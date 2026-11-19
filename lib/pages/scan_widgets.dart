/// 拍照辨識頁和即時辨識頁共用的畫面元件：辨識框、掃描框、選牌對話框。
library;

import 'package:flutter/material.dart';

import '../core/mahjong/mahjong.dart';
import '../core/vision/preprocess.dart';
import '../core/vision/tile_reading.dart';
import '../core/vision/yolo_decoder.dart';

/// 在照片上畫出辨識框與牌名；被過濾掉的框用灰色細線表示
class DetectionPainter extends CustomPainter {
  DetectionPainter(this.detections, this.removed, this.uncertain, this.imageWidth);

  final List<Detection> detections;
  final List<Detection> removed;
  final Set<Detection> uncertain;
  final double imageWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / imageWidth; // 原圖座標 → 畫面座標
    Rect toRect(Detection d) =>
        Rect.fromLTRB(d.left * scale, d.top * scale, d.right * scale, d.bottom * scale);

    // 被過濾掉的框：灰色細線
    final removedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.grey;
    for (final d in removed) {
      canvas.drawRect(toRect(d), removedPaint);
    }

    // 手牌：綠色；需確認的牌：黃色
    for (final d in detections) {
      final color = uncertain.contains(d) ? Colors.amber : Colors.greenAccent;
      final rect = toRect(d);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      final label = TextPainter(
        text: TextSpan(
          text: classDisplayName(d.classId),
          style: TextStyle(
            color: Colors.black,
            backgroundColor: color,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rect.left, rect.top - label.height));
    }
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections || old.removed != removed;
}

/// 可拖拉的掃描框：拖四個角調整大小，拖框內移動位置。框外會變暗。
class CropFrame extends StatefulWidget {
  const CropFrame({super.key, required this.rect, required this.enabled, required this.onChanged});

  final NormalizedRect rect;
  final bool enabled;
  final ValueChanged<NormalizedRect> onChanged;

  @override
  State<CropFrame> createState() => _CropFrameState();
}

/// 目前拖的是哪裡
enum _DragMode { none, move, topLeft, topRight, bottomLeft, bottomRight }

class _CropFrameState extends State<CropFrame> {
  static const double _handleRadius = 28; // 離角落多近算「抓到角」（畫面像素）
  static const double _minSize = 0.05; // 框最小佔照片的 5%

  _DragMode _mode = _DragMode.none;

  _DragMode _hitTest(Offset p, Size size) {
    final r = widget.rect;
    final corners = {
      _DragMode.topLeft: Offset(r.left * size.width, r.top * size.height),
      _DragMode.topRight: Offset(r.right * size.width, r.top * size.height),
      _DragMode.bottomLeft: Offset(r.left * size.width, r.bottom * size.height),
      _DragMode.bottomRight: Offset(r.right * size.width, r.bottom * size.height),
    };
    for (final MapEntry(key: mode, value: c) in corners.entries) {
      if ((c - p).distance <= _handleRadius) return mode;
    }
    final inside = Rect.fromLTRB(r.left * size.width, r.top * size.height,
            r.right * size.width, r.bottom * size.height)
        .contains(p);
    return inside ? _DragMode.move : _DragMode.none;
  }

  void _onDrag(Offset delta, Size size) {
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    final r = widget.rect;
    var (l, t, rt, b) = (r.left, r.top, r.right, r.bottom);
    switch (_mode) {
      case _DragMode.none:
        return;
      case _DragMode.move:
        // 整個框平移，但不超出照片
        final w = rt - l, h = b - t;
        l = (l + dx).clamp(0.0, 1.0 - w);
        t = (t + dy).clamp(0.0, 1.0 - h);
        rt = l + w;
        b = t + h;
      case _DragMode.topLeft:
        l = (l + dx).clamp(0.0, rt - _minSize);
        t = (t + dy).clamp(0.0, b - _minSize);
      case _DragMode.topRight:
        rt = (rt + dx).clamp(l + _minSize, 1.0);
        t = (t + dy).clamp(0.0, b - _minSize);
      case _DragMode.bottomLeft:
        l = (l + dx).clamp(0.0, rt - _minSize);
        b = (b + dy).clamp(t + _minSize, 1.0);
      case _DragMode.bottomRight:
        rt = (rt + dx).clamp(l + _minSize, 1.0);
        b = (b + dy).clamp(t + _minSize, 1.0);
    }
    widget.onChanged(NormalizedRect(l, t, rt, b));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: widget.enabled ? (d) => _mode = _hitTest(d.localPosition, size) : null,
        onPanUpdate: widget.enabled ? (d) => _onDrag(d.delta, size) : null,
        onPanEnd: (_) => _mode = _DragMode.none,
        child: CustomPaint(painter: _CropPainter(widget.rect), size: size),
      );
    });
  }
}

/// 畫掃描框：框外變暗、綠色邊框、四個角的把手
class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);

  final NormalizedRect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(rect.left * size.width, rect.top * size.height,
        rect.right * size.width, rect.bottom * size.height);

    // 框外變暗
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.lightGreenAccent,
    );
    final handle = Paint()..color = Colors.lightGreenAccent;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 8, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect.left != rect.left ||
      old.rect.top != rect.top ||
      old.rect.right != rect.right ||
      old.rect.bottom != rect.bottom;
}

/// 選牌對話框：列出 34 種牌，可選「刪除這張」
class TilePickerDialog extends StatelessWidget {
  const TilePickerDialog({super.key, required this.allowDelete});

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
