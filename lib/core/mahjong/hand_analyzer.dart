/// 麻將胡牌與聽牌判定（純 Dart，無 Flutter 相依，可在任何平台離線執行）。
///
/// 核心做法：
///   1. 把手牌轉成長度 34 的「張數陣列」counts[id]。
///   2. 一般胡牌（n 組面子 + 1 組將）：
///      先枚舉將牌，再用遞迴檢查剩下的牌能否全部拆成順子或刻子。
///      遞迴每次只看「最小的那張牌」，它只可能是刻子或順子的開頭，
///      因此不會漏解也不會重複搜尋，速度非常快。
///   3. 聽牌：對 34 種牌逐一「假設摸進來」，再判斷是否胡牌。
///
/// 支援台灣 16 張、香港 13 張、日本 13 張（見 [MahjongRules]）。
/// 已吃碰槓的牌不用傳入，只要傳入「手上剩下的牌」即可（例如碰了一組，就傳 10 張）。
library;

import 'tile.dart';

/// 胡牌牌型
enum WinPattern {
  /// 一般牌型：n 組面子（順子/刻子）+ 1 組將
  standard('一般牌型'),

  /// 七對子：7 組「不同」的對子（僅限 14 張）
  sevenPairs('七對子'),

  /// 國士無雙（十三么）：13 種么九牌各一張，其中一種成對（僅限 14 張）
  thirteenOrphans('國士無雙');

  const WinPattern(this.label);

  /// 中文名稱
  final String label;
}

/// 規則設定：手牌張數與承認哪些特殊牌型。
///
/// 香港牌與日本牌在「聽哪些牌」上的判定相同（差別在算番／役），
/// 先分開成兩個選項，之後加入計分功能時就能各自擴充。
class MahjongRules {
  const MahjongRules({
    required this.name,
    required this.handSize,
    this.allowSevenPairs = false,
    this.allowThirteenOrphans = false,
  });

  /// 台灣 16 張麻將：只看一般牌型
  static const MahjongRules taiwan = MahjongRules(name: '台灣牌', handSize: 16);

  /// 香港 13 張麻將：一般牌型 + 七對子 + 十三么
  static const MahjongRules hongKong = MahjongRules(
      name: '香港牌', handSize: 13, allowSevenPairs: true, allowThirteenOrphans: true);

  /// 日本 13 張麻將（立直麻將）：一般牌型 + 七對子 + 國士無雙
  static const MahjongRules japanese = MahjongRules(
      name: '日本牌', handSize: 13, allowSevenPairs: true, allowThirteenOrphans: true);

  /// 畫面上可切換的規則（第一個是預設）
  static const List<MahjongRules> presets = [taiwan, hongKong, japanese];

  /// 顯示名稱
  final String name;

  /// 沒有吃碰時的手牌張數（13 或 16）
  final int handSize;

  final bool allowSevenPairs;
  final bool allowThirteenOrphans;
}

class HandAnalyzer {
  const HandAnalyzer([this.rules = MahjongRules.taiwan]);

  final MahjongRules rules;

  /// 判斷 3n+2 張牌是否胡牌
  bool isWinningHand(List<Tile> tiles) => winPatterns(tiles).isNotEmpty;

  /// 回傳 3n+2 張牌符合的所有胡牌牌型（不胡則為空集合）
  Set<WinPattern> winPatterns(List<Tile> tiles) {
    if (tiles.length % 3 != 2) {
      throw ArgumentError('胡牌判定需要 3n+2 張牌（例如 14 張），目前是 ${tiles.length} 張');
    }
    if (tiles.length > rules.handSize + 1) {
      throw ArgumentError('${rules.name}胡牌最多 ${rules.handSize + 1} 張，目前是 ${tiles.length} 張');
    }
    return _winPatterns(_toCounts(tiles), tiles.length);
  }

  /// 計算 3n+1 張牌（例如 13 張）聽哪些牌，結果依牌的 id 排序。
  ///
  /// 若某張牌手上已經有 4 張，就不可能再摸到第 5 張，所以不算在聽牌內。
  List<Tile> waitingTiles(List<Tile> tiles) =>
      waitingTilesWithPatterns(tiles).keys.toList();

  /// 是否聽牌
  bool isTenpai(List<Tile> tiles) => waitingTiles(tiles).isNotEmpty;

