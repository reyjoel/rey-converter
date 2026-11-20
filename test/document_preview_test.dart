import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/document_preview.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';
import 'package:pdf/pdf.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late XFile quadrants;
  late XFile portrait;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('rey-color-preview-');
    final image = img.Image(width: 120, height: 80);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 59,
      y2: 39,
      color: img.ColorRgb8(255, 0, 0),
    );
    img.fillRect(
      image,
      x1: 60,
      y1: 0,
      x2: 119,
      y2: 39,
      color: img.ColorRgb8(0, 255, 0),
    );
    img.fillRect(
      image,
      x1: 0,
      y1: 40,
      x2: 59,
      y2: 79,
      color: img.ColorRgb8(0, 0, 255),
    );
    img.fillRect(
      image,
      x1: 60,
      y1: 40,
      x2: 119,
      y2: 79,
      color: img.ColorRgb8(255, 255, 0),
    );
    final landscapeFile = await File('${directory.path}/quadrants.png')
        .writeAsBytes(img.encodePng(image));
    final portraitFile = await File('${directory.path}/portrait.png')
        .writeAsBytes(img.encodePng(img.Image(width: 80, height: 120)));
    quadrants = XFile(landscapeFile.path);
    portrait = XFile(portraitFile.path);
  });

  tearDownAll(() => directory.delete(recursive: true));

  tearDown(() {
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
  });

  Future<void> flushUntil(WidgetTester tester, bool Function() finished) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      if (finished()) return;
    }
    fail('The image preview did not finish its asynchronous work.');
  }

  Future<void> openPreview(
    WidgetTester tester,
    DocumentPage page, {
    ValueChanged<int>? onSampled,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: DocumentPreview(page: page, onColorSampled: onSampled),
            ),
          ),
        ),
      ),
    );
    await flushUntil(tester, () {
      if (find.byKey(const ValueKey('page-canvas')).evaluate().isEmpty) {
        return false;
      }
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.isEmpty || images.first.image == null) return false;
      final decoded = images.first.image!;
      return page.source.path == portrait.path
          ? decoded.width == 80 && decoded.height == 120
          : decoded.width == 120 && decoded.height == 80;
    });
  }

  Offset photoPoint(WidgetTester tester, double x, double y) {
    final rect = tester.getRect(
      find.byKey(const ValueKey('photo-color-picker')),
    );
    return rect.topLeft + Offset(rect.width * x, rect.height * y);
  }

  testWidgets(
    'eyedropper hides a colored cover and samples the original photo',
    (tester) async {
      final sampled = <int>[];
      final cover = CoverAnnotation(
        id: 'cover',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        color: 0x123456,
      );
      final page = DocumentPage(source: quadrants, annotations: [cover]);
      await openPreview(tester, page);
      expect(find.byKey(const ValueKey('annotation-cover')), findsOneWidget);

      await openPreview(tester, page, onSampled: sampled.add);
      expect(find.byKey(const ValueKey('annotation-cover')), findsNothing);
      await tester.tapAt(photoPoint(tester, .25, .25));
      await flushUntil(tester, () => sampled.isNotEmpty);
      expect(sampled, [0xff0000]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('eyedropper respects all displayed page rotations', (
    tester,
  ) async {
    const expected = [0xff0000, 0x0000ff, 0xffff00, 0x00ff00];
    for (var turn = 0; turn < 4; turn++) {
      final sampled = <int>[];
      await openPreview(
        tester,
        DocumentPage(source: quadrants, quarterTurns: turn),
        onSampled: sampled.add,
      );
      await tester.tapAt(photoPoint(tester, .25, .25));
      await flushUntil(tester, () => sampled.isNotEmpty);
      expect(sampled.single, expected[turn]);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('eyedropper returns the filtered color visible on the photo', (
    tester,
  ) async {
    for (final (filter, expected) in [
      (ScanFilter.grayscale, 0x363636),
      (ScanFilter.highContrast, 0x000000),
    ]) {
      final sampled = <int>[];
      await openPreview(
        tester,
        DocumentPage(source: quadrants, filter: filter),
        onSampled: sampled.add,
      );
      await tester.tapAt(photoPoint(tester, .25, .25));
      await flushUntil(tester, () => sampled.isNotEmpty);
      expect(sampled.single, expected);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canceling sampling restores overlays and ignores pending samples',
    (tester) async {
      final sampled = <int>[];
      final page = DocumentPage(
        source: quadrants,
        annotations: [CoverAnnotation(id: 'cover', color: 0x112233)],
      );
      await openPreview(tester, page, onSampled: sampled.add);
      final picker = tester.widget<GestureDetector>(
        find.byKey(const ValueKey('photo-color-picker')),
      );
      final rect = tester.getRect(
        find.byKey(const ValueKey('photo-color-picker')),
      );
      // Start the native pixel read, then cancel before flushing its future.
      picker.onTapUp!(
        TapUpDetails(
          kind: PointerDeviceKind.touch,
          localPosition: Offset(rect.width * .25, rect.height * .25),
        ),
      );
      await openPreview(tester, page);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('photo-color-picker')), findsNothing);
      expect(find.byKey(const ValueKey('annotation-cover')), findsOneWidget);
      expect(sampled, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview honors text styles, colors, and true point sizes', (
    tester,
  ) async {
    for (final source in [quadrants, portrait]) {
      final text = TextAnnotation(
        text: 'Styled note',
        fontSizePt: 24,
        color: 0x2468ac,
        bold: true,
        italic: true,
        underline: true,
        strikethrough: true,
      );
      final signature = SignatureAnnotation(
        strokes: [
          [const AnnotationPoint(.1, .2), const AnnotationPoint(.8, .7)],
        ],
        color: 0x884422,
      );
      final cover = CoverAnnotation(id: 'color-cover', color: 0xaaccdd);
      await openPreview(
        tester,
        DocumentPage(source: source, annotations: [cover, text, signature]),
      );
      final rendered = tester.widget<Text>(find.text('Styled note'));
      expect(rendered.style!.color, const Color(0xff2468ac));
      expect(rendered.style!.fontWeight, FontWeight.bold);
      expect(rendered.style!.fontStyle, FontStyle.italic);
      expect(
        rendered.style!.decoration!.contains(TextDecoration.underline),
        isTrue,
      );
      expect(
        rendered.style!.decoration!.contains(TextDecoration.lineThrough),
        isTrue,
      );
      final canvas = tester.getSize(find.byKey(const ValueKey('page-canvas')));
      final sourceAspect = source == quadrants ? 1.5 : 2 / 3;
      final exportedWidth = math.min(
        PdfPageFormat.a4.width - 48,
        (PdfPageFormat.a4.height - 48) * sourceAspect,
      );
      expect(
        rendered.style!.fontSize! / canvas.width * exportedWidth,
        closeTo(24, .0001),
      );

      final coloredCover = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('annotation-color-cover')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(coloredCover.color, const Color(0xffaaccdd));
      final signaturePaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(ValueKey('annotation-${signature.id}')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((signaturePaint.painter! as SignaturePainter).color, 0x884422);
    }
    expect(tester.takeException(), isNull);
  });
}
