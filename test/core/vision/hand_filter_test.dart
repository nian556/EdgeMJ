import 'dart:typed_data';

import 'package:edge_mj/core/vision/hand_filter.dart';
import 'package:edge_mj/core/vision/preprocess.dart';
import 'package:edge_mj/core/vision/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 一張牌：左上角 (x, y)，預設 40×60 大小
Detection tile(double x, double y, {double w = 40, double h = 60, int cls = 0}) =>
    Detection(left: x, top: y, right: x + w, bottom: y + h, classId: cls, score: 0.9);

/// 一排手牌：從 x=0 開始，每張間隔 42 像素
List<Detection> handRow(int n, {double y = 500}) =>
    [for (var i = 0; i < n; i++) tile(i * 42.0, y, cls: i % 34)];

void main() {
  group('filterHandDetections', () {
    test('整齊的一排手牌全部保留', () {
      final r = filterHandDetections(handRow(16));
      expect(r.kept.length, 16);
      expect(r.removed, isEmpty);
    });

    test('太小的框（牌尺文字）被剔除', () {
      final small = tile(100, 510, w: 15, h: 20);
      final r = filterHandDetections([...handRow(16), small]);
      expect(r.kept.length, 16);
      expect(r.removed, [small]);
    });

    test('不在同一排的牌（海底牌）被剔除，即使大小差不多', () {
      final river = [tile(100, 100), tile(150, 100), tile(200, 100)];
      final r = filterHandDetections([...handRow(16), ...river]);
      expect(r.kept.length, 16);
      expect(r.removed.length, 3);
    });

    test('海底小牌很多時，用中位數仍能正確過濾', () {
      // 10 張小的海底牌 + 16 張手牌：平均面積會被拉低，中位數不會
      final river = [for (var i = 0; i < 10; i++) tile(i * 25.0, 100, w: 20, h: 30)];
      final r = filterHandDetections([...handRow(16), ...river]);
      expect(r.kept.length, 16);
      expect(r.removed.length, 10);
    });

    test('規則 A：牌頂白色被認成白板（疊在牌上方）→ 丟掉白板，保留的牌標記需確認', () {
      final hand = handRow(16);
      final target = hand[5]; // x = 210~250，y = 500~560
      final whiteTop = tile(212, 470, w: 38, h: 32, cls: whiteDragonClassId);
      final r = filterHandDetections([...hand, whiteTop]);
      expect(r.kept.length, 16);
      expect(r.removed, [whiteTop]);
      expect(r.uncertain, {target});
    });

    test('規則 A：白板就算信心比較高，疊在別的牌上也優先丟白板', () {
      final hand = handRow(16);
      final whiteTop = Detection(
          left: 210, top: 480, right: 250, bottom: 530, classId: whiteDragonClassId, score: 0.99);
      final r = filterHandDetections([...hand, whiteTop]);
      expect(r.removed, contains(whiteTop));
      expect(r.kept, contains(hand[5]));
    });

    test('規則 A：一張七條被拆成上下兩半 → 只留一張', () {
      final hand = handRow(15);
      final top = tile(15 * 42.0, 500, h: 30, cls: 3);
      final bottom = tile(15 * 42.0, 530, h: 30, cls: 3);
      final r = filterHandDetections([...hand, top, bottom]);
      expect(r.kept.length, 16);
      expect(r.removed.length, 1);
      expect(r.uncertain.length, 1);
    });

    test('規則 A：一張四條被拆成左右兩半 → 只留一張', () {
      final hand = handRow(15);
      final left = tile(15 * 42.0, 500, w: 20, cls: 1);
      final right = tile(15 * 42.0 + 20, 500, w: 20, cls: 1);
      final r = filterHandDetections([...hand, left, right]);
      expect(r.kept.length, 16);
      expect(r.uncertain.length, 1);
    });

    test('規則 A：正常相鄰的牌不會被誤合併', () {
      // 牌和牌緊貼（間隔 = 牌寬）
      final tight = [for (var i = 0; i < 16; i++) tile(i * 40.0, 500)];
      final r = filterHandDetections(tight);
      expect(r.kept.length, 16);
      expect(r.uncertain, isEmpty);
    });

    test('規則 B：信心偏低的牌標記需確認', () {
      final low = Detection(left: 16 * 42.0, top: 500, right: 16 * 42.0 + 40, bottom: 560,
          classId: 1, score: 0.4);
      final r = filterHandDetections([...handRow(16), low]);
      expect(r.kept, contains(low));
      expect(r.uncertain, {low});
    });

    test('框太少時不過濾', () {
      final r = filterHandDetections([tile(0, 0), tile(0, 300, w: 10, h: 10)]);
      expect(r.kept.length, 2);
    });
  });

  group('checkHandWarnings', () {
    test('正常 17 張沒有提醒', () {
      expect(checkHandWarnings(handRow(17), handSize: 16), isEmpty);
    });

    test('超過 17 張要提醒', () {
      final w = checkHandWarnings(handRow(18), handSize: 16);
      expect(w.single, contains('18 張'));
    });

    test('香港牌超過 14 張要提醒', () {
      expect(checkHandWarnings(handRow(15), handSize: 13), hasLength(1));
    });

    test('同一種牌超過 4 張要提醒', () {
      final five = [for (var i = 0; i < 5; i++) tile(i * 42.0, 0, cls: 0)];
      final w = checkHandWarnings(five, handSize: 16);
      expect(w.single, contains('一萬'));
    });

    test('花牌不算進張數', () {
      final flowers = [for (var i = 0; i < 8; i++) tile(i * 42.0, 0, cls: 34 + i)];
      expect(checkHandWarnings([...handRow(16), ...flowers], handSize: 16), isEmpty);
    });
  });

  group('掃描框裁切', () {
    test('只取框內，並記錄裁切位置', () {
      final image = img.Image(width: 1000, height: 800);
      final bytes = Uint8List.fromList(img.encodePng(image));
      final pre = preprocessImageBytes(
        bytes,
        crop: const NormalizedRect(0.1, 0.5, 0.9, 1.0),
      );
      expect(pre.cropLeft, 100);
      expect(pre.cropTop, 400);
      // 回報的是整張原圖大小
      expect(pre.width, 1000);
      expect(pre.height, 800);
      // 裁出 800×400 → 縮成 640×320
      expect(pre.letterbox.ratio, closeTo(0.8, 1e-9));
    });

    test('Detection.shifted 平移回原圖座標', () {
      final d = tile(10, 20).shifted(100, 400);
      expect(d.left, 110);
      expect(d.top, 420);
      expect(d.right, 150);
      expect(d.bottom, 480);
    });
  });
}
