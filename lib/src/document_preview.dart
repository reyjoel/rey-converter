import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'document_page.dart';
import 'page_annotation.dart';
import 'page_geometry.dart';
import 'image_color_sampling.dart';

/// A bounded decode shared by the page editor and the small page thumbnails.
class DocumentPreview extends StatelessWidget {
  const DocumentPreview({
    super.key,
    required this.page,
    this.selectedAnnotationId,
    this.onSelectionChanged,
    this.onAnnotationChanged,
    this.onAspectRatioChanged,
    this.onColorSampled,
    this.onColorSamplingFailed,
  });

  final DocumentPage page;
  final String? selectedAnnotationId;
  final ValueChanged<String?>? onSelectionChanged;
  final ValueChanged<PageAnnotation>? onAnnotationChanged;
  final ValueChanged<double>? onAspectRatioChanged;
  final ValueChanged<int>? onColorSampled;
  final VoidCallback? onColorSamplingFailed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        final provider = ResizeImage(
          FileImage(File(page.source.path)),
          width: (width * ratio).ceil().clamp(1, 1536),
          height: (height * ratio).ceil().clamp(1, 1536),
          policy: ResizeImagePolicy.fit,
        );
        return _PageCanvas(
          page: page,
          provider: provider,
          available: Size(width, height),
          selectedAnnotationId: selectedAnnotationId,
          onSelectionChanged: onSelectionChanged,
          onAnnotationChanged: onAnnotationChanged,
          onAspectRatioChanged: onAspectRatioChanged,
          onColorSampled: onColorSampled,
          onColorSamplingFailed: onColorSamplingFailed,
        );
      },
    );
  }
}

class _PageCanvas extends StatefulWidget {
  const _PageCanvas({
    required this.page,
    required this.provider,
    required this.available,
    this.selectedAnnotationId,
    this.onSelectionChanged,
    this.onAnnotationChanged,
    this.onAspectRatioChanged,
    this.onColorSampled,
    this.onColorSamplingFailed,
  });

  final DocumentPage page;
  final ImageProvider provider;
  final Size available;
  final String? selectedAnnotationId;
  final ValueChanged<String?>? onSelectionChanged;
  final ValueChanged<PageAnnotation>? onAnnotationChanged;
  final ValueChanged<double>? onAspectRatioChanged;
  final ValueChanged<int>? onColorSampled;
  final VoidCallback? onColorSamplingFailed;

