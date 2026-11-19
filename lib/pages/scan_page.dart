import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/mahjong/mahjong.dart';
import '../core/vision/hand_filter.dart';
import '../core/vision/preprocess.dart';
import '../core/vision/tile_detector.dart';
import '../core/vision/tile_reading.dart';
import 'scan_widgets.dart';
import 'wait_text.dart';

/// 拍照／選相簿 → 拖拉掃描框對準手牌 → 辨識 → 顯示牌型與聽牌。
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
  Size? _imageSize; // 照片寬高（用來決定顯示比例）
  NormalizedRect _crop = NormalizedRect.full; // 掃描框（使用者可拖拉）
  DetectionResult? _result;
  List<String> _warnings = [];
  List<Tile> _tiles = []; // 手牌（可手動修改）
  List<bool> _uncertain = []; // 和 _tiles 對應：true = 需確認（黃色）
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
    Size size;
    try {
      // 先讀出照片大小，畫面才能用正確比例顯示並讓使用者拖框
      final image = await decodeImageFromList(bytes);
      size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
    } catch (e) {
      setState(() => _error = '無法讀取這張圖片：$e');
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _imageSize = size;
      _crop = NormalizedRect.full;
      _result = null;
      _warnings = [];
      _error = null;
    });
  }

  /// 只辨識掃描框內的部分
  Future<void> _detect() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _detector ??= await TileDetector.load();
      final result = await _detector!.detect(bytes, crop: _crop);
      final reading =
          TileReading.fromDetections(result.detections, uncertainSet: result.uncertain);
      setState(() {
        _result = result;
        _tiles = reading.tiles;
        _uncertain = reading.uncertain;
        _flowers = reading.flowers;
        _warnings = checkHandWarnings(result.detections, handSize: _rules.handSize);
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
      builder: (context) => TilePickerDialog(allowDelete: index != null),
    );
    if (picked == null) return;
    setState(() {
      if (picked is Tile) {
        if (index == null) {
          _tiles = [..._tiles, picked];
          _uncertain = [..._uncertain, false];
        } else {
          _tiles = [..._tiles]..[index] = picked;
          _uncertain = [..._uncertain]..[index] = false; // 使用者確認過了
        }
      } else if (index != null) {
        _tiles = [..._tiles]..removeAt(index); // 刪除
        _uncertain = [..._uncertain]..removeAt(index);
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
            onSelectionChanged: (s) => setState(() {
              _rules = s.first;
              if (_result != null) {
                _warnings = checkHandWarnings(_result!.detections, handSize: _rules.handSize);
              }
            }),
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
          if (_imageBytes != null) ...[
            Text('拖拉綠框對準手牌（框外的海底牌、牌尺不會被辨識）', style: textTheme.bodySmall),
            const SizedBox(height: 8),
            _buildImage(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _detect,
                    icon: const Icon(Icons.search),
                    label: Text(_result == null ? '開始辨識' : '重新辨識'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy || _crop.isFull
                      ? null
                      : () => setState(() => _crop = NormalizedRect.full),
                  child: const Text('框選整張'),
                ),
              ],
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_result != null) ...[
            const SizedBox(height: 16),
            for (final w in _warnings)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(w),
                ),
              ),
            Text('認到的手牌（${_tiles.length} 張，點一下可修改）', style: textTheme.titleMedium),
            if (_uncertain.contains(true))
              Text('黃色的牌比較沒把握，請確認一下（點一下改成正確的牌）',
                  style: textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _tiles.length; i++)
                  ActionChip(
                    label: Text(_tiles[i].displayName),
                    backgroundColor: _uncertain[i] ? Colors.amber.shade200 : null,
                    avatar: _uncertain[i] ? const Icon(Icons.help_outline, size: 18) : null,
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

  /// 照片 + 掃描框 + 辨識框
  Widget _buildImage() {
    final size = _imageSize!;
    final result = _result;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_imageBytes!, fit: BoxFit.fill),
              if (result != null)
                CustomPaint(
                  painter: DetectionPainter(
                    result.detections,
                    result.removed,
                    result.uncertain,
                    result.imageWidth.toDouble(),
                  ),
                ),
              CropFrame(
                rect: _crop,
                enabled: !_busy,
                onChanged: (r) => setState(() => _crop = r),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
