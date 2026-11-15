import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/mahjong/mahjong.dart';
import '../core/vision/tile_detector.dart';
import '../core/vision/tile_reading.dart';
import '../core/vision/yolo_decoder.dart';
import 'wait_text.dart';

/// 拍照／選相簿 → 辨識手牌 → 顯示牌型與聽牌。
/// 認錯的牌可以點一下修改，也可以補上沒認到的牌。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _picker = ImagePicker();
  TileDetector? _detector; // 第一次辨識時才載入模型
  MahjongRules _rules = MahjongRules.presets.first; // 預設：台灣牌

  Uint8List? _imageBytes;
  DetectionResult? _result;
  List<Tile> _tiles = []; // 手牌（可手動修改）
  List<String> _flowers = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _detector?.close();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(source: source);
    } catch (e) {
      setState(() => _error = '無法取得照片：$e');
      return;
    }
    if (file == null) return; // 使用者取消

    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _result = null;
      _busy = true;
      _error = null;
    });
    try {
      _detector ??= await TileDetector.load();
      final result = await _detector!.detect(bytes);
      final reading = TileReading.fromDetections(result.detections);
      setState(() {
        _result = result;
        _tiles = reading.tiles;
        _flowers = reading.flowers;
      });
    } catch (e) {
      setState(() => _error = '辨識失敗：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 點牌 → 選擇要改成哪張（或刪除）；index 為 null 代表新增一張
  Future<void> _editTile(int? index) async {
    final picked = await showDialog<Object>(
      context: context,
      builder: (context) => _TilePickerDialog(allowDelete: index != null),
    );
    if (picked == null) return;
    setState(() {
      if (picked is Tile) {
        if (index == null) {
          _tiles = [..._tiles, picked];
        } else {
          _tiles = [..._tiles]..[index] = picked;
        }
      } else if (index != null) {
        _tiles = [..._tiles]..removeAt(index); // 刪除
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canUseCamera = _picker.supportsImageSource(ImageSource.camera);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('EdgeMJ 拍照辨識')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<MahjongRules>(
            segments: [
              for (final r in MahjongRules.presets)
                ButtonSegment(value: r, label: Text(r.name)),
            ],
            selected: {_rules},
            onSelectionChanged: (s) => setState(() => _rules = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canUseCamera) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('拍照'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: Text(canUseCamera ? '選相簿' : '選照片'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_imageBytes != null) _buildImage(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text('認到的手牌（${_tiles.length} 張，點一下可修改）', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _tiles.length; i++)
                  ActionChip(
                    label: Text(_tiles[i].displayName),
                    onPressed: () => _editTile(i),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('補一張'),
                  onPressed: () => _editTile(null),
                ),
              ],
            ),
            if (_flowers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('花牌（不算進手牌）：${_flowers.join(' ')}'),
            ],
            const SizedBox(height: 8),
            Text('簡寫：${tilesToNotation(_tiles)}', style: textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(
              calculateWaitText(_tiles, _rules),
              key: const Key('scanResultText'),
              style: textTheme.titleLarge,
            ),
          ],
        ],
      ),
    );
  }

  /// 照片 + 辨識框
  Widget _buildImage() {
    final result = _result;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: Center(
        child: AspectRatio(
          aspectRatio: result == null ? 4 / 3 : result.imageWidth / result.imageHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_imageBytes!, fit: BoxFit.fill),
              if (result != null)
                CustomPaint(
                  painter: _BoxPainter(result.detections, result.imageWidth.toDouble()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 在照片上畫出辨識框與牌名
class _BoxPainter extends CustomPainter {
  _BoxPainter(this.detections, this.imageWidth);

  final List<Detection> detections;
  final double imageWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / imageWidth; // 原圖座標 → 畫面座標
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.greenAccent;
    for (final d in detections) {
      final rect = Rect.fromLTRB(d.left * scale, d.top * scale, d.right * scale, d.bottom * scale);
      canvas.drawRect(rect, boxPaint);
      final label = TextPainter(
        text: TextSpan(
          text: classDisplayName(d.classId),
          style: const TextStyle(
            color: Colors.black,
            backgroundColor: Colors.greenAccent,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rect.left, rect.top - label.height));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.detections != detections;
}

/// 選牌對話框：列出 34 種牌，可選「刪除這張」
class _TilePickerDialog extends StatelessWidget {
  const _TilePickerDialog({required this.allowDelete});

  final bool allowDelete;

  /// 代表「刪除」的回傳值
  static const Object delete = 'delete';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('改成哪一張？'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final t in Tile.values)
              ActionChip(
                label: Text(t.displayName),
                onPressed: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
      actions: [
        if (allowDelete)
          TextButton(
            onPressed: () => Navigator.pop(context, delete),
            child: const Text('刪除這張'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}
