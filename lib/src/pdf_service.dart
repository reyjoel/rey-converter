import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_page.dart';

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
    final document = pw.Document(
      title: 'REY Converter',
      creator: 'REY Converter',
      compress: true,
    );

    for (var index = 0; index < pages.length; index++) {
      final originalBytes = await pages[index].source.readAsBytes();
      final preparedBytes = preparePageImage(
        originalBytes,
        pages[index],
        quality,
      );
      final pdfImage = pw.MemoryImage(preparedBytes);

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) =>
              pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
        ),
      );
      onProgress?.call(index + 1, pages.length);
    }

    return document.save();
  }

  Uint8List preparePageImage(
    Uint8List bytes,
    DocumentPage page,
    PdfImageQuality quality,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'One of the selected images could not be read.',
      );
    }

    final corrected = img.bakeOrientation(decoded);
    var edited = corrected;
    if (page.quarterTurns != 0) {
      edited = img.copyRotate(edited, angle: page.quarterTurns * 90);
    }
    edited = switch (page.filter) {
      ScanFilter.original => edited,
      ScanFilter.grayscale => img.grayscale(edited),
      ScanFilter.highContrast => img.adjustColor(
        img.grayscale(edited),
        contrast: 1.45,
      ),
    };

    final longestSide = edited.width > edited.height
        ? edited.width
        : edited.height;
    final resized = longestSide > quality.maximumDimension
        ? img.copyResize(
            edited,
            width: edited.width >= edited.height
                ? quality.maximumDimension
                : null,
            height: edited.height > edited.width
                ? quality.maximumDimension
                : null,
            interpolation: img.Interpolation.linear,
          )
        : edited;

    return Uint8List.fromList(
      img.encodeJpg(resized, quality: quality.jpegQuality),
    );
  }
}
