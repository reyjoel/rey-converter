import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_page.dart';
import 'image_color_sampling.dart';
import 'page_annotation.dart';

enum PdfImageQuality {
  compact('Compact', 1280, 70),
  balanced('Balanced', 1920, 82),
  high('High', 2560, 90);

  const PdfImageQuality(this.label, this.maximumDimension, this.jpegQuality);

  final String label;
  final int maximumDimension;
  final int jpegQuality;
}

class PdfService {
  Future<Uint8List> createPdf({
    required List<DocumentPage> pages,
    required PdfImageQuality quality,
    void Function(int completed, int total)? onProgress,
  }) async {
    final inputs = pages
        .map(
          (page) => _PdfPage(
            page.source,
            page.quarterTurns,
            page.filter,
            page.annotations,
          ),
        )
        .toList();
    final fontFaces = pages
        .expand((page) => page.annotations.whereType<TextAnnotation>())
        .map(_fontFace)
        .toSet();
    final fontBytes = <String, Uint8List>{};
    for (final face in fontFaces) {
      // Asset access belongs on the app isolate; the worker receives plain bytes.
      final font = await rootBundle.load('assets/fonts/Roboto-$face.ttf');
      fontBytes[face] = font.buffer.asUint8List(
        font.offsetInBytes,
        font.lengthInBytes,
      );
    }
    final progress = ReceivePort();
    final progressFinished = Completer<void>();
    Object? callbackError;
    StackTrace? callbackStack;
    final subscription = progress.listen((message) {
      if (message == null) {
        progressFinished.complete();
      } else if (callbackError == null) {
        try {
          onProgress?.call(message as int, inputs.length);
        } catch (error, stack) {
          callbackError = error;
          callbackStack = stack;
        }
      }
    });

    try {
      final bytes = await _runPdfWorker(
        inputs,
        quality,
        progress.sendPort,
        fontBytes,
      );
      // Progress and the final result use separate ports. Drain the progress
      // port before returning so callers always see the last completed page.
      await progressFinished.future;
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      return bytes;
    } finally {
      await subscription.cancel();
      progress.close();
    }
  }

  Uint8List preparePageImage(
    Uint8List bytes,
    DocumentPage page,
    PdfImageQuality quality,
  ) {
    return _preparePageImage(
      bytes,
      page.quarterTurns,
      page.filter,
      quality,
      page.annotations,
    );
  }
}

class _PdfPage {
  const _PdfPage(this.source, this.quarterTurns, this.filter, this.annotations);

  final XFile source;
  final int quarterTurns;
  final ScanFilter filter;
  final List<PageAnnotation> annotations;
}

// Keep the isolate closure outside the service/UI scope so it only captures
// image inputs and a send port, never widgets or progress callbacks.
Future<Uint8List> _runPdfWorker(
  List<_PdfPage> pages,
  PdfImageQuality quality,
  SendPort progress,
  Map<String, Uint8List> fontBytes,
) => Isolate.run(
  () => _buildPdf(pages, quality, progress, fontBytes),
  debugName: 'pdf-generation',
);

Future<Uint8List> _buildPdf(
  List<_PdfPage> pages,
  PdfImageQuality quality,
  SendPort progress,
  Map<String, Uint8List> fontBytes,
) async {
  try {
    final fonts = fontBytes.map(
      (face, bytes) => MapEntry(
        face,
        pw.Font.ttf(
          ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      ),
    );
    final document = pw.Document(
      title: 'REY Converter',
      creator: 'REY Converter',
      compress: true,
    );

    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      final originalBytes = await page.source.readAsBytes();
      final preparedBytes = _preparePageImage(
        originalBytes,
        page.quarterTurns,
        page.filter,
        quality,
        page.annotations,
      );
      final pdfImage = pw.MemoryImage(preparedBytes);

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => _buildAnnotatedPage(pdfImage, page.annotations, fonts),
        ),
      );
      progress.send(index + 1);
    }

    return await document.save();
  } finally {
    progress.send(null);
  }
}

