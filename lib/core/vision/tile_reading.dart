/// 把辨識結果（Detection）整理成「手牌」與「花牌」（純 Dart）。
library;

import '../mahjong/tile.dart';
import 'yolo_decoder.dart';

/// 花牌名稱，對應類別 34~41（1f~8f）
const List<String> flowerNames = ['春', '夏', '秋', '冬', '梅', '蘭', '菊', '竹'];

/// 第一個花牌的類別編號（0~33 是一般牌，和 Tile id 相同）
const int firstFlowerClassId = Tile.kinds;

/// 類別編號的中文名稱，例如 0 →「一萬」、34 →「春」
String classDisplayName(int classId) => classId < firstFlowerClassId
    ? Tile(classId).displayName
    : flowerNames[classId - firstFlowerClassId];

/// 一張照片的辨識結果整理
class TileReading {
  const TileReading({required this.tiles, required this.flowers, this.uncertain = const []});

  /// 依畫面上從左到右的順序整理好的辨識結果。
  /// [uncertainSet]：需要使用者確認的框
  factory TileReading.fromDetections(
    List<Detection> detections, {
    Set<Detection> uncertainSet = const {},
  }) {
    final ordered = [...detections]..sort((a, b) => a.centerX.compareTo(b.centerX));
    final handTiles = [
      for (final d in ordered)
        if (d.classId < firstFlowerClassId) d,
    ];
    return TileReading(
      tiles: [for (final d in handTiles) Tile(d.classId)],
      uncertain: [for (final d in handTiles) uncertainSet.contains(d)],
      flowers: [
        for (final d in ordered)
          if (d.classId >= firstFlowerClassId) flowerNames[d.classId - firstFlowerClassId],
      ],
    );
  }

  /// 手牌（不含花牌），由左到右
  final List<Tile> tiles;

  /// 花牌名稱（不算進手牌）
  final List<String> flowers;

  /// 和 [tiles] 一一對應：true = 這張需要使用者確認（信心偏低或位置有重複的框）
  final List<bool> uncertain;
}
