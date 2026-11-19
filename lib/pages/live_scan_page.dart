import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/mahjong/mahjong.dart';
import '../core/vision/hand_filter.dart';
import '../core/vision/preprocess.dart';
import '../core/vision/tile_detector.dart';
import '../core/vision/tile_reading.dart';
import 'scan_widgets.dart';
import 'wait_text.dart';

/// 即時辨識：鏡頭對著手牌，畫面上直接顯示認到的牌和聽牌，不用按拍照。
///
/// 做法：不停地「抓一張畫面 → 辨識 → 更新結果」。
/// 連續兩次認到一樣的牌，才更新下方的手牌和聽牌，避免結果一直跳來跳去。
///
/// 沒有鏡頭時（例如電腦沒接攝影機），可以改用「照片模擬鏡頭」：
/// 選幾張照片輪流播放，當成鏡頭畫面來測試。
class LiveScanPage extends StatefulWidget {
  const LiveScanPage({super.key, this.active = true});

  /// 這一頁目前是否顯示在畫面上；切到別頁時會自動暫停，省電也釋放鏡頭
  final bool active;

  @override
  State<LiveScanPage> createState() => _LiveScanPageState();
}

/// 畫面來源
enum _Source { none, camera, photos }

class _LiveScanPageState extends State<LiveScanPage> {
  /// 照片模擬模式：每張照片要辨識幾輪才換下一張
  static const int _roundsPerPhoto = 3;

  final _picker = ImagePicker();
  TileDetector? _detector;
  MahjongRules _rules = MahjongRules.presets.first; // 預設：台灣牌

  _Source _source = _Source.none;
  CameraController? _camera;
  bool _noCamera = false; // 找不到鏡頭

  List<Uint8List> _photos = []; // 模擬用的照片
  int _photoRound = 0; // 模擬模式已經跑了幾輪

  bool _running = false; // 是否正在連續辨識
  bool _looping = false; // 辨識迴圈是否還在跑（避免同時跑兩個）
  NormalizedRect _crop = NormalizedRect.full;

