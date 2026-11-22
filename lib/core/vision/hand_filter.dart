/// 手牌過濾：把「不像手牌」的辨識框剔除，並檢查結果是否合理（純 Dart）。
///
/// 做法：
///   1. 一個位置只留一張牌：兩個框位置幾乎重疊（牌頂白色被認成白板、
///      一張七條被拆成兩張……），只留一個，並標記成「需確認」
///   2. 大小過濾：面積小於「中位數 × [minAreaRatio]」的框剔除（牌尺文字、遠處海底牌通常比較小）
///   3. 同一排檢查：手牌排成一橫排，中心高度和這一排差太多的框剔除
///   4. 信心偏低的牌也標記成「需確認」
///   5. 張數檢查：不偷偷刪牌，只產生提醒訊息
///
/// 用「中位數」而不是「平均值」：海底牌很多時，平均值會被拉低，過濾就失效。
library;

import 'dart:math' as math;

import 'tile_reading.dart';
import 'yolo_decoder.dart';

/// 白板的類別編號
const int whiteDragonClassId = 33;

/// 過濾後的結果
class HandFilterResult {
  const HandFilterResult({
    required this.kept,
    required this.removed,
    this.uncertain = const {},
  });

  /// 留下來的框（當作手牌）
  final List<Detection> kept;

  /// 被剔除的框（畫面上用灰色顯示，讓使用者知道丟了哪些）
  final List<Detection> removed;

  /// kept 之中「需要使用者確認」的框（信心偏低，或和別的框搶同一個位置）
  final Set<Detection> uncertain;
}

/// 少於這個數量就不做過濾（框太少時中位數不可靠）
const int _minBoxesToFilter = 3;

/// 依位置、大小與「同一排」剔除不像手牌的框。
///
/// [minAreaRatio]：面積小於中位數的幾倍就剔除（預設 0.5）
/// [maxRowOffset]：中心高度和這一排相差超過「牌高 × 幾倍」就剔除（預設 0.6）
/// [samePositionRatio]：兩個框中心的水平距離小於「牌寬 × 幾倍」就算同一個位置（預設 0.6）
/// [lowConfidence]：信心低於這個值就標記「需確認」（預設 0.6）
HandFilterResult filterHandDetections(
  List<Detection> detections, {
  double minAreaRatio = 0.5,
  double maxRowOffset = 0.6,
  double samePositionRatio = 0.6,
  double lowConfidence = 0.6,
}) {
  final uncertain = <Detection>{
    for (final d in detections)
      if (d.score < lowConfidence) d,
  };
  if (detections.length < _minBoxesToFilter) {
    return HandFilterResult(kept: [...detections], removed: const [], uncertain: uncertain);
  }
  final removed = <Detection>[];

  // 1. 一個位置只留一張牌
  final deduped = _dedupeSamePosition(detections, samePositionRatio, removed, uncertain);

  // 2. 大小過濾
  final medianArea = _median(deduped.map((d) => d.area));
  final bySize = <Detection>[];
  for (final d in deduped) {
    (d.area >= medianArea * minAreaRatio ? bySize : removed).add(d);
  }

  // 3. 同一排檢查（用剩下的框算這一排的高度位置）
  final kept = <Detection>[];
  if (bySize.length < _minBoxesToFilter) {
    kept.addAll(bySize);
  } else {
    final rowY = _median(bySize.map((d) => d.centerY));
    final tileHeight = _median(bySize.map((d) => d.height));
    for (final d in bySize) {
      final offset = (d.centerY - rowY).abs();
      (offset <= tileHeight * maxRowOffset ? kept : removed).add(d);
    }
  }
  uncertain.retainAll(kept);
  return HandFilterResult(kept: kept, removed: removed, uncertain: uncertain);
}

