import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';

void main() {
  test('editing text and moving a signature preserves annotation identity', () {
    final text = TextAnnotation(text: 'Old text');
    final edited = text.copyWith(text: 'Replacement', x: .3, fontSize: .05);
    expect(edited.id, text.id);
    expect(edited.text, 'Replacement');
    expect(edited.x, .3);
    expect(edited.fontSize, .05);
    expect(text.text, 'Old text');

    final signature = SignatureAnnotation(
      strokes: [
        [const AnnotationPoint(0, 0), const AnnotationPoint(1, 1)],
      ],
    );
    final moved = signature.copyWith(x: .2, width: .4);
    expect(moved.id, signature.id);
    expect(moved.strokes.single.length, 2);
    expect(moved.width, .4);
    expect(signature.id, isNot(text.id));
  });

  test('signature strokes cannot change after an editor snapshot is made', () {
    final stroke = [const AnnotationPoint(.1, .2)];
    final strokes = [stroke];
    final signature = SignatureAnnotation(strokes: strokes);
    stroke.clear();
    strokes.clear();

    expect(signature.strokes.single.single.x, .1);
    expect(() => signature.strokes.clear(), throwsUnsupportedError);
    expect(() => signature.strokes.single.clear(), throwsUnsupportedError);
  });

  test('text styles and explicit point size survive moving and editing', () {
    final text = TextAnnotation(
      text: 'Styled',
      fontSizePt: 18.5,
      color: 0x1648a0,
      bold: true,
      italic: true,
      underline: true,
      strikethrough: true,
    );
    final moved = text.copyWith(x: .35, text: 'Edited');
    expect(moved.id, text.id);
    expect(moved.color, 0x1648a0);
    expect(moved.bold, isTrue);
    expect(moved.italic, isTrue);
    expect(moved.underline, isTrue);
    expect(moved.strikethrough, isTrue);
    expect(moved.fontSizeForImageWidth(200), 18.5);
    expect(moved.fontSizeForImageWidth(500), 18.5);
    final plain = moved.copyWith(
      fontSizePt: 12,
      color: 0,
      bold: false,
      italic: false,
      underline: false,
      strikethrough: false,
    );
    expect(plain.fontSizeForImageWidth(500), 12);
    expect(
      plain.bold || plain.italic || plain.underline || plain.strikethrough,
      isFalse,
    );
    expect(
      TextAnnotation(text: 'Older', fontSize: .05).fontSizeForImageWidth(400),
      20,
    );
  });

  test('moving and resizing signatures and covers preserves chosen colors', () {
    final signature = SignatureAnnotation(
      color: 0x0055ff,
      strokes: [
        [const AnnotationPoint(.1, .2)],
      ],
    );
    expect(signature.copyWith(x: .2, width: .6).color, 0x0055ff);
    expect(signature.copyWith(color: 0xaa1100).color, 0xaa1100);
    final cover = CoverAnnotation(color: 0xe6d6b5);
    expect(cover.copyWith(y: .6, height: .1).color, 0xe6d6b5);
    expect(cover.copyWith(color: 0).color, 0);
    expect(CoverAnnotation().color, 0xffffff);
  });
}
