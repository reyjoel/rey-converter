import 'package:image_picker/image_picker.dart';

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
    Object? id,
  }) : id = id ?? Object();

  final XFile source;
  final int quarterTurns;
  final ScanFilter filter;
  final Object id;

  DocumentPage copyWith({int? quarterTurns, ScanFilter? filter}) {
    return DocumentPage(
      source: source,
      quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
      filter: filter ?? this.filter,
      id: id,
    );
  }
}
