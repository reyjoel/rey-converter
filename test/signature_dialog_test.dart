import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';
import 'package:mobile_pdf_converter/src/signature_dialog.dart';

void main() {
  Future<void> openPad(
    WidgetTester tester,
    ValueChanged<List<List<AnnotationPoint>>?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  onResult(await showSignatureDialog(context)),
              child: const Text('Sign'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sign'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty signatures cannot be accepted and Cancel returns null', (
    tester,
  ) async {
    var completed = false;
    List<List<AnnotationPoint>>? result;
    await openPad(tester, (value) {
      completed = true;
      result = value;
    });

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('drawn strokes return normalized points and taps keep dots', (
    tester,
  ) async {
    List<List<AnnotationPoint>>? result;
    await openPad(tester, (value) => result = value);
    final pad = find.byKey(const ValueKey('signature-pad'));
    final bounds = tester.getRect(pad);
    await tester.dragFrom(
      bounds.topLeft + Offset(bounds.width * 0.1, bounds.height * 0.3),
      Offset(bounds.width * 0.5, bounds.height * 0.4),
    );
    await tester.tapAt(
      bounds.topLeft + Offset(bounds.width * 0.8, bounds.height * 0.3),
    );
    await tester.pump();
    await tester.tap(find.text('Use signature'));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result!.first.length, greaterThan(1));
    expect(result!.last, hasLength(1));
    for (final stroke in result!) {
      for (final point in stroke) {
        expect(point.x, inInclusiveRange(0.0, 1.0));
        expect(point.y, inInclusiveRange(0.0, 1.0));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo removes the last stroke and clear empties the pad', (
    tester,
  ) async {
    List<List<AnnotationPoint>>? result;
    await openPad(tester, (value) => result = value);
    final pad = find.byKey(const ValueKey('signature-pad'));
    await tester.drag(pad, const Offset(50, 10));
    await tester.tap(pad);
    await tester.pump();
    await tester.tap(find.text('Undo stroke'));
    await tester.pump();
    await tester.tap(find.text('Use signature'));
    await tester.pumpAndSettle();
    expect(result, hasLength(1));
    expect(result!.first.length, greaterThan(1));

    await tester.tap(find.text('Sign'));
    await tester.pumpAndSettle();
    await tester.tap(pad);
    await tester.pump();
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signature tools fit a small phone without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPad(tester, (_) {});
    expect(find.text('Use signature'), findsOneWidget);
    expect(find.byKey(const ValueKey('signature-pad')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
