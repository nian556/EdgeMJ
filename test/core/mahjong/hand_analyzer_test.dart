import 'package:edge_mj/core/mahjong/mahjong.dart';
import 'package:flutter_test/flutter_test.dart';

const taiwan = MahjongRules.taiwan;
const hongKong = MahjongRules.hongKong;
const japanese = MahjongRules.japanese;

/// 小工具：直接用簡寫字串算聽牌，回傳簡寫字串清單（預設用日本牌規則）
List<String> waits(String hand, [MahjongRules rules = japanese]) =>
    HandAnalyzer(rules).waitingTiles(parseTiles(hand)).map((t) => t.notation).toList();

Set<WinPattern> patterns(String hand, [MahjongRules rules = japanese]) =>
    HandAnalyzer(rules).winPatterns(parseTiles(hand));

void main() {
  test('沒指定規則時預設是台灣牌', () {
    expect(const HandAnalyzer().rules, same(taiwan));
    expect(MahjongRules.presets.first, same(taiwan));
  });

  group('13 張聽牌：基本聽型', () {
    test('兩面聽（23m → 聽 1m、4m）', () {
      expect(waits('23m456p789s111z22z'), ['1m', '4m']);
    });

    test('嵌張（13m → 聽 2m）', () {
      expect(waits('13m456p789s111z22z'), ['2m']);
    });

    test('邊張（12m → 聽 3m）', () {
      expect(waits('12m456p789s111z22z'), ['3m']);
    });

    test('對碰（11m、22p → 聽 1m、2p）', () {
      expect(waits('11m345m22p456s789s'), ['1m', '2p']);
    });

    test('單騎（字牌）', () {
      expect(waits('111z222z333z444z5z'), ['5z']);
    });

    test('單騎 + 延伸（1234p → 聽 1p、4p）', () {
      expect(waits('123m456m789m1234p'), ['1p', '4p']);
    });

    test('1112m → 聽 2m（單騎）與 3m（11 將 + 123 順）', () {
      expect(waits('1112m456p789p123s'), ['2m', '3m']);
    });

    test('九蓮寶燈 → 聽 1~9 萬', () {
      expect(waits('1112345678999m'),
          ['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m']);
    });

    test('多面聽（2345678m → 聽 2、5、8 萬）', () {
      expect(waits('2345678m111p222s'), ['2m', '5m', '8m']);
    });
  });

  group('香港牌 / 日本牌：特殊牌型', () {
    for (final rules in [hongKong, japanese]) {
      test('${rules.name}：七對子單騎', () {
        final result = HandAnalyzer(rules)
            .waitingTilesWithPatterns(parseTiles('1122m3344p5566s7z'));
        expect(result.keys.map((t) => t.notation), ['7z']);
        expect(result.values.single, {WinPattern.sevenPairs});
      });

      test('${rules.name}：十三么 13 面聽', () {
        expect(waits('19m19p19s1234567z', rules), [
          '1m', '9m', '1p', '9p', '1s', '9s',
          '1z', '2z', '3z', '4z', '5z', '6z', '7z',
        ]);
      });
    }

    test('國士無雙單騎（缺白 → 聽白）', () {
      final result = HandAnalyzer(japanese)
          .waitingTilesWithPatterns(parseTiles('19m19p19s1234566z'));
      expect(result.keys.single.displayName, '白');
      expect(result.values.single, {WinPattern.thirteenOrphans});
    });

    test('手牌超過 13 張會丟出 ArgumentError', () {
      expect(() => waits('1112345678999m123p', japanese), throwsArgumentError);
      expect(() => waits('1112345678999m123p', hongKong), throwsArgumentError);
      expect(() => patterns('11123456789999m123p', japanese), throwsArgumentError);
    });
  });

  group('台灣牌（16 張）', () {
    test('16 張單騎', () {
      expect(waits('123m456m789m123p456p1s', taiwan), ['1s']);
    });

    test('16 張九蓮 + 一組順子 → 聽 1~9 萬', () {
      expect(waits('1112345678999m123p', taiwan),
          ['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m']);
    });

    test('17 張胡牌判定', () {
      expect(patterns('123m456m789m123p456p11s', taiwan), {WinPattern.standard});
    });

    test('有吃碰後剩 13 張也能計算', () {
      expect(waits('23m456p789s111z22z', taiwan), ['1m', '4m']);
    });

    test('台灣牌不算特殊牌型（8 組對子不聽牌）', () {
      expect(waits('99m11223344556677z', taiwan), isEmpty);
    });

    test('台灣牌不算七對子與十三么', () {
      expect(waits('1122m3344p5566s7z', taiwan), isEmpty);
      expect(waits('19m19p19s1234567z', taiwan), isEmpty);
    });
  });

  group('不聽牌與邊界情況', () {
    test('完全散牌 → 不聽', () {
      expect(waits('1357m2468p13579s'), isEmpty);
      expect(HandAnalyzer(japanese).isTenpai(parseTiles('1357m2468p13579s')), isFalse);
    });

    test('唯一要等的牌手上已有 4 張 → 不算聽牌', () {
      // 5555m 只能單騎 5m，但 5m 已經用完
      expect(waits('5555m123p456p789p'), isEmpty);
    });

    test('有吃碰後只剩 10 張也能計算', () {
      expect(waits('23m456p789s22z'), ['1m', '4m']);
    });

    test('只剩 1 張（單騎）', () {
      expect(waits('5z'), ['5z']);
    });

    test('張數不是 3n+1 會丟出 ArgumentError', () {
      expect(() => waits('123m456p789s111z'), throwsArgumentError); // 12 張
      expect(() => waits('123m456p789s1111z2z'), throwsArgumentError); // 14 張
    });

    test('同一種牌超過 4 張會丟出 ArgumentError', () {
      expect(() => waits('11111m23m456p789p'), throwsArgumentError);
    });
  });

  group('胡牌判定（14 張）', () {
    test('一般胡牌', () {
      expect(patterns('123m456p789s111z22z'), {WinPattern.standard});
    });

    test('同時符合一般牌型與七對子', () {
      expect(patterns('11223344556677m'),
          {WinPattern.standard, WinPattern.sevenPairs});
    });

    test('4 張相同不能當成兩組對子', () {
      expect(patterns('1111m2233p4455s66z'), isEmpty);
    });

    test('字牌不能組順子', () {
      expect(patterns('123z456p789s111m22m'), isEmpty);
    });

    test('順子不能跨花色（89m + 1p 不是順子）', () {
      expect(patterns('89m1p456p789s111z22z'), isEmpty);
    });

    test('張數不是 3n+2 會丟出 ArgumentError', () {
      expect(() => patterns('1112345678999m'), throwsArgumentError);
    });
  });

  group('一致性檢查', () {
    test('三種規則下：聽的牌加進來都能胡；不聽的牌加進來都不能胡', () {
      const hands13 = [
        '1112345678999m',
        '2223334445556m',
        '1234567m11p234s9s',
        '3334555m11p22s77z',
        '1122m3344p5566s7z',
        '19m19p19s1234567z',
      ];
      const hands16 = [
        '1112345678999m123p',
        '99m11223344556677z',
        '2223334445556m789s',
      ];
      for (final rules in MahjongRules.presets) {
        final analyzer = HandAnalyzer(rules);
        final hands = rules.handSize == 16 ? [...hands13, ...hands16] : hands13;
        for (final hand in hands) {
          final tiles = parseTiles(hand);
          final waitSet = analyzer.waitingTiles(tiles).toSet();
          final counts = List<int>.filled(Tile.kinds, 0);
          for (final t in tiles) {
            counts[t.id]++;
          }
          for (final candidate in Tile.values) {
            if (counts[candidate.id] >= 4) continue;
            final win = analyzer.isWinningHand([...tiles, candidate]);
            expect(win, waitSet.contains(candidate),
                reason: '${rules.name} $hand + ${candidate.notation}');
          }
        }
      }
    });
  });
}
