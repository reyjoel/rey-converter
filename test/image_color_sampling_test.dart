import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/image_color_sampling.dart';

void main() {
  final quadrants = Uint8List.fromList([
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    255,
    0,
    0,
    255,
    255,
    255,
    255,
    0,
    255,
  ]);

  int sample(double x, double y, {int turns = 0}) => sampleRgbaColor(
    rgba: quadrants,
    width: 2,
    height: 2,
    x: x,
    y: y,
    quarterTurns: turns,
  );

  test('samples exact colors in each unrotated quadrant', () {
    expect(sample(.25, .25), 0xff0000);
    expect(sample(.75, .25), 0x00ff00);
    expect(sample(.25, .75), 0x0000ff);
    expect(sample(.75, .75), 0xffff00);
  });

  test(
    'shared export transform and eyedropper agree for every filter and alpha',
    () {
      for (final filter in ScanFilter.values) {
        for (final alpha in [0, 64, 128, 255]) {
          final direct = photoPixelColor(
            red: 20,
            green: 100,
            blue: 200,
            alpha: alpha / 255,
            filter: filter,
          );
          final sampled = sampleRgbaColor(
            rgba: Uint8List.fromList([20, 100, 200, alpha]),
            width: 1,
            height: 1,
            x: .5,
            y: .5,
            filter: filter,
          );
          expect(direct, sampled);
        }
      }
    },
  );

  test('display coordinates map back through all quarter turns', () {
    const positions = [(.25, .25), (.75, .25), (.25, .75), (.75, .75)];
    const expected = [
      [0xff0000, 0x00ff00, 0x0000ff, 0xffff00],
      [0x0000ff, 0xff0000, 0xffff00, 0x00ff00],
      [0xffff00, 0x0000ff, 0x00ff00, 0xff0000],
      [0x00ff00, 0xffff00, 0xff0000, 0x0000ff],
    ];
    for (var turn = 0; turn < 4; turn++) {
      for (var index = 0; index < positions.length; index++) {
        final (x, y) = positions[index];
        expect(sample(x, y, turns: turn), expected[turn][index]);
      }
    }
    expect(sample(.25, .25, turns: -1), sample(.25, .25, turns: 3));
    expect(sample(.25, .25, turns: 5), sample(.25, .25, turns: 1));
  });

  test('clamps out-of-bounds positions and includes exact image edges', () {
    expect(sample(-10, -10), 0xff0000);
    expect(sample(1, 1), 0xffff00);
    expect(sample(50, 50), 0xffff00);
    expect(sample(0, 1, turns: 1), 0xffff00);
  });

  test('transparent and translucent pixels composite onto white', () {
    int alphaSample(int alpha) => sampleRgbaColor(
      rgba: Uint8List.fromList([20, 100, 200, alpha]),
      width: 1,
      height: 1,
      x: .5,
      y: .5,
    );
    expect(alphaSample(0), 0xffffff);
    expect(alphaSample(255), 0x1464c8);
    expect(alphaSample(128), 0x89b1e3);
  });

  test('grayscale and high contrast match the displayed filter matrices', () {
    int filtered(ScanFilter filter, List<int> pixel) => sampleRgbaColor(
      rgba: Uint8List.fromList(pixel),
      width: 1,
      height: 1,
      x: .5,
      y: .5,
      filter: filter,
    );
    expect(filtered(ScanFilter.grayscale, [100, 150, 200, 255]), 0x8f8f8f);
    expect(filtered(ScanFilter.highContrast, [100, 150, 200, 255]), 0x9b9b9b);
    expect(filtered(ScanFilter.highContrast, [0, 0, 0, 255]), 0x000000);
    expect(filtered(ScanFilter.highContrast, [255, 255, 255, 255]), 0xffffff);
    expect(filtered(ScanFilter.grayscale, [0, 0, 0, 0]), 0xffffff);
  });

  test(
    'rejects invalid dimensions, incomplete pixels, and nonfinite points',
    () {
      for (final dimensions in [(0, 2), (2, 0), (-1, 2), (2, -1)]) {
        expect(
          () => sampleRgbaColor(
            rgba: quadrants,
            width: dimensions.$1,
            height: dimensions.$2,
            x: 0,
            y: 0,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => sampleRgbaColor(
          rgba: Uint8List(15),
          width: 2,
          height: 2,
          x: 0,
          y: 0,
        ),
        throwsArgumentError,
      );
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => sample(value, 0), throwsArgumentError);
        expect(() => sample(0, value), throwsArgumentError);
      }
    },
  );
}