pw.Widget _buildAnnotatedPage(
  pw.MemoryImage image,
  List<PageAnnotation> annotations,
  Map<String, pw.Font> fonts,
) {
  final scale = math.min(
    (PdfPageFormat.a4.width - 48) / image.width!,
    (PdfPageFormat.a4.height - 48) / image.height!,
  );
  final width = image.width! * scale;
  final height = image.height! * scale;
  return pw.Center(
    child: pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(
        fit: pw.StackFit.expand,
        children: [
          pw.Image(image, width: width, height: height, fit: pw.BoxFit.fill),
          for (final annotation in annotations)
            if (annotation is! CoverAnnotation)
              pw.Positioned(
                left: annotation.x * width,
                top: annotation.y * height,
                child: pw.SizedBox(
                  width: annotation.width * width,
                  height: annotation.height * height,
                  child: pw.ClipRect(
                    child: switch (annotation) {
                      TextAnnotation() => pw.Text(
                        annotation.text,
                        overflow: pw.TextOverflow.clip,
                        style: pw.TextStyle(
                          font: fonts[_fontFace(annotation)],
                          fontWeight: annotation.bold
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                          fontStyle: annotation.italic
                              ? pw.FontStyle.italic
                              : pw.FontStyle.normal,
                          fontSize: annotation.fontSizeForImageWidth(width),
                          // Roboto's natural line height is 2400/2048 em.
                          // Add leading to match the editor's 1.2 em lines.
                          lineSpacing:
                              annotation.fontSizeForImageWidth(width) *
                              (1.2 - 2400 / 2048),
                          color: _pdfColor(annotation.color),
                          decorationColor: _pdfColor(annotation.color),
                          decoration: pw.TextDecoration.combine([
                            if (annotation.underline)
                              pw.TextDecoration.underline,
                            if (annotation.strikethrough)
                              pw.TextDecoration.lineThrough,
                          ]),
                        ),
                      ),
                      SignatureAnnotation() => _buildSignature(annotation),
                      CoverAnnotation() => pw.SizedBox.shrink(),
                    },
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

pw.Widget _buildSignature(SignatureAnnotation annotation) => pw.CustomPaint(
  painter: (canvas, size) {
    final strokeWidth = size.x * .012;
    canvas
      ..setStrokeColor(_pdfColor(annotation.color))
      ..setFillColor(_pdfColor(annotation.color))
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      ..setLineWidth(strokeWidth);
    for (final stroke in annotation.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas
          ..drawEllipse(
            stroke.first.x * size.x,
            (1 - stroke.first.y) * size.y,
            strokeWidth / 2,
            strokeWidth / 2,
          )
          ..fillPath();
      } else {
        canvas.moveTo(stroke.first.x * size.x, (1 - stroke.first.y) * size.y);
        for (final point in stroke.skip(1)) {
          canvas.lineTo(point.x * size.x, (1 - point.y) * size.y);
        }
        canvas.strokePath();
      }
    }
  },
);

Uint8List _preparePageImage(
  Uint8List bytes,
  int quarterTurns,
  ScanFilter filter,
  PdfImageQuality quality,
  List<PageAnnotation> annotations,
) {
  var edited = _decodeAndResize(bytes, quality.maximumDimension);
  if (edited.exif.imageIfd.hasOrientation &&
      edited.exif.imageIfd.orientation != 1) {
    edited = img.bakeOrientation(edited);
  }
  if (quarterTurns != 0) {
    edited = img.copyRotate(edited, angle: quarterTurns * 90);
  }
  edited = _applyPhotoFilter(edited, filter);

  final covers = annotations.whereType<CoverAnnotation>();
  for (final cover in covers) {
    final left = (cover.x * edited.width).floor();
    final top = (cover.y * edited.height).floor();
    final right = ((cover.x + cover.width) * edited.width).ceil();
    final bottom = ((cover.y + cover.height) * edited.height).ceil();
    if (right <= 0 ||
        bottom <= 0 ||
        left >= edited.width ||
        top >= edited.height) {
      continue;
    }
    img.fillRect(
      edited,
      x1: left,
      y1: top,
      x2: right - 1,
      y2: bottom - 1,
      color: img.ColorRgb8(
        (cover.color >> 16) & 0xff,
        (cover.color >> 8) & 0xff,
        cover.color & 0xff,
      ),
      alphaBlend: false,
    );
  }
  if (covers.isNotEmpty) {
    // Do not retain an original EXIF thumbnail behind an exported cover.
    edited.exif = img.ExifData();
  }

  return Uint8List.fromList(
    img.encodeJpg(edited, quality: quality.jpegQuality),
  );
}

img.Image _applyPhotoFilter(img.Image image, ScanFilter filter) {
  // Palette entries and high-bit channels need real, writable 8-bit RGB(A)
  // pixels before applying the same color math as the preview and eyedropper.
  if (image.hasPalette ||
      image.format != img.Format.uint8 ||
      image.numChannels < 3) {
    image = image.convert(
      format: img.Format.uint8,
      numChannels: image.hasAlpha ? 4 : 3,
      noAnimation: true,
    );
  }
  final hasAlpha = image.hasAlpha;
  if (!hasAlpha && filter == ScanFilter.original) return image;
  for (final pixel in image) {
    final color = photoPixelColor(
      red: pixel.r.toDouble(),
      green: pixel.g.toDouble(),
      blue: pixel.b.toDouble(),
      alpha: hasAlpha ? pixel.a / 255 : 1.0,
      filter: filter,
    );
    pixel.setRgba((color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff, 255);
  }
  return image;
}

String _fontFace(TextAnnotation annotation) =>
    switch ((annotation.bold, annotation.italic)) {
      (true, true) => 'BoldItalic',
      (true, false) => 'Bold',
      (false, true) => 'Italic',
      (false, false) => 'Regular',
    };

PdfColor _pdfColor(int rgb) => PdfColor(
  ((rgb >> 16) & 0xff) / 255,
  ((rgb >> 8) & 0xff) / 255,
  (rgb & 0xff) / 255,
);

img.Image _decodeAndResize(Uint8List bytes, int maximumDimension) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException(
      'One of the selected images could not be read.',
    );
  }

  // copyResize automatically bakes EXIF orientation, which would first make
  // full-resolution copies. Defer that work until after the image is bounded.
  final orientation = decoded.exif.imageIfd.orientation;
  decoded.exif.imageIfd.orientation = null;
  final longestSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final resized = longestSide > maximumDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maximumDimension : null,
          height: decoded.height > decoded.width ? maximumDimension : null,
          interpolation: img.Interpolation.linear,
        )
      : decoded;
  resized.exif.imageIfd.orientation = orientation;
  return resized;
}
