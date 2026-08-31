import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pdf_converter/src/ordering.dart';

void main() {
  test('moving an image down preserves the requested visual order', () {
    expect(moveItem(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
  });

  test('moving an image up preserves the requested visual order', () {
    expect(moveItem(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
  });

  test('moving an image to the same slot does not change the order', () {
    expect(moveItem(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
  });
}