  @override
  State<_PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends State<_PageCanvas> {
  ImageStream? _stream;
  Size? _sourceSize;
  ui.Image? _sourceImage;
  bool _readingColor = false;
  bool _failed = false;
  double? _reportedAspect;
  double _dragX = 0;
  double _dragY = 0;
  late final _listener = ImageStreamListener(
    (info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      final image = info.image.clone();
      info.dispose();
      if (mounted) {
        _sourceImage?.dispose();
        _sourceImage = image;
        setState(() => _sourceSize = size);
      } else {
        image.dispose();
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (mounted) setState(() => _failed = true);
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final next = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == next.key) return;
    _stream?.removeListener(_listener);
    _stream = next..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _sourceImage?.dispose();
    super.dispose();
  }

  Future<void> _sampleColor(Offset position, Size size) async {
    if (_readingColor || widget.onColorSampled == null) return;
    final callback = widget.onColorSampled;
    final image = _sourceImage?.clone();
    if (image == null) return;
    _readingColor = true;
    try {
      final pixels = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (pixels == null) throw StateError('Image pixels are unavailable.');
      final color = sampleRgbaColor(
        rgba: pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        ),
        width: image.width,
        height: image.height,
        x: position.dx / size.width,
        y: position.dy / size.height,
        quarterTurns: widget.page.quarterTurns,
        filter: widget.page.filter,
      );
      if (mounted && identical(widget.onColorSampled, callback)) {
        callback!(color);
      }
    } catch (_) {
      if (mounted && identical(widget.onColorSampled, callback)) {
        widget.onColorSamplingFailed?.call();
      }
    } finally {
      image.dispose();
      _readingColor = false;
    }
  }

  static const _grayscale = <double>[
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
  static const _contrast = <double>[
    .3827,
    1.2874,
    .1299,
    0,
    -102,
    .3827,
    1.2874,
    .1299,
    0,
    -102,
    .3827,
    1.2874,
    .1299,
    0,
    -102,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Icon(Icons.image_not_supported_outlined));
    }
    final original = _sourceSize;
    if (original == null) {
      return const Center(
        child: Icon(Icons.image_outlined, color: Colors.black38),
      );
    }
    final rotated = widget.page.quarterTurns.isOdd
        ? Size(original.height, original.width)
        : original;
    final aspect = rotated.width / rotated.height;
    if (_reportedAspect != aspect) {
      _reportedAspect = aspect;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAspectRatioChanged?.call(aspect);
      });
    }
    final size = applyBoxFit(
      BoxFit.contain,
      rotated,
      widget.available,
    ).destination;
    Widget image = ColoredBox(
      color: Colors.white,
      child: RotatedBox(
        quarterTurns: widget.page.quarterTurns,
        child: Image(image: widget.provider, fit: BoxFit.fill),
      ),
    );
    final matrix = switch (widget.page.filter) {
      ScanFilter.original => null,
      ScanFilter.grayscale => _grayscale,
      ScanFilter.highContrast => _contrast,
    };
    if (matrix != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: image,
      );
    }
    final ordered = [
      ...widget.page.annotations.whereType<CoverAnnotation>(),
      ...widget.page.annotations.where((item) => item is! CoverAnnotation),
    ];
    return Center(
      child: SizedBox(
        key: const ValueKey('page-canvas'),
        width: size.width,
        height: size.height,
        child: GestureDetector(
          onTap: widget.onSelectionChanged == null
              ? null
              : () => widget.onSelectionChanged!(null),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (widget.onColorSampled == null)
                  for (final annotation in ordered)
                    _annotationWidget(annotation, size),
                if (widget.onColorSampled != null)
                  Positioned.fill(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.precise,
                      child: GestureDetector(
                        key: const ValueKey('photo-color-picker'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _sampleColor(details.localPosition, size),
                        child: Semantics(
                          label: 'Tap the photo to pick a color',
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _annotationWidget(PageAnnotation annotation, Size size) {
    final selected = annotation.id == widget.selectedAnnotationId;
    final interactive = widget.onSelectionChanged != null;
    final box = Size(
      annotation.width * size.width,
      annotation.height * size.height,
    );
    final pdfWidth = imageWidthPointsForAspectRatio(size.width / size.height);
    Widget child = switch (annotation) {
      CoverAnnotation() => ColoredBox(
        color: Color(0xff000000 | annotation.color),
      ),
      TextAnnotation() => Text(
        annotation.text,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'ReyDocument',
          fontSize:
              annotation.fontSizeForImageWidth(pdfWidth) /
              pdfWidth *
              size.width,
          fontWeight: annotation.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
          color: Color(0xff000000 | annotation.color),
          height: 1.2,
          decoration: TextDecoration.combine([
            if (annotation.underline) TextDecoration.underline,
            if (annotation.strikethrough) TextDecoration.lineThrough,
          ]),
          decorationColor: Color(0xff000000 | annotation.color),
        ),
      ),
      SignatureAnnotation() => CustomPaint(
        painter: SignaturePainter(annotation.strokes, color: annotation.color),
        size: box,
      ),
    };
    child = ClipRect(child: child);
    if (selected) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        child: child,
      );
    }
    if (interactive) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectionChanged!(annotation.id),
        onPanStart: (_) {
          _dragX = annotation.x;
          _dragY = annotation.y;
          widget.onSelectionChanged!(annotation.id);
        },
        onPanUpdate: (details) {
          _dragX = (_dragX + details.delta.dx / size.width).clamp(
            0.0,
            math.max(0.0, 1 - annotation.width),
          );
          _dragY = (_dragY + details.delta.dy / size.height).clamp(
            0.0,
            math.max(0.0, 1 - annotation.height),
          );
          widget.onAnnotationChanged?.call(
            annotation.copyWith(x: _dragX, y: _dragY),
          );
        },
        child: child,
      );
    }
    return Positioned(
      key: ValueKey('annotation-${annotation.id}'),
      left: annotation.x * size.width,
      top: annotation.y * size.height,
      width: box.width,
      height: box.height,
      child: child,
    );
  }
}

class SignaturePainter extends CustomPainter {
  const SignaturePainter(this.strokes, {this.color = 0x000000});

  final List<List<AnnotationPoint>> strokes;
  final int color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xff000000 | color)
      ..strokeWidth = size.width * .012
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        final point = stroke.first;
        canvas.drawCircle(
          Offset(point.x * size.width, point.y * size.height),
          paint.strokeWidth / 2,
          Paint()..color = Color(0xff000000 | color),
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.first.x * size.width, stroke.first.y * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.color != color;
}
