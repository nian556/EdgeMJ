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
  });

  /// 模型輸入資料（長度 640*640*3）
  final Float32List input;

  /// 縮放與補邊資訊，之後要用來把框還原回原圖
  final LetterboxInfo letterbox;

  /// 原圖寬高（已依照片的拍攝方向轉正）
  final int width;
  final int height;
}

/// 解碼照片檔（jpg/png…）並做 letterbox。
///
/// 這一步很花時間，App 端會放到背景執行（Isolate.run），避免畫面卡住。
PreprocessedImage preprocessImageBytes(Uint8List bytes, {int inputSize = 640}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('無法讀取這張圖片');
  }
  // 手機拍的照片常把方向記在 EXIF 裡，先轉正，框的位置才會對
  return preprocessImage(img.bakeOrientation(decoded), inputSize: inputSize);
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
