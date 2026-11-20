import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/document_preview.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';
import 'package:mobile_pdf_converter/src/page_editor.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late XFile source;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('rey-editor-test-');
    final file = File('${directory.path}/page.png');
    await file.writeAsBytes(img.encodePng(img.Image(width: 400, height: 600)));
    source = XFile(file.path);
  });

  tearDownAll(() async {
    // A native image read can briefly outlive its removed preview on Windows.
    for (var attempt = 0; ; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32 || attempt >= 19) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  tearDown(() {
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
  });

  Future<void> waitForCanvas(WidgetTester tester) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      if (find.byKey(const ValueKey('page-canvas')).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('The page preview did not finish loading.');
  }

  Future<void> openEditor(
    WidgetTester tester,
    DocumentPage page,
    ValueChanged<DocumentPage?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await Navigator.of(context).push<DocumentPage>(
                  MaterialPageRoute(builder: (_) => PageEditor(page: page)),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await waitForCanvas(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> addText(WidgetTester tester, String text) async {
    await tapVisible(tester, find.text('Add text'));
    await tester.enterText(find.byKey(const ValueKey('page-text-input')), text);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  DocumentPage editedPage(WidgetTester tester) =>
      tester.widget<DocumentPreview>(find.byType(DocumentPreview)).page;

  testWidgets('added text can be edited and deleted before applying', (
    tester,
  ) async {
    DocumentPage? result;
    await openEditor(
      tester,
      DocumentPage(source: source),
      (page) => result = page,
    );
    await addText(tester, 'Original note');
    expect(find.text('Original note'), findsOneWidget);

    await tapVisible(tester, find.text('Edit'));
    await tester.enterText(
      find.byKey(const ValueKey('page-text-input')),
      'Revised note',
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Original note'), findsNothing);
    expect(find.text('Revised note'), findsOneWidget);
    expect(
      editedPage(tester).annotations.whereType<TextAnnotation>().single.text,
      'Revised note',
    );

    await tapVisible(tester, find.byTooltip('Delete selected item'));
    expect(editedPage(tester).annotations, isEmpty);
    expect(find.text('Revised note'), findsNothing);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.annotations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cover placement is inherited by replacement text and Apply saves',
    (tester) async {
      final original = DocumentPage(source: source);
      DocumentPage? result;
      await openEditor(tester, original, (page) => result = page);
      await tapVisible(tester, find.text('Cover printed text'));
      final initialCover =
          editedPage(tester).annotations.single as CoverAnnotation;
      final canvas = tester.getSize(find.byKey(const ValueKey('page-canvas')));
      await tester.drag(
        find.byKey(ValueKey('annotation-${initialCover.id}')),
        Offset(canvas.width * .15, canvas.height * .12),
      );
      await tester.pumpAndSettle();
      final cover = editedPage(tester).annotations.single as CoverAnnotation;
      expect(cover.x, greaterThan(initialCover.x));
      expect(cover.y, greaterThan(initialCover.y));
      await addText(tester, 'Replacement');

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result!.id, same(original.id));
      expect(result!.annotations, hasLength(2));
      final replacement = result!.annotations
          .whereType<TextAnnotation>()
          .single;
      expect(replacement.text, 'Replacement');
      expect(replacement.x, closeTo(cover.x, .0001));
      expect(replacement.y, closeTo(cover.y, .0001));
      expect(replacement.width, cover.width);
      expect(replacement.height, cover.height);
      expect(original.annotations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling text and leaving the page discards pending changes', (
    tester,
  ) async {
    final original = DocumentPage(
      source: source,
      annotations: [TextAnnotation(text: 'Keep this')],
    );
    var completed = false;
    DocumentPage? result;
    await openEditor(tester, original, (page) {
      completed = true;
      result = page;
    });
    await tapVisible(tester, find.text('Add text'));
    await tester.enterText(
      find.byKey(const ValueKey('page-text-input')),
      'Canceled note',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(editedPage(tester).annotations, hasLength(1));
    await tapVisible(tester, find.text('Cover printed text'));
    expect(editedPage(tester).annotations, hasLength(2));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(original.annotations, hasLength(1));
    expect((original.annotations.single as TextAnnotation).text, 'Keep this');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging annotations clamps both edges to the visible page', (
    tester,
  ) async {
    final text = TextAnnotation(
      id: 'drag-target',
      text: 'Move me',
      x: .2,
      y: .2,
      width: .3,
      height: .1,
    );
    DocumentPage? result;
    await openEditor(
      tester,
      DocumentPage(source: source, annotations: [text]),
      (page) => result = page,
    );
    final annotation = find.byKey(const ValueKey('annotation-drag-target'));
    await tester.drag(annotation, const Offset(2000, 2000));
    await tester.pumpAndSettle();
    final bottomRight = editedPage(tester).annotations.single;
    expect(bottomRight.x, closeTo(1 - text.width, .0001));
    expect(bottomRight.y, closeTo(1 - text.height, .0001));

    await tester.drag(annotation, const Offset(-2000, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.annotations.single.x, 0);
    expect(result!.annotations.single.y, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signature size keeps its proportions and stays inside page', (
    tester,
  ) async {
    final signature = SignatureAnnotation(
      id: 'signature',
      x: .5,
      y: .75,
      width: .4,
      height: .12,
      strokes: [
        [const AnnotationPoint(.1, .2), const AnnotationPoint(.8, .7)],
      ],
    );
    await openEditor(
      tester,
      DocumentPage(source: source, annotations: [signature]),
      (_) {},
    );
    await tapVisible(tester, find.text('Signature 1'));
    final slider = find.byKey(const ValueKey('annotation-Size'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(slider);
    await tester.tapAt(Offset(bounds.right - 30, bounds.center.dy));
    await tester.pumpAndSettle();
    final resized = editedPage(tester).annotations.single;
    expect(resized.width, greaterThan(signature.width));
    expect(
      resized.width / resized.height,
      closeTo(signature.width / signature.height, .0001),
    );
    expect(resized.x + resized.width, lessThanOrEqualTo(1));
    expect(resized.y + resized.height, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rotation locks while annotations exist and unlocks after delete',
    (tester) async {
      await openEditor(tester, DocumentPage(source: source), (_) {});
      final rotateLeft = find.widgetWithIcon(IconButton, Icons.rotate_left);
      final rotateRight = find.widgetWithIcon(IconButton, Icons.rotate_right);
      const rotationHelp =
          'Rotate the page before adding text, covers, or signatures.';
      expect(tester.widget<IconButton>(rotateLeft).onPressed, isNotNull);
      expect(tester.widget<IconButton>(rotateRight).onPressed, isNotNull);
      await tapVisible(tester, rotateRight);
      expect(editedPage(tester).quarterTurns, 1);

      await tapVisible(tester, find.text('Cover printed text'));
      expect(editedPage(tester).annotations.single, isA<CoverAnnotation>());
      expect(tester.widget<IconButton>(rotateLeft).onPressed, isNull);
      expect(tester.widget<IconButton>(rotateRight).onPressed, isNull);
      expect(find.text(rotationHelp), findsOneWidget);
      expect(editedPage(tester).quarterTurns, 1);

      await tapVisible(tester, find.byTooltip('Delete selected item'));
      expect(editedPage(tester).annotations, isEmpty);
      expect(tester.widget<IconButton>(rotateLeft).onPressed, isNotNull);
      expect(tester.widget<IconButton>(rotateRight).onPressed, isNotNull);
      expect(find.text(rotationHelp), findsNothing);
      await tapVisible(tester, rotateLeft);
      expect(editedPage(tester).quarterTurns, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor and selected text controls fit a 320 by 480 phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openEditor(tester, DocumentPage(source: source), (_) {});
    await addText(tester, 'Small screen');
    expect(find.text('Apply'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('annotation-Text size')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byTooltip('Delete selected item'));
    expect(editedPage(tester).annotations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text styles, color, and explicit point size survive Apply', (
    tester,
  ) async {
    DocumentPage? result;
    await openEditor(
      tester,
      DocumentPage(
        source: source,
        annotations: [TextAnnotation(text: 'Styled note')],
      ),
      (page) => result = page,
    );
    await tapVisible(tester, find.text('Text 1'));
    for (final label in ['Bold', 'Italic', 'Underline', 'Strikethrough']) {
      await tapVisible(tester, find.widgetWithText(FilterChip, label));
    }
    await tapVisible(
      tester,
      find.byKey(const ValueKey('Text color-color-blue')),
    );
    final sizeField = find.byKey(const ValueKey('text-size-pt'));
    await tester.ensureVisible(sizeField);
    await tester.pumpAndSettle();
    await tester.enterText(sizeField, '24.5');
    await tester.pump();

    final previewText = tester.widget<Text>(find.text('Styled note'));
    expect(previewText.style!.fontWeight, FontWeight.bold);
    expect(previewText.style!.fontStyle, FontStyle.italic);
    expect(previewText.style!.color, const Color(0xff1565c0));
    expect(
      previewText.style!.decoration!.contains(TextDecoration.underline),
      isTrue,
    );
    expect(
      previewText.style!.decoration!.contains(TextDecoration.lineThrough),
      isTrue,
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final text = result!.annotations.single as TextAnnotation;
    expect(text.bold, isTrue);
    expect(text.italic, isTrue);
    expect(text.underline, isTrue);
    expect(text.strikethrough, isTrue);
    expect(text.color, 0x1565c0);
    expect(text.fontSizePt, 24.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover and signature palette changes survive Apply', (
    tester,
  ) async {
    DocumentPage? result;
    await openEditor(
      tester,
      DocumentPage(
        source: source,
        annotations: [
          CoverAnnotation(),
          SignatureAnnotation(
            strokes: [
              [const AnnotationPoint(.1, .2), const AnnotationPoint(.8, .7)],
            ],
          ),
        ],
      ),
      (page) => result = page,
    );
    await tapVisible(tester, find.text('Cover 1'));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('Cover color-color-green')),
    );
    await tapVisible(tester, find.text('Signature 2'));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('Signature color-color-red')),
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(
      result!.annotations.whereType<CoverAnnotation>().single.color,
      0x2e7d32,
    );
    expect(
      result!.annotations.whereType<SignatureAnnotation>().single.color,
      0xd32f2f,
    );
    expect(
      result!.annotations
          .whereType<SignatureAnnotation>()
          .single
          .strokes
          .single,
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'photo color sampling can cancel or apply an original photo color',
    (tester) async {
      DocumentPage? result;
      await openEditor(
        tester,
        DocumentPage(source: source, annotations: [CoverAnnotation()]),
        (page) => result = page,
      );
      await tapVisible(tester, find.text('Cover 1'));
      final pickColor = find.byKey(const ValueKey('pick-color-from-photo'));
      await tapVisible(tester, pickColor);
      expect(
        find.text(
          'Tap a color in the photo. For a cover, pick the nearby background.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Apply'))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('photo-color-picker')), findsOneWidget);
      await tester.tap(find.text('Cancel picker'));
      await tester.pumpAndSettle();
      expect(
        editedPage(tester).annotations
            .whereType<CoverAnnotation>()
            .single
            .color,
        0xffffff,
      );
      expect(find.byKey(const ValueKey('photo-color-picker')), findsNothing);

      await tapVisible(tester, pickColor);
      final photo = tester.getRect(
        find.byKey(const ValueKey('photo-color-picker')),
      );
      // The cover itself is white. Sample its location to verify that the picker
      // reads the original black photo instead of the annotation painted on top.
      await tester.tapAt(
        photo.topLeft + Offset(photo.width * .3, photo.height * .34),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('photo-color-picker'))
            .evaluate()
            .isEmpty) {
          break;
        }
      }
      expect(find.byKey(const ValueKey('photo-color-picker')), findsNothing);
      expect(
        editedPage(tester).annotations
            .whereType<CoverAnnotation>()
            .single
            .color,
        0x000000,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Apply'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        result!.annotations.whereType<CoverAnnotation>().single.color,
        0x000000,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      binding.imageCache.clear();
      binding.imageCache.clearLiveImages();
      for (var frame = 0; frame < 3; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
    },
  );
}
