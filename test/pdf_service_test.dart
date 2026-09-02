import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/pdf_service.dart';

void main() {
  late Uint8List sourceBytes;

  setUp(() {
    final source = img.Image(width: 4, height: 2);
    source.setPixelRgb(0, 0, 240, 40, 20);
    sourceBytes = Uint8List.fromList(img.encodePng(source));
  });

  test('page rotation is applied before PDF encoding', () {
    final service = PdfService();
    final page = DocumentPage(
      source: XFile.fromData(sourceBytes),
      quarterTurns: 1,
    );

    final result = service.preparePageImage(
      sourceBytes,
      page,
      PdfImageQuality.high,
    );
    final decoded = img.decodeJpg(result)!;

    expect(decoded.width, 2);
    expect(decoded.height, 4);
  });

  test('grayscale filter produces neutral color channels', () {
    final service = PdfService();
    final page = DocumentPage(
      source: XFile.fromData(sourceBytes),
      filter: ScanFilter.grayscale,
    );

    final result = service.preparePageImage(
      sourceBytes,
      page,
      PdfImageQuality.high,
    );
    final pixel = img.decodeJpg(result)!.getPixel(0, 0);

    expect((pixel.r - pixel.g).abs(), lessThanOrEqualTo(2));
    expect((pixel.g - pixel.b).abs(), lessThanOrEqualTo(2));
  });

  test('PDF generation reports every completed page', () async {
    final service = PdfService();
    final completed = <int>[];
    final pages = [
      DocumentPage(source: XFile.fromData(sourceBytes)),
      DocumentPage(source: XFile.fromData(sourceBytes)),
    ];

    final result = await service.createPdf(
      pages: pages,
      quality: PdfImageQuality.compact,
      onProgress: (done, _) => completed.add(done),
    );

    expect(result, isNotEmpty);
    expect(completed, [1, 2]);
  });
}
