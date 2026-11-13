/// 麻將牌的基本定義。
///
/// 34 種牌以 0~33 的整數 id 表示：
///   0~8   ：一萬 ~ 九萬   (m)
///   9~17  ：一筒 ~ 九筒   (p)
///   18~26 ：一條 ~ 九條   (s)
///   27~33 ：東 南 西 北 中 發 白 (z，對應 1z~7z)
///
/// 這個順序也會用在階段二 YOLO 的 class id，讓辨識結果可直接轉成 Tile。
library;

/// 花色
enum Suit {
  man('m', '萬'),
  pin('p', '筒'),
  sou('s', '條'),
  honor('z', '');

  const Suit(this.code, this.label);

  /// 簡寫代碼（m / p / s / z）
  final String code;

  /// 中文名稱
  final String label;
}

class Tile implements Comparable<Tile> {
  const Tile._(this.id);

  /// 依 id 取得牌（每種牌只有一個實例）
  factory Tile(int id) {
    if (id < 0 || id >= kinds) {
      throw RangeError.range(id, 0, kinds - 1, 'id');
    }
    return values[id];
  }

  /// 依花色與數字取得牌，例如 Tile.of(Suit.man, 5) = 五萬、Tile.of(Suit.honor, 1) = 東
  factory Tile.of(Suit suit, int number) {
    final max = suit == Suit.honor ? 7 : 9;
    if (number < 1 || number > max) {
      throw RangeError.range(number, 1, max, 'number');
    }
    return Tile(suit.index * 9 + number - 1);
  }

  /// 牌的種類數
  static const int kinds = 34;

  /// 全部 34 種牌，依 id 排序
  static final List<Tile> values =
      List.unmodifiable(List.generate(kinds, Tile._));

  /// 么九牌（國士無雙需要的 13 種）：1、9 萬筒條 + 7 種字牌
  static const List<int> terminalAndHonorIds = [
    0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33,
  ];

  static const List<String> _honorNames = ['東', '南', '西', '北', '中', '發', '白'];
  static const List<String> _chineseNumbers = [
    '一', '二', '三', '四', '五', '六', '七', '八', '九',
  ];

  final int id;

  Suit get suit => Suit.values[id ~/ 9];

  /// 牌面數字：數牌 1~9；字牌 1~7（東南西北中發白）
  int get number => id % 9 + 1;

  bool get isHonor => id >= 27;

  /// 老頭牌（數牌的 1 或 9）
  bool get isTerminal => !isHonor && (number == 1 || number == 9);

  /// 簡寫，例如 "5m"、"1z"
  String get notation => '$number${suit.code}';

  /// 中文名稱，例如「五萬」、「東」
  String get displayName =>
      isHonor ? _honorNames[number - 1] : '${_chineseNumbers[number - 1]}${suit.label}';

  @override
  int compareTo(Tile other) => id.compareTo(other.id);

  @override
  bool operator ==(Object other) => other is Tile && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => notation;
}

/// 把簡寫字串轉成牌的清單。
///
/// 格式：數字寫在花色代碼前面，例如
///   "123m456p789s11z"  → 一二三萬、四五六筒、七八九條、東東
/// 空白會被忽略。
List<Tile> parseTiles(String text) {
  final result = <Tile>[];
  final pendingNumbers = <int>[];
  for (final ch in text.replaceAll(RegExp(r'\s'), '').split('')) {
    final digit = int.tryParse(ch);
    if (digit != null) {
      pendingNumbers.add(digit);
      continue;
    }
    final suit = Suit.values.where((s) => s.code == ch).firstOrNull;
    if (suit == null) {
      throw FormatException('無法辨識的字元 "$ch"', text);
    }
    if (pendingNumbers.isEmpty) {
      throw FormatException('花色 "$ch" 前面沒有數字', text);
    }
    for (final n in pendingNumbers) {
      try {
        result.add(Tile.of(suit, n));
      } on RangeError {
        throw FormatException('不合法的牌 "$n$ch"', text);
      }
    }
    pendingNumbers.clear();
  }
  if (pendingNumbers.isNotEmpty) {
    throw FormatException('結尾的數字缺少花色代碼', text);
  }
  return result;
}

/// 把牌的清單轉回簡寫字串（會先排序），例如 [1m,2m,3m,1z] → "123m1z"
String tilesToNotation(Iterable<Tile> tiles) {
  final sorted = tiles.toList()..sort();
  final buffer = StringBuffer();
  for (final suit in Suit.values) {
    final numbers = sorted.where((t) => t.suit == suit).map((t) => t.number);
    if (numbers.isNotEmpty) buffer.write('${numbers.join()}${suit.code}');
  }
  return buffer.toString();
}
