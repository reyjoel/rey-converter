import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_pdf_converter/src/document_page.dart';
import 'package:mobile_pdf_converter/src/page_annotation.dart';

void main() {
  test('copyWith preserves the source and updates page edits', () {
    final source = XFile('page.jpg');
    final page = DocumentPage(source: source);

    final edited = page.copyWith(
      quarterTurns: 3,
      filter: ScanFilter.highContrast,
    );

    expect(edited.source, same(source));
    expect(edited.id, same(page.id));
    expect(edited.quarterTurns, 3);
    expect(edited.filter, ScanFilter.highContrast);
  });

  test('copyWith normalizes complete rotations', () {
    final page = DocumentPage(source: XFile('page.jpg'));

    expect(page.copyWith(quarterTurns: 5).quarterTurns, 1);
  });

  test('separate pages receive unique identifiers for reordering', () {
    final source = XFile('page.jpg');

    expect(
      DocumentPage(source: source).id,
      isNot(DocumentPage(source: source).id),
    );
  });

  test('page edits preserve annotations without sharing a mutable list', () {
    final text = TextAnnotation(text: 'Initial text');
    final annotations = <PageAnnotation>[text];
    final page = DocumentPage(
      source: XFile('page.jpg'),
      annotations: annotations,
    );
    annotations.clear();

    final edited = page.copyWith(quarterTurns: 1, filter: ScanFilter.grayscale);
    expect(edited.annotations, [text]);
    expect(edited.id, same(page.id));
    expect(() => page.annotations.clear(), throwsUnsupportedError);

    final deleted = edited.copyWith(annotations: []);
    expect(deleted.annotations, isEmpty);
    expect(page.annotations, [text]);
  });
}
