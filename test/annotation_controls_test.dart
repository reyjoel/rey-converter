import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pdf_converter/src/annotation_controls.dart';

void main() {
  const sizeField = ValueKey('text-size-pt');
  const sizeSlider = ValueKey('annotation-Text size');

  Future<void> openSizeControl(
    WidgetTester tester, {
    double initialValue = 12,
    required ValueChanged<double> onChanged,
  }) async {
    var value = initialValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  PointSizeControl(
                    value: value,
                    onChanged: (size) {
                      setState(() => value = size);
                      onChanged(size);
                    },
                  ),
                  TextButton(
                    onPressed: () => FocusScope.of(context).unfocus(),
                    child: const Text('Outside'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(sizeField)).controller!.text;

  testWidgets(
    'manual point sizes update slider and preserve decimal precision',
    (tester) async {
      final changes = <double>[];
      await openSizeControl(tester, onChanged: changes.add);

      await tester.enterText(find.byKey(sizeField), '24.25');
      await tester.pump();
      expect(changes.last, 24.25);
      expect(tester.widget<Slider>(find.byKey(sizeSlider)).value, 24.25);
      expect(fieldText(tester), '24.25');

      await tester.tap(find.text('Outside'));
      await tester.pumpAndSettle();
      expect(fieldText(tester), '24.25');
      expect(tester.widget<Slider>(find.byKey(sizeSlider)).value, 24.25);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('moving the slider synchronizes numeric point size', (
    tester,
  ) async {
    final changes = <double>[];
    await openSizeControl(tester, onChanged: changes.add);
    final bounds = tester.getRect(find.byKey(sizeSlider));
    await tester.tapAt(bounds.center);
    await tester.pumpAndSettle();

    final value = tester.widget<Slider>(find.byKey(sizeSlider)).value;
    expect(value, greaterThan(12));
    expect(changes.last, value);
    expect(double.parse(fieldText(tester)), value);
    expect(find.text('pt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty or invalid values stay local and recover on blur', (
    tester,
  ) async {
    final changes = <double>[];
    await openSizeControl(tester, onChanged: changes.add);
    for (final input in [
      '',
      '.',
      '3',
      '145',
      'NaN',
      'Infinity',
      '12..3',
      '1e2',
      '-6',
    ]) {
      await tester.enterText(find.byKey(sizeField), input);
      await tester.pump();
      expect(changes, isEmpty, reason: '$input must not reach the annotation');
      expect(tester.widget<Slider>(find.byKey(sizeSlider)).value, 12);
      expect(fieldText(tester), input);
    }
    expect(find.text('Enter a size from 4 to 144 pt.'), findsOneWidget);
    await tester.tap(find.text('Outside'));
    await tester.pumpAndSettle();
    expect(fieldText(tester), '12');
    expect(find.text('Enter a size from 4 to 144 pt.'), findsNothing);
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'in-progress decimals keep focus and selection updates refresh value',
    (tester) async {
      var value = 12.0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return PointSizeControl(
                  value: value,
                  onChanged: (size) => setState(() => value = size),
                );
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(sizeField), '24.');
      await tester.pump();
      expect(value, 24);
      expect(fieldText(tester), '24.');
      expect(
        tester.widget<TextField>(find.byKey(sizeField)).focusNode!.hasFocus,
        isTrue,
      );
      rebuild(() => value = 72);
      await tester.pump();
      expect(fieldText(tester), '72');
      expect(tester.widget<Slider>(find.byKey(sizeSlider)).value, 72);
      expect(
        tester.widget<TextField>(find.byKey(sizeField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> openColorControl(
    WidgetTester tester,
    ValueChanged<int> onChanged,
  ) async {
    var value = 0x000000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => AnnotationColorControl(
                label: 'Text color',
                color: value,
                onChanged: (color) {
                  setState(() => value = color);
                  onChanged(color);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('color presets expose selected state and chosen RGB value', (
    tester,
  ) async {
    final changes = <int>[];
    await openColorControl(tester, changes.add);
    await tester.tap(find.byKey(const ValueKey('Text color-color-blue')));
    await tester.pump();
    expect(changes, [0x1565c0]);
    expect(find.text('#1565C0'), findsOneWidget);
    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((item) => item.properties.label == 'Text color: Blue');
    expect(selected.properties.selected, isTrue);
    expect(selected.properties.label, 'Text color: Blue');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom hex color validates and cancellation preserves the color',
    (tester) async {
      final changes = <int>[];
      await openColorControl(tester, changes.add);
      final custom = find.byKey(const ValueKey('Text color-custom-color'));
      await tester.tap(custom);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-color-hex')),
        '#12345G',
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Enter six hexadecimal digits.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('custom-color-hex')),
        '#a1b2c3',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(changes, [0xa1b2c3]);
      expect(find.text('#A1B2C3'), findsOneWidget);

      await tester.tap(custom);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-color-hex')),
        'ffffff',
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(changes, [0xa1b2c3]);
      expect(find.text('#A1B2C3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('size and color controls fit a 320 pixel phone', (tester) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                PointSizeControl(value: 12, onChanged: (_) {}),
                AnnotationColorControl(
                  label: 'Cover color',
                  color: 0xffffff,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(sizeField), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
