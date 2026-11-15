/// 麻將牌辨識器：載入 TFLite 模型，輸入照片、輸出辨識結果。
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'preprocess.dart';
import 'yolo_decoder.dart';

/// 一張照片的辨識結果
class DetectionResult {
  const DetectionResult({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<Detection> detections;

  /// 原圖寬高（框的座標以這個為基準）
  final int imageWidth;
  final int imageHeight;
}

class TileDetector {
  TileDetector._(this._interpreter, this._isolateInterpreter);

  static const String modelAsset = 'assets/models/edgemj_float16.tflite';
  static const int inputSize = 640;
  static const int numClasses = 42;
  static const int numBoxes = 8400;

  final Interpreter _interpreter;
  final IsolateInterpreter _isolateInterpreter;

  /// 載入模型（第一次比較久，之後重複使用同一個 TileDetector）
  static Future<TileDetector> load() async {
    final interpreter = await Interpreter.fromAsset(modelAsset);
    // 在背景執行模型推論，畫面才不會卡住
    final isolateInterpreter =
        await IsolateInterpreter.create(address: interpreter.address);
    return TileDetector._(interpreter, isolateInterpreter);
  }

  /// 辨識一張照片（jpg/png 等檔案內容）
  Future<DetectionResult> detect(Uint8List imageBytes) async {
    // 1. 前處理（解碼、縮放、補邊）放在背景執行
    final pre = await Isolate.run(() => preprocessImageBytes(imageBytes, inputSize: inputSize));

    // 2. 執行模型
    final output = Float32List((4 + numClasses) * numBoxes);
    await _isolateInterpreter.run(pre.input.buffer.asUint8List(), output.buffer);

    // 3. 解讀輸出
    final detections = decodeYoloOutput(
      output,
      letterbox: pre.letterbox,
      numClasses: numClasses,
      numBoxes: numBoxes,
    );
    return DetectionResult(
      detections: detections,
      imageWidth: pre.width,
      imageHeight: pre.height,
    );
  }

  /// 不再使用時釋放記憶體
  Future<void> close() async {
    await _isolateInterpreter.close();
    _interpreter.close();
  }
}
