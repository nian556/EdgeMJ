/// 把照片轉成模型的輸入格式（純 Dart，使用 image 套件）。
///
/// 輸入：[1, 640, 640, 3] float32，RGB，數值 0~1；
/// 等比例縮放後用灰色 (114) 補邊（letterbox）。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'yolo_decoder.dart';

/// 前處理的結果
class PreprocessedImage {
  const PreprocessedImage({
    required this.input,
    required this.letterbox,
    required this.width,
    required this.height,
    this.cropLeft = 0,
    this.cropTop = 0,
  });

  /// 模型輸入資料（長度 640*640*3）
  final Float32List input;

  /// 縮放與補邊資訊，之後要用來把框還原回原圖
  final LetterboxInfo letterbox;

  /// 原圖寬高（已依照片的拍攝方向轉正）
  final int width;
  final int height;

  /// 裁切區域左上角在原圖的位置（沒裁切就是 0）。
  /// 模型認到的框要加上這個位移，才會對回原圖。
  final int cropLeft;
  final int cropTop;
}

/// 用 0~1 比例表示的長方形（相對於轉正後的整張照片），用來表示「掃描框」
class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.right, this.bottom);

  /// 整張照片
  static const NormalizedRect full = NormalizedRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isFull => left <= 0 && top <= 0 && right >= 1 && bottom >= 1;
}

/// 解碼照片檔（jpg/png…），只取掃描框 [crop] 內的部分，再做 letterbox。
///
/// 只把框內的畫面給模型：牌在模型眼中變大、比較好認，框外的海底牌也不會被認到。
/// 這一步很花時間，App 端會放到背景執行（Isolate.run），避免畫面卡住。
PreprocessedImage preprocessImageBytes(
  Uint8List bytes, {
  int inputSize = 640,
  NormalizedRect crop = NormalizedRect.full,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('無法讀取這張圖片');
  }
  // 手機拍的照片常把方向記在 EXIF 裡，先轉正，框的位置才會對
  final image = img.bakeOrientation(decoded);
  if (crop.isFull) return preprocessImage(image, inputSize: inputSize);

  // 比例 → 像素，並限制在圖片範圍內（至少留 1 像素）
  final x0 = (crop.left * image.width).round().clamp(0, image.width - 1);
  final y0 = (crop.top * image.height).round().clamp(0, image.height - 1);
  final x1 = (crop.right * image.width).round().clamp(x0 + 1, image.width);
  final y1 = (crop.bottom * image.height).round().clamp(y0 + 1, image.height);
  final cropped = img.copyCrop(image, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  final pre = preprocessImage(cropped, inputSize: inputSize);
  return PreprocessedImage(
    input: pre.input,
    letterbox: pre.letterbox,
    width: image.width, // 回報整張原圖的大小，畫面才能把框畫在原圖上
    height: image.height,
    cropLeft: x0,
    cropTop: y0,
  );
}

/// 對已解碼的圖片做 letterbox，轉成 float32 輸入
PreprocessedImage preprocessImage(img.Image image, {int inputSize = 640}) {
  final box = LetterboxInfo.compute(image.width, image.height, inputSize);
  final resized = img.copyResize(
    image,
    width: box.scaledWidth(image.width),
    height: box.scaledHeight(image.height),
    interpolation: img.Interpolation.linear,
  );

  // 先全部填灰色 114/255，再把縮放後的照片貼到中間
  final input = Float32List(inputSize * inputSize * 3)..fillRange(0, inputSize * inputSize * 3, 114 / 255);
  for (final p in resized) {
    final offset = ((p.y + box.padY) * inputSize + (p.x + box.padX)) * 3;
    input[offset] = p.rNormalized.toDouble();
    input[offset + 1] = p.gNormalized.toDouble();
    input[offset + 2] = p.bNormalized.toDouble();
  }
  return PreprocessedImage(
    input: input,
    letterbox: box,
    width: image.width,
    height: image.height,
  );
}
