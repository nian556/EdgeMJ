import '../core/mahjong/mahjong.dart';

/// 把聽牌結果轉成文字，例如「聽：一萬、白（國士無雙）」。
/// 兩個頁面（手動輸入、拍照辨識）共用。
String describeWaits(Map<Tile, Set<WinPattern>> waits) => waits.isEmpty
    ? '沒有聽牌'
    : '聽：${waits.entries.map(_describeWait).join('、')}';

/// 例如「白（國士無雙）」；一般牌型就只顯示牌名
String _describeWait(MapEntry<Tile, Set<WinPattern>> wait) {
  final special = wait.value
      .where((p) => p != WinPattern.standard)
      .map((p) => p.label);
  return special.isEmpty
      ? wait.key.displayName
      : '${wait.key.displayName}（${special.join('/')}）';
}

/// 計算聽牌並轉成文字；張數不對等錯誤也轉成提示文字
String calculateWaitText(List<Tile> tiles, MahjongRules rules) {
  try {
    return describeWaits(HandAnalyzer(rules).waitingTilesWithPatterns(tiles));
  } on ArgumentError catch (e) {
    return '${e.message}';
  }
}