  Uint8List? _frame; // 照片模式：目前顯示的那張
  Size? _frameSize; // 目前畫面的寬高（畫框用）
  DetectionResult? _latest; // 最新一輪的辨識框（即時畫在畫面上）
  String? _lastKey; // 上一輪認到的牌（用來判斷是否穩定）
  TileReading? _stable; // 穩定的結果（連續兩輪一樣）
  List<String> _warnings = [];
  double _fps = 0; // 每秒辨識幾次
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _openCamera();
  }

  @override
  void didUpdateWidget(LiveScanPage old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) {
      // 切到別頁：停止辨識並關掉鏡頭
      _running = false;
      _closeCamera();
    } else if (!old.active && widget.active && _source != _Source.photos) {
      _openCamera();
    }
  }

  @override
  void dispose() {
    _running = false;
    _camera?.dispose();
    _detector?.close();
    super.dispose();
  }

  // ───────────── 畫面來源 ─────────────

  Future<void> _openCamera() async {
    if (_camera != null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _noCamera = true);
        return;
      }
      // 手機優先用背面鏡頭
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(cam, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted || !widget.active) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _source = _Source.camera;
        _noCamera = false;
        _frame = null;
        _frameSize = null;
        _latest = null;
      });
    } catch (e) {
      setState(() {
        _noCamera = true;
        _error = '無法開啟鏡頭：$e';
      });
    }
  }

  Future<void> _closeCamera() async {
    final c = _camera;
    _camera = null;
    if (_source == _Source.camera) _source = _Source.none;
    await c?.dispose();
    if (mounted) setState(() {});
  }

  /// 選幾張照片，輪流當成鏡頭畫面
  Future<void> _usePhotos() async {
    final List<XFile> files;
    try {
      files = await _picker.pickMultiImage();
    } catch (e) {
      setState(() => _error = '無法選取照片：$e');
      return;
    }
    if (files.isEmpty) return;
    final photos = [for (final f in files) await f.readAsBytes()];
    _running = false;
    await _closeCamera();
    setState(() {
      _photos = photos;
      _photoRound = 0;
      _source = _Source.photos;
      _frame = photos.first;
      _frameSize = null;
      _latest = null;
      _error = null;
    });
    await _updateFrameSize(photos.first);
    _start();
  }

  Future<void> _updateFrameSize(Uint8List bytes) async {
    final image = await decodeImageFromList(bytes);
    if (mounted) {
      setState(() => _frameSize = Size(image.width.toDouble(), image.height.toDouble()));
    }
    image.dispose();
  }

  /// 抓下一張畫面；沒有畫面來源時回傳 null
  Future<Uint8List?> _nextFrame() async {
    switch (_source) {
      case _Source.none:
        return null;
      case _Source.camera:
        final c = _camera;
        if (c == null || !c.value.isInitialized) return null;
        final file = await c.takePicture();
        return file.readAsBytes();
      case _Source.photos:
        final index = (_photoRound ~/ _roundsPerPhoto) % _photos.length;
        _photoRound++;
        final bytes = _photos[index];
        if (!identical(bytes, _frame)) {
          setState(() {
            _frame = bytes;
            _latest = null; // 換照片時先清掉舊的框
          });
          await _updateFrameSize(bytes);
        }
        return bytes;
    }
  }

  // ───────────── 連續辨識 ─────────────

  void _start() {
    setState(() {
      _running = true;
      _error = null;
    });
    if (!_looping) _loop();
  }

  void _stop() => setState(() => _running = false);

  Future<void> _loop() async {
    _looping = true;
    try {
      _detector ??= await TileDetector.load();
      while (_running && mounted) {
        final watch = Stopwatch()..start();
        final bytes = await _nextFrame();
        if (bytes == null || !_running || !mounted) break;
        final result = await _detector!.detect(bytes, crop: _crop);
        if (!mounted) break;
        _onResult(result, watch.elapsedMilliseconds);
        // 照片模式辨識太快會看不清楚，稍微停一下
        if (_source == _Source.photos) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '辨識失敗：$e');
    } finally {
      _looping = false;
      if (mounted) setState(() => _running = false);
    }
  }

  void _onResult(DetectionResult result, int ms) {
    final reading =
        TileReading.fromDetections(result.detections, uncertainSet: result.uncertain);
    final key = '${tilesToNotation(reading.tiles)}|${reading.flowers.join()}';
    setState(() {
      _latest = result;
      _frameSize ??= Size(result.imageWidth.toDouble(), result.imageHeight.toDouble());
      _fps = ms > 0 ? 1000 / ms : 0;
      // 連續兩輪一樣才算穩定，才更新下方的結果
      if (key == _lastKey) {
        _stable = reading;
        _warnings = checkHandWarnings(result.detections, handSize: _rules.handSize);
      }
      _lastKey = key;
    });
  }

  // ───────────── 畫面 ─────────────

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stable = _stable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EdgeMJ 即時辨識'),
        actions: [
          if (_running)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('每秒 ${_fps.toStringAsFixed(1)} 次')),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<MahjongRules>(
            segments: [
              for (final r in MahjongRules.presets) ButtonSegment(value: r, label: Text(r.name)),
            ],
            selected: {_rules},
            onSelectionChanged: (s) => setState(() {
              _rules = s.first;
              if (_latest != null) {
                _warnings = checkHandWarnings(_latest!.detections, handSize: _rules.handSize);
              }
            }),
          ),
          const SizedBox(height: 12),
          _buildControls(),
          const SizedBox(height: 12),
          if (_source != _Source.none) ...[
            Text('拖拉綠框對準手牌（框外的海底牌不會被辨識）', style: textTheme.bodySmall),
            const SizedBox(height: 8),
            _buildView(),
          ] else if (_noCamera)
            Card(
              child: ListTile(
                leading: const Icon(Icons.videocam_off),
                title: const Text('找不到鏡頭'),
                subtitle: const Text('可以先用「照片模擬鏡頭」測試：選幾張手牌照片，會輪流播放並即時辨識。'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (stable != null) ...[
            const SizedBox(height: 16),
            for (final w in _warnings)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(leading: const Icon(Icons.warning_amber), title: Text(w)),
              ),
            Text('認到的手牌（${stable.tiles.length} 張）', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < stable.tiles.length; i++)
                  Chip(
                    label: Text(stable.tiles[i].displayName),
                    backgroundColor: stable.uncertain[i] ? Colors.amber.shade200 : null,
                  ),
              ],
            ),
            if (stable.flowers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('花牌（不算進手牌）：${stable.flowers.join(' ')}'),
            ],
            const SizedBox(height: 16),
            Text(
              calculateWaitText(stable.tiles, _rules),
              key: const Key('liveResultText'),
              style: textTheme.titleLarge,
            ),
          ],
        ],
      ),
    );
  }

  /// 開始／暫停、切換畫面來源
  Widget _buildControls() {
    final hasSource = _source != _Source.none;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (hasSource)
          FilledButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            label: Text(_running ? '暫停' : '開始辨識'),
          ),
        if (_source != _Source.camera)
          OutlinedButton.icon(
            onPressed: () {
              _running = false;
              setState(() {
                _source = _Source.none;
                _noCamera = false;
                _error = null;
              });
              _openCamera();
            },
            icon: const Icon(Icons.videocam),
            label: const Text('用鏡頭'),
          ),
        OutlinedButton.icon(
          onPressed: _usePhotos,
          icon: const Icon(Icons.photo_library),
          label: const Text('照片模擬鏡頭'),
        ),
        if (!_crop.isFull)
          OutlinedButton(
            onPressed: () => setState(() => _crop = NormalizedRect.full),
            child: const Text('框選整個畫面'),
          ),
      ],
    );
  }

  /// 鏡頭畫面（或模擬照片）+ 辨識框 + 掃描框
  Widget _buildView() {
    final camera = _camera;
    final size = _frameSize;
    final double aspect = size != null
        ? size.width / size.height
        : (camera != null && camera.value.isInitialized ? camera.value.aspectRatio : 4 / 3);
    final latest = _latest;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_source == _Source.camera && camera != null)
                CameraPreview(camera)
              else if (_frame != null)
                Image.memory(_frame!, fit: BoxFit.fill, gaplessPlayback: true),
              if (latest != null)
                CustomPaint(
                  painter: DetectionPainter(
                    latest.detections,
                    latest.removed,
                    latest.uncertain,
                    latest.imageWidth.toDouble(),
                  ),
                ),
              CropFrame(
                rect: _crop,
                enabled: true,
                onChanged: (r) => setState(() => _crop = r),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
