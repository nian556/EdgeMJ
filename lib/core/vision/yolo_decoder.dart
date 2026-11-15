/// 解讀 YOLOv8 模型的原始輸出（純 Dart，無 Flutter 相依，方便寫測試）。
///
/// 模型輸出 [1, 46, 8400]：
///   - 46 = 4 個座標（中心x、中心y、寬、高，以 640×640 輸入的像素為單位）+ 42 個類別分數
///   - 8400 = 候選框數量
/// 排列方式是「先排完所有框的中心x，再排所有框的中心y……」，
/// 所以第 k 個數值、第 i 個框在 output[k * 8400 + i]。
///
/// 參考實作：ml/scripts/evaluate.py 的 decode()
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 一個辨識結果：框的位置（原圖像素）、類別、分數
class Detection {
  const Detection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.classId,
    required this.score,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// 類別編號：0~33 對應 Tile id；34~41 是花牌（春夏秋冬梅蘭菊竹）
  final int classId;

  /// 信心分數 0~1
  final double score;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get area => math.max(0, width) * math.max(0, height);

  @override
  String toString() =>
      'Detection(class=$classId, score=${score.toStringAsFixed(2)}, '
      '[${left.round()}, ${top.round()}, ${right.round()}, ${bottom.round()}])';
}

/// 等比例縮放（letterbox）的資訊，用來把框還原回原圖座標
class LetterboxInfo {
  const LetterboxInfo({required this.ratio, required this.padX, required this.padY});

  /// 縮放比例（模型輸入 ÷ 原圖）
  final double ratio;

  /// 左邊補了幾個像素
  final int padX;

  /// 上面補了幾個像素
  final int padY;

  /// 依原圖大小計算 letterbox 參數（和 evaluate.py 的 letterbox() 相同算法）
  factory LetterboxInfo.compute(int imageWidth, int imageHeight, int inputSize) {
    final ratio = math.min(inputSize / imageHeight, inputSize / imageWidth);
    final newW = (imageWidth * ratio).round();
    final newH = (imageHeight * ratio).round();
    return LetterboxInfo(
      ratio: ratio,
      padX: (inputSize - newW) ~/ 2,
      padY: (inputSize - newH) ~/ 2,
    );
  }

  /// 縮放後（不含補邊）的寬
  int scaledWidth(int imageWidth) => (imageWidth * ratio).round();

  /// 縮放後（不含補邊）的高
  int scaledHeight(int imageHeight) => (imageHeight * ratio).round();
}

/// 兩個框的重疊程度（IoU：交集面積 ÷ 聯集面積），0 = 不重疊、1 = 完全重疊
double intersectionOverUnion(Detection a, Detection b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final inter = w * h;
  return inter / (a.area + b.area - inter);
}

/// 去除重疊框（NMS）：分數高的優先保留，和它重疊太多的框就丟掉。
///
/// 這裡「不分類別」一起比：一張實體牌只該算一次，
/// 就算模型同時猜它是「三萬」和「五萬」，也只留分數高的那個。
List<Detection> nonMaxSuppression(List<Detection> detections, double iouThreshold) {
  final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <Detection>[];
  for (final d in sorted) {
    if (kept.every((k) => intersectionOverUnion(k, d) <= iouThreshold)) {
      kept.add(d);
    }
  }
  return kept;
}

/// 把模型原始輸出轉成辨識結果（座標已還原到原圖像素）。
List<Detection> decodeYoloOutput(
  Float32List output, {
  required LetterboxInfo letterbox,
  int numClasses = 42,
  int numBoxes = 8400,
  double confThreshold = 0.25,
  double iouThreshold = 0.5,
}) {
  final expected = (4 + numClasses) * numBoxes;
  if (output.length != expected) {
    throw ArgumentError('模型輸出長度應為 $expected，實際是 ${output.length}');
  }

  final candidates = <Detection>[];
  for (var i = 0; i < numBoxes; i++) {
    // 找出這個框分數最高的類別
    var bestClass = 0;
    var bestScore = output[4 * numBoxes + i];
    for (var c = 1; c < numClasses; c++) {
      final s = output[(4 + c) * numBoxes + i];
      if (s > bestScore) {
        bestScore = s;
        bestClass = c;
      }
    }
    if (bestScore <= confThreshold) continue;

    final cx = output[i];
    final cy = output[numBoxes + i];
    final w = output[2 * numBoxes + i];
    final h = output[3 * numBoxes + i];
    // 去掉補邊、除以縮放比例 → 還原成原圖座標
    double toX(double x) => (x - letterbox.padX) / letterbox.ratio;
    double toY(double y) => (y - letterbox.padY) / letterbox.ratio;
    candidates.add(Detection(
      left: toX(cx - w / 2),
      top: toY(cy - h / 2),
      right: toX(cx + w / 2),
      bottom: toY(cy + h / 2),
      classId: bestClass,
      score: bestScore,
    ));
  }
  return nonMaxSuppression(candidates, iouThreshold);
}
