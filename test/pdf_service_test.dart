import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/pdf_service.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';
import 'package:mobile_pdf_converter/src/image_color_sampling.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('large EXIF-oriented images stay bounded after page rotation', () {
    final source = img.Image(width: 1600, height: 800);
    source.exif.imageIfd.orientation = 6;
    final bytes = img.encodeJpg(source);
    final result = PdfService().preparePageImage(
      bytes,
      DocumentPage(source: XFile.fromData(bytes), quarterTurns: 1),
      PdfImageQuality.compact,
    );
    final decoded = img.decodeJpg(result)!;

    expect(decoded.width, 1280);
    expect(decoded.height, 640);
    expect(decoded.exif.imageIfd.orientation, isNull);
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

  test(
    'PDF generation yields to the UI event loop before processing',
    () async {
      var eventLoopRan = false;
      Timer.run(() => eventLoopRan = true);
      final progress = <bool>[];

      await PdfService().createPdf(
        pages: [DocumentPage(source: XFile.fromData(sourceBytes))],
        quality: PdfImageQuality.compact,
        onProgress: (_, _) => progress.add(eventLoopRan),
      );

      expect(progress, [true]);
    },
  );

  test('worker can read images from files and apply page edits', () async {
    final directory = await Directory.systemTemp.createTemp('rey_pdf_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/page.png')
        .writeAsBytes(sourceBytes);

    final result = await PdfService().createPdf(
      pages: [
        DocumentPage(
          source: XFile(file.path),
          quarterTurns: 1,
          filter: ScanFilter.highContrast,
        ),
      ],
      quality: PdfImageQuality.compact,
    );

    expect(String.fromCharCodes(result.take(5)), '%PDF-');
  });

  test('worker propagates invalid image errors to the caller', () async {
    await expectLater(
      PdfService().createPdf(
        pages: [DocumentPage(source: XFile.fromData(Uint8List(32)))],
        quality: PdfImageQuality.compact,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('white covers replace pixels on the final rotated page image', () {
    final source = img.Image(width: 100, height: 80);
    img.fill(source, color: img.ColorRgb8(20, 30, 40));
    final bytes = img.encodePng(source);
    final page = DocumentPage(
      source: XFile.fromData(bytes),
      quarterTurns: 1,
      filter: ScanFilter.highContrast,
      annotations: [CoverAnnotation(x: .25, y: .25, width: .5, height: .5)],
    );
    final prepared = PdfService().preparePageImage(
      bytes,
      page,
      PdfImageQuality.high,
    );
    final masked = img.decodeJpg(prepared)!;

    expect(masked.width, 80);
    expect(masked.height, 100);
    expect(masked.getPixel(40, 50).r, greaterThan(245));
    expect(masked.getPixel(5, 5).r, lessThan(30));
    expect(masked.exif.isEmpty, isTrue);
  });

  test(
    'worker exports baked masks, text, and vector signature strokes',
    () async {
      final source = img.Image(width: 100, height: 80);
      img.fill(source, color: img.ColorRgb8(20, 30, 40));
      final bytes = img.encodePng(source);
      final annotations = <PageAnnotation>[
        CoverAnnotation(x: .25, y: .25, width: .5, height: .5),
        TextAnnotation(text: 'Edited title ñ', x: .25, y: .25),
        SignatureAnnotation(
          x: .2,
          y: .7,
          width: .5,
          height: .2,
          strokes: [
            [
              const AnnotationPoint(.1, .2),
              const AnnotationPoint(.5, .8),
              const AnnotationPoint(.9, .2),
            ],
          ],
        ),
      ];

      final pdf = await PdfService().createPdf(
        pages: [
          DocumentPage(source: XFile.fromData(bytes), annotations: annotations),
        ],
        quality: PdfImageQuality.high,
      );
      final streams = _pdfStreams(pdf);
      final jpeg = streams.firstWhere(
        (stream) => stream.length > 2 && stream[0] == 0xff && stream[1] == 0xd8,
      );
      final image = img.decodeJpg(jpeg)!;
      expect(image.getPixel(50, 40).r, greaterThan(245));
      expect(image.getPixel(5, 5).r, lessThan(45));

      final content = streams
          .where((stream) => stream.length < 2 || stream[0] != 0xff)
          .map((stream) {
            try {
              return latin1.decode(zlib.decode(stream));
            } catch (_) {
              return latin1.decode(stream);
            }
          })
          .join('\n');
      final sourcePdf = latin1.decode(pdf);
      expect(sourcePdf, contains('/FontFile2'));
      expect(sourcePdf, contains('/ToUnicode'));
      // The embedded font maps its glyph indices back to the entered Unicode.
      expect(content.toLowerCase(), contains('<0045>'));
      expect(content.toLowerCase(), contains('<00f1>'));
      // PDF stroke coordinates invert the signature's top-left y coordinates.
      final stroke = RegExp(
        r'([\d.]+) ([\d.]+) m ([\d.]+) ([\d.]+) l ([\d.]+) ([\d.]+) l S',
      ).firstMatch(content)!;
      final pageWidth = PdfPageFormat.a4.width - 48;
      final signatureWidth = pageWidth * .5;
      final signatureHeight = (pageWidth / 1.25) * .2;
      expect(double.parse(stroke[1]!), closeTo(signatureWidth * .1, .0001));
      expect(double.parse(stroke[2]!), closeTo(signatureHeight * .8, .0001));
      expect(double.parse(stroke[3]!), closeTo(signatureWidth * .5, .0001));
      expect(double.parse(stroke[4]!), closeTo(signatureHeight * .2, .0001));
      expect(double.parse(stroke[5]!), closeTo(signatureWidth * .9, .0001));
    },
  );

  test('colored covers replace pixels after filters and retain no EXIF', () {
    final source = img.Image(width: 100, height: 100);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    final bytes = img.encodePng(source);
    final result = PdfService().preparePageImage(
      bytes,
      DocumentPage(
        source: XFile.fromData(bytes),
        filter: ScanFilter.grayscale,
        annotations: [
          CoverAnnotation(color: 0xecd8b1, x: .2, y: .2, width: .6, height: .6),
        ],
      ),
      PdfImageQuality.high,
    );
    final image = img.decodeJpg(result)!;
    final color = image.getPixel(50, 50);
    expect(color.r, closeTo(236, 3));
    expect(color.g, closeTo(216, 3));
    expect(color.b, closeTo(177, 3));
    expect(image.exif.isEmpty, isTrue);
    final outside = image.getPixel(5, 5);
    expect(outside.r, closeTo(outside.g, 2));
    expect(outside.g, closeTo(outside.b, 2));
  });

  test(
    'PDF photo colors match sampled preview filters and white compositing',
    () {
      for (final alpha in [0, 128, 255]) {
        final source = img.Image(width: 24, height: 24, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(50, 100, 150, alpha));
        final bytes = img.encodePng(source);
        for (final filter in ScanFilter.values) {
          final expected = sampleRgbaColor(
            rgba: Uint8List.fromList([50, 100, 150, alpha]),
            width: 1,
            height: 1,
            x: .5,
            y: .5,
            filter: filter,
          );
          final prepared = PdfService().preparePageImage(
            bytes,
            DocumentPage(source: XFile.fromData(bytes), filter: filter),
            PdfImageQuality.high,
          );
          final pixel = img.decodeJpg(prepared)!.getPixel(12, 12);
          expect(
            pixel.r,
            closeTo((expected >> 16) & 0xff, 2),
            reason: '$filter, alpha=$alpha red',
          );
          expect(
            pixel.g,
            closeTo((expected >> 8) & 0xff, 2),
            reason: '$filter, alpha=$alpha green',
          );
          expect(
            pixel.b,
            closeTo(expected & 0xff, 2),
            reason: '$filter, alpha=$alpha blue',
          );
        }
      }
    },
  );

  test('palette and 16-bit photo channels are normalized before filtering', () {
    final palette = img.Image(
      width: 24,
      height: 24,
      numChannels: 4,
      withPalette: true,
    );
    palette.palette!.setRgba(0, 50, 100, 150, 128);
    final highBit = img.Image(
      width: 24,
      height: 24,
      format: img.Format.uint16,
      numChannels: 4,
    );
    for (final pixel in highBit) {
      pixel.setRgba(50 * 257, 100 * 257, 150 * 257, 128 * 257);
    }
    for (final source in [palette, highBit]) {
      final bytes = img.encodePng(source);
      for (final filter in ScanFilter.values) {
        final expected = sampleRgbaColor(
          rgba: Uint8List.fromList([50, 100, 150, 128]),
          width: 1,
          height: 1,
          x: .5,
          y: .5,
          filter: filter,
        );
        final prepared = PdfService().preparePageImage(
          bytes,
          DocumentPage(source: XFile.fromData(bytes), filter: filter),
          PdfImageQuality.high,
        );
        final pixel = img.decodeJpg(prepared)!.getPixel(12, 12);
        expect(pixel.r, closeTo((expected >> 16) & 0xff, 2));
        expect(pixel.g, closeTo((expected >> 8) & 0xff, 2));
        expect(pixel.b, closeTo(expected & 0xff, 2));
      }
    }
  });

  test(
    'PDF keeps explicit point size across image aspects and styles',
    () async {
      final pageBytes = img.encodePng(img.Image(width: 200, height: 400));
      final annotations = <PageAnnotation>[
        TextAnnotation(
          text: 'Regular',
          fontSizePt: 18.5,
          color: 0xff0000,
          x: .1,
          y: .05,
          width: .8,
          height: .1,
        ),
        TextAnnotation(
          text: 'Bold',
          fontSizePt: 19,
          bold: true,
          x: .1,
          y: .2,
          width: .8,
          height: .1,
        ),
        TextAnnotation(
          text: 'Italic',
          fontSizePt: 20,
          italic: true,
          x: .1,
          y: .35,
          width: .8,
          height: .1,
        ),
        TextAnnotation(
          text: 'Both',
          fontSizePt: 21,
          bold: true,
          italic: true,
          underline: true,
          strikethrough: true,
          color: 0xff0000,
          x: .1,
          y: .5,
          width: .8,
          height: .1,
        ),
        SignatureAnnotation(
          color: 0x0000ff,
          strokes: [
            [
              const AnnotationPoint(.1, .2),
              const AnnotationPoint(.4, .8),
              const AnnotationPoint(.9, .3),
            ],
          ],
        ),
      ];
      final pdf = await PdfService().createPdf(
        pages: [
          DocumentPage(
            source: XFile.fromData(pageBytes),
            annotations: annotations,
          ),
          DocumentPage(
            source: XFile.fromData(pageBytes),
            quarterTurns: 1,
            annotations: annotations,
          ),
        ],
        quality: PdfImageQuality.high,
      );
      final content = _decodedStreams(pdf);
      final source = latin1.decode(pdf);
      for (final face in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
        expect(source, contains('/Roboto-$face'));
      }
      for (final size in ['18.5', '19', '20', '21']) {
        expect(RegExp('/F\\d+ $size Tf').allMatches(content), hasLength(2));
      }
      expect(content, contains('1 0 0 rg'));
      expect(content, contains('0 0 1 RG'));
      final horizontalLines =
          RegExp(r'([\d.]+) ([\d.]+) m ([\d.]+) ([\d.]+) l S')
              .allMatches(content)
              .where((line) => line[2] == line[4] && line[1] != line[3]);
      // Each page has an underline and strikethrough on the final text box.
      expect(horizontalLines, hasLength(4));
    },
  );
}

String _decodedStreams(Uint8List pdf) =>
    _pdfStreams(pdf)
        .where((stream) => stream.length < 2 || stream[0] != 0xff)
        .map((stream) {
          try {
            return latin1.decode(zlib.decode(stream));
          } catch (_) {
            return latin1.decode(stream);
          }
        })
        .join('\n');

List<Uint8List> _pdfStreams(Uint8List bytes) {
  final source = latin1.decode(bytes);
  return RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream')
      .allMatches(source)
      .map((match) => Uint8List.fromList(latin1.encode(match.group(1)!)))
      .toList();
}