/// 把「搶同一個位置」的框分成一組，每組只留一個。
///
/// 同一個位置的判斷（符合任一個）：
///   - 中心水平距離 < 牌寬 × [ratio]，且上下有重疊或幾乎相連（例如牌頂白框疊在牌上面）
///   - 一個框大部分（> 50%）被另一個框蓋住
///
/// 每組留下的優先順序：不是白板 → 大小最接近正常牌 → 信心高。
/// 有被合併過的框會加進 [uncertain]，提醒使用者確認。
List<Detection> _dedupeSamePosition(
  List<Detection> detections,
  double ratio,
  List<Detection> removed,
  Set<Detection> uncertain,
) {
  final tileWidth = _median(detections.map((d) => d.width));
  final tileHeight = _median(detections.map((d) => d.height));
  final medianArea = _median(detections.map((d) => d.area));

  bool samePosition(Detection a, Detection b) {
    final dx = (a.centerX - b.centerX).abs();
    // 上下的間隙（負數 = 有重疊）
    final gapY = math.max(a.top, b.top) - math.min(a.bottom, b.bottom);
    if (dx < tileWidth * ratio && gapY < tileHeight * 0.25) return true;
    return _overlapOfSmaller(a, b) > 0.5;
  }

  // 分組：會互相連到的框放在同一組
  final groupOf = List<int>.generate(detections.length, (i) => i);
  int find(int i) => groupOf[i] == i ? i : groupOf[i] = find(groupOf[i]);
  for (var i = 0; i < detections.length; i++) {
    for (var j = i + 1; j < detections.length; j++) {
      if (samePosition(detections[i], detections[j])) groupOf[find(i)] = find(j);
    }
  }
  final groups = <int, List<Detection>>{};
  for (var i = 0; i < detections.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(detections[i]);
  }

  final kept = <Detection>[];
  for (final group in groups.values) {
    if (group.length == 1) {
      kept.add(group.single);
      continue;
    }
    // 越前面越優先：不是白板 → 面積最接近中位數 → 信心高
    group.sort((a, b) {
      final aWhite = a.classId == whiteDragonClassId ? 1 : 0;
      final bWhite = b.classId == whiteDragonClassId ? 1 : 0;
      if (aWhite != bWhite) return aWhite - bWhite;
      final aDiff = (math.log(a.area / medianArea)).abs();
      final bDiff = (math.log(b.area / medianArea)).abs();
      if ((aDiff - bDiff).abs() > 0.1) return aDiff.compareTo(bDiff);
      return b.score.compareTo(a.score);
    });
    kept.add(group.first);
    uncertain.add(group.first);
    removed.addAll(group.skip(1));
  }
  return kept;
}

/// 交集面積 ÷ 較小那個框的面積（小框被大框蓋住多少）
double _overlapOfSmaller(Detection a, Detection b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final smaller = math.min(a.area, b.area);
  return smaller <= 0 ? 0 : w * h / smaller;
}

/// 檢查辨識結果是否合理，回傳要提醒使用者的訊息（沒問題就回傳空清單）。
///
/// [handSize]：規則的手牌張數（台灣 16、香港／日本 13），摸牌後最多多 1 張
List<String> checkHandWarnings(List<Detection> detections, {required int handSize}) {
  final warnings = <String>[];
  final tiles = detections.where((d) => d.classId < firstFlowerClassId).toList();

  final maxTiles = handSize + 1;
  if (tiles.length > maxTiles) {
    warnings.add('認到 ${tiles.length} 張，超過 $maxTiles 張，可能把其他牌也算進來了，'
        '請縮小框或調整角度');
  } else if (tiles.isNotEmpty && tiles.length % 3 == 0) {
    // 相公檢查：每吃碰槓一組手牌少 3 張（槓完會補牌，張數一樣），
    // 所以正確張數一定是「3 的倍數 +1」（等摸牌）或「+2」（剛摸牌）。
    // 剛好是 3 的倍數（3、6、9、12、15…）就一定多一張或少一張。
    warnings.add('手牌 ${tiles.length} 張，可能相公（多一張或少一張）。'
        '也可能有牌沒認到或多認了，請檢查一下');
  }

  // 同一種牌最多 4 張，超過一定有認錯
  final counts = <int, int>{};
  for (final d in tiles) {
    counts[d.classId] = (counts[d.classId] ?? 0) + 1;
  }
  for (final MapEntry(key: classId, value: n) in counts.entries) {
    if (n > 4) {
      warnings.add('「${classDisplayName(classId)}」認到 $n 張（最多只有 4 張），有些牌認錯了');
    }
  }
  return warnings;
}

/// 中位數（排序後取中間；偶數個取中間兩個的平均）
double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}
