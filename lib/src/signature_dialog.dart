import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'page_annotation.dart';

/// Captures ink in a 3:1 box. Points are normalized to that box.
Future<List<List<AnnotationPoint>>?> showSignatureDialog(BuildContext context) {
  return showDialog<List<List<AnnotationPoint>>>(
    context: context,
    builder: (_) => const _SignatureDialog(),
  );
}

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog();

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final List<List<AnnotationPoint>> _strokes = [];
  List<AnnotationPoint>? _activeStroke;

  AnnotationPoint _point(Offset localPosition, Size size) {
    return AnnotationPoint(
      (localPosition.dx / size.width).clamp(0.0, 1.0),
      (localPosition.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _beginStroke(Offset localPosition, Size size) {
    setState(() {
      _activeStroke = [_point(localPosition, size)];
      _strokes.add(_activeStroke!);
    });
  }

  void _extendStroke(Offset localPosition, Size size) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    setState(() => stroke.add(_point(localPosition, size)));
  }

  void _endStroke() => _activeStroke = null;

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _activeStroke = null;
      _strokes.removeLast();
    });
  }

  void _clear() {
    setState(() {
      _activeStroke = null;
      _strokes.clear();
    });
  }

  void _accept() {
    if (_strokes.isEmpty) return;
    Navigator.of(context).pop(_trimmedStrokes());
  }

  List<List<AnnotationPoint>> _trimmedStrokes() {
    var minX = 1.0;
    var maxX = 0.0;
    var minY = 1.0;
    var maxY = 0.0;
    for (final stroke in _strokes) {
      for (final point in stroke) {
        minX = math.min(minX, point.x);
        maxX = math.max(maxX, point.x);
        minY = math.min(minY, point.y);
        maxY = math.max(maxY, point.y);
      }
    }

    // Use one scale for both normalized axes, preserving the 3:1 pad's aspect
    // ratio. Leave ink padding so the exported round stroke ends stay visible.
    final extent = math.max(maxX - minX, maxY - minY);
    final scale = extent < 0.01 ? 1.0 : 0.9 / extent;
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    return List.unmodifiable(
      _strokes.map(
        (stroke) => List<AnnotationPoint>.unmodifiable(
          stroke.map(
            (point) => AnnotationPoint(
              ((point.x - centerX) * scale + 0.5).clamp(0.0, 1.0),
              ((point.y - centerY) * scale + 0.5).clamp(0.0, 1.0),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Add signature'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Draw with your finger.'),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: AspectRatio(
                    aspectRatio: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: ColoredBox(
                        color: Colors.white,
                        child: LayoutBuilder(
                          builder: (_, constraints) {
                            final size = constraints.biggest;
                            return GestureDetector(
                              key: const ValueKey('signature-pad'),
                              behavior: HitTestBehavior.opaque,
                              onPanDown: (details) =>
                                  _beginStroke(details.localPosition, size),
                              onPanUpdate: (details) =>
                                  _extendStroke(details.localPosition, size),
                              onPanEnd: (_) => _endStroke(),
                              onPanCancel: _endStroke,
                              onTapUp: (_) => _endStroke(),
                              child: CustomPaint(
                                painter: _SignaturePainter(_strokes),
                                child: const SizedBox.expand(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _strokes.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo stroke'),
                  ),
                  TextButton.icon(
                    onPressed: _strokes.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _strokes.isEmpty ? null : _accept,
          icon: const Icon(Icons.check),
          label: const Text('Use signature'),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<AnnotationPoint>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.012;
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final first = Offset(
        stroke.first.x * size.width,
        stroke.first.y * size.height,
      );
      if (stroke.length == 1) {
        canvas.drawCircle(
          first,
          strokeWidth / 2,
          Paint()..color = Colors.black,
        );
        continue;
      }
      final path = Path()..moveTo(first.dx, first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  // Strokes are appended while drawing, so the shared list can retain identity.
  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