  /// 計算聽哪些牌，並附上每張牌胡的是哪些牌型
  Map<Tile, Set<WinPattern>> waitingTilesWithPatterns(List<Tile> tiles) {
    if (tiles.length % 3 != 1) {
      throw ArgumentError('聽牌計算需要 3n+1 張牌（例如 13 或 16 張），目前是 ${tiles.length} 張');
    }
    if (tiles.length > rules.handSize) {
      throw ArgumentError('${rules.name}手牌最多 ${rules.handSize} 張，目前是 ${tiles.length} 張');
    }
    final counts = _toCounts(tiles);
    final result = <Tile, Set<WinPattern>>{};
    for (var id = 0; id < Tile.kinds; id++) {
      if (counts[id] >= 4) continue; // 已經 4 張，不可能再摸到
      counts[id]++;
      final patterns = _winPatterns(counts, tiles.length + 1);
      counts[id]--;
      if (patterns.isNotEmpty) result[Tile(id)] = patterns;
    }
    return result;
  }

  // ───────────────────────── 內部實作 ─────────────────────────

  /// 轉成張數陣列，並檢查同一種牌不超過 4 張
  static List<int> _toCounts(List<Tile> tiles) {
    final counts = List<int>.filled(Tile.kinds, 0);
    for (final t in tiles) {
      if (++counts[t.id] > 4) {
        throw ArgumentError('牌 ${t.notation}（${t.displayName}）超過 4 張');
      }
    }
    return counts;
  }

  Set<WinPattern> _winPatterns(List<int> counts, int total) {
    final patterns = <WinPattern>{};
    if (_isStandardWin(counts)) patterns.add(WinPattern.standard);
    if (total == 14) {
      if (rules.allowSevenPairs && _isSevenPairs(counts)) {
        patterns.add(WinPattern.sevenPairs);
      }
      if (rules.allowThirteenOrphans && _isThirteenOrphans(counts)) {
        patterns.add(WinPattern.thirteenOrphans);
      }
    }
    return patterns;
  }

  /// 一般牌型：枚舉將牌，剩下的牌必須全部組成面子
  static bool _isStandardWin(List<int> counts) {
    for (var id = 0; id < Tile.kinds; id++) {
      if (counts[id] < 2) continue;
      counts[id] -= 2;
      final ok = _suitsDivisibleByThree(counts) && _canFormMelds(counts, 0);
      counts[id] += 2;
      if (ok) return true;
    }
    return false;
  }

  /// 快速剪枝：每個花色的張數都必須是 3 的倍數，才可能全拆成面子
  static bool _suitsDivisibleByThree(List<int> counts) {
    for (var start = 0; start < Tile.kinds; start += 9) {
      var sum = 0;
      final end = start + 9 > Tile.kinds ? Tile.kinds : start + 9;
      for (var i = start; i < end; i++) {
        sum += counts[i];
      }
      if (sum % 3 != 0) return false;
    }
    return true;
  }

  /// 遞迴檢查：從 [from] 開始的牌能否全部拆成順子或刻子。
  /// 會暫時修改 counts，回傳前一定還原。
  static bool _canFormMelds(List<int> counts, int from) {
    // 找到最小的一張還有剩的牌
    var i = from;
    while (i < Tile.kinds && counts[i] == 0) {
      i++;
    }
    if (i == Tile.kinds) return true; // 全部拆完

    // 嘗試一：當作刻子
    if (counts[i] >= 3) {
      counts[i] -= 3;
      final ok = _canFormMelds(counts, i);
      counts[i] += 3;
      if (ok) return true;
    }

    // 嘗試二：當作順子開頭（字牌不能組順子；8、9 不能當順子開頭）
    if (i < 27 && i % 9 <= 6 && counts[i + 1] > 0 && counts[i + 2] > 0) {
      counts[i]--;
      counts[i + 1]--;
      counts[i + 2]--;
      final ok = _canFormMelds(counts, i);
      counts[i]++;
      counts[i + 1]++;
      counts[i + 2]++;
      if (ok) return true;
    }
    return false;
  }

  /// 七對子：剛好 7 種牌各 2 張（4 張相同不算兩對）
  static bool _isSevenPairs(List<int> counts) {
    var pairs = 0;
    for (final c in counts) {
      if (c == 2) {
        pairs++;
      } else if (c != 0) {
        return false;
      }
    }
    return pairs == 7;
  }

  /// 國士無雙：13 種么九牌都有，且只有么九牌
  static bool _isThirteenOrphans(List<int> counts) {
    var total = 0;
    for (final id in Tile.terminalAndHonorIds) {
      if (counts[id] == 0) return false;
      total += counts[id];
    }
    return total == 14; // 代表其他牌都是 0 張
  }
}
