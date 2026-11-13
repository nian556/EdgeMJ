import 'package:edge_mj/core/mahjong/mahjong.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tile 編碼', () {
    test('id 對應正確的花色與數字', () {
      expect(Tile(0).notation, '1m');
      expect(Tile(8).notation, '9m');
      expect(Tile(9).notation, '1p');
      expect(Tile(26).notation, '9s');
      expect(Tile(27).displayName, '東');
      expect(Tile(33).displayName, '白');
      expect(Tile(4).displayName, '五萬');
    });

    test('Tile.of 與 id 一致', () {
      expect(Tile.of(Suit.pin, 5).id, 13);
      expect(Tile.of(Suit.honor, 5).displayName, '中');
    });

    test('超出範圍會丟出錯誤', () {
      expect(() => Tile(34), throwsRangeError);
      expect(() => Tile.of(Suit.honor, 8), throwsRangeError);
    });

    test('么九判斷', () {
      expect(Tile(0).isTerminal, isTrue);
      expect(Tile(4).isTerminal, isFalse);
      expect(Tile(30).isHonor, isTrue);
      expect(Tile(30).isTerminal, isFalse);
    });
  });

  group('parseTiles / tilesToNotation', () {
    test('解析簡寫', () {
      final tiles = parseTiles('123m 1z');
      expect(tiles.map((t) => t.id), [0, 1, 2, 27]);
    });

    test('轉回簡寫時會排序', () {
      expect(tilesToNotation(parseTiles('1z9s321m')), '123m9s1z');
    });

    test('不合法的輸入會丟出 FormatException', () {
      expect(() => parseTiles('8z'), throwsFormatException);
      expect(() => parseTiles('123'), throwsFormatException);
      expect(() => parseTiles('12x'), throwsFormatException);
      expect(() => parseTiles('m'), throwsFormatException);
      expect(() => parseTiles('0m'), throwsFormatException);
    });
  });
}
