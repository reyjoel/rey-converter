import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    required List<XFile> images,
    required PdfImageQuality quality,
    void Function(int completed, int total)? onProgress,
  }) async {
    final document = pw.Document(
      title: 'REY Converter',
      creator: 'REY Converter',
      compress: true,
    );

    for (var index = 0; index < images.length; index++) {
      final originalBytes = await images[index].readAsBytes();
      final preparedBytes = _prepareImage(originalBytes, quality);
      final pdfImage = pw.MemoryImage(preparedBytes);

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) =>
              pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
        ),
      );
      onProgress?.call(index + 1, images.length);
    }

    return document.save();
  }

  Uint8List _prepareImage(Uint8List bytes, PdfImageQuality quality) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'One of the selected images could not be read.',
      );
    }

    final corrected = img.bakeOrientation(decoded);
    final longestSide = corrected.width > corrected.height
        ? corrected.width
        : corrected.height;
    final resized = longestSide > quality.maximumDimension
        ? img.copyResize(
            corrected,
            width: corrected.width >= corrected.height
                ? quality.maximumDimension
                : null,
            height: corrected.height > corrected.width
                ? quality.maximumDimension
                : null,
            interpolation: img.Interpolation.linear,
          )
        : corrected;

    return Uint8List.fromList(
      img.encodeJpg(resized, quality: quality.jpegQuality),
    );
  }
}
