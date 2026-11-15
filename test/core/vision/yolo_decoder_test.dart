import 'dart:typed_data';

import 'package:edge_mj/core/mahjong/mahjong.dart';
import 'package:edge_mj/core/vision/preprocess.dart';
import 'package:edge_mj/core/vision/tile_reading.dart';
import 'package:edge_mj/core/vision/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const int numClasses = 42;
const int numBoxes = 10; // 測試用：只放 10 個候選框

/// 做一份假的模型輸出；boxes 的每一筆是 (中心x, 中心y, 寬, 高, 類別, 分數)
Float32List fakeOutput(List<(double, double, double, double, int, double)> boxes) {
  final out = Float32List((4 + numClasses) * numBoxes);
  for (var i = 0; i < boxes.length; i++) {
    final (cx, cy, w, h, cls, score) = boxes[i];
    out[i] = cx;
    out[numBoxes + i] = cy;
    out[2 * numBoxes + i] = w;
    out[3 * numBoxes + i] = h;
    out[(4 + cls) * numBoxes + i] = score;
  }
  return out;
}

Detection box(double l, double t, double r, double b, {int cls = 0, double score = 0.9}) =>
    Detection(left: l, top: t, right: r, bottom: b, classId: cls, score: score);

void main() {
  group('LetterboxInfo', () {
    test('寬圖：上下補邊', () {
      final info = LetterboxInfo.compute(1280, 640, 640);
      expect(info.ratio, 0.5);
      expect(info.padX, 0);
      expect(info.padY, 160); // 縮成 640x320，上下各補 160
    });

    test('直圖：左右補邊', () {
      final info = LetterboxInfo.compute(300, 600, 640);
      expect(info.padX, 160); // 縮成 320x640，左右各補 160
      expect(info.padY, 0);
    });
  });

  group('IoU 與 NMS', () {
    test('完全重疊 = 1，不重疊 = 0', () {
      expect(intersectionOverUnion(box(0, 0, 10, 10), box(0, 0, 10, 10)), 1);
      expect(intersectionOverUnion(box(0, 0, 10, 10), box(20, 0, 30, 10)), 0);
    });

    test('重疊太多的框只留分數高的（不分類別）', () {
      final kept = nonMaxSuppression([
        box(0, 0, 10, 10, cls: 2, score: 0.6),
        box(1, 0, 11, 10, cls: 4, score: 0.9), // 同一張牌被猜成另一種
        box(20, 0, 30, 10, cls: 2, score: 0.8), // 旁邊的另一張牌
      ], 0.5);
      expect(kept.map((d) => d.classId), [4, 2]);
    });
  });

  group('decodeYoloOutput', () {
    test('過濾低分、還原成原圖座標', () {
      // 原圖 1280x640 → 縮放 0.5、上面補 160
      final letterbox = LetterboxInfo.compute(1280, 640, 640);
      final out = fakeOutput([
        (100, 260, 40, 60, 5, 0.9), // 六萬
        (300, 260, 40, 60, 27, 0.1), // 分數太低，要被丟掉
      ]);
      final result = decodeYoloOutput(out,
          letterbox: letterbox, numClasses: numClasses, numBoxes: numBoxes);
      expect(result, hasLength(1));
      final d = result.single;
      expect(d.classId, 5);
      expect(d.left, (100 - 20) / 0.5);
      expect(d.top, (260 - 30 - 160) / 0.5);
      expect(d.right, (100 + 20) / 0.5);
      expect(d.bottom, (260 + 30 - 160) / 0.5);
    });

    test('輸出長度不對會報錯', () {
      expect(
        () => decodeYoloOutput(Float32List(10),
            letterbox: LetterboxInfo.compute(640, 640, 640)),
        throwsArgumentError,
      );
    });
  });

  group('TileReading', () {
    test('依由左到右排序，花牌分開', () {
      final reading = TileReading.fromDetections([
        box(200, 0, 240, 60, cls: 27), // 東
        box(0, 0, 40, 60, cls: 0), // 一萬
        box(100, 0, 140, 60, cls: 34), // 春（花牌）
        box(50, 0, 90, 60, cls: 9), // 一筒
      ]);
      expect(tilesToNotation(reading.tiles), '1m1p1z');
      expect(reading.tiles.map((t) => t.notation), ['1m', '1p', '1z']);
      expect(reading.flowers, ['春']);
    });

    test('類別中文名稱', () {
      expect(classDisplayName(0), '一萬');
      expect(classDisplayName(33), '白');
      expect(classDisplayName(41), '竹');
    });
  });

  group('前處理', () {
    test('補邊是灰色、照片內容放在中間', () {
      // 200x100 的紅色圖 → 縮成 640x320，上下各補 160
      final image = img.Image(width: 200, height: 100)
        ..clear(img.ColorRgb8(255, 0, 0));
      final pre = preprocessImage(image);
      expect(pre.input.length, 640 * 640 * 3);
      expect(pre.letterbox.padY, 160);
      // 左上角 (0,0) 是補邊的灰色
      expect(pre.input[0], closeTo(114 / 255, 1e-6));
      // 正中間 (320,320) 是紅色
      final center = (320 * 640 + 320) * 3;
      expect(pre.input[center], closeTo(1, 1e-6));
      expect(pre.input[center + 1], closeTo(0, 1e-6));
    });
  });
}
