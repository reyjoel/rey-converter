import 'package:image_picker/image_picker.dart';

import 'page_annotation.dart';

enum ScanFilter {
  original('Original'),
  grayscale('Grayscale'),
  highContrast('High contrast');

  const ScanFilter(this.label);

  final String label;
}

class DocumentPage {
  DocumentPage({
    required this.source,
    this.quarterTurns = 0,
    this.filter = ScanFilter.original,
    List<PageAnnotation> annotations = const [],
    Object? id,
  }) : id = id ?? Object(),
       annotations = List.unmodifiable(annotations);

  final XFile source;
  final int quarterTurns;
  final ScanFilter filter;
  final Object id;
  final List<PageAnnotation> annotations;

  DocumentPage copyWith({
    int? quarterTurns,
    ScanFilter? filter,
    List<PageAnnotation>? annotations,
  }) {
    return DocumentPage(
      source: source,
      quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
      filter: filter ?? this.filter,
      annotations: annotations ?? this.annotations,
      id: id,
    );
  }
}
