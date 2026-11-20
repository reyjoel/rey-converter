/// Coordinates are fractions of the final, rotated page image, from its top left.
sealed class PageAnnotation {
  PageAnnotation({
    String? id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) : id = id ?? 'annotation-${_nextId++}';

  static var _nextId = 0;

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  PageAnnotation copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  });
}

class TextAnnotation extends PageAnnotation {
  TextAnnotation({
    required this.text,
    this.fontSize = .04,
    this.fontSizePt,
    this.color = 0x000000,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    super.id,
    super.x = .1,
    super.y = .1,
    super.width = .6,
    super.height = .12,
  });

  final String text;

  /// Font size as a fraction of the page image's displayed width.
  final double fontSize;

  /// An explicit PDF point size. Older annotations keep their relative sizing.
  final double? fontSizePt;
  final int color;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  double fontSizeForImageWidth(double imageWidthPoints) =>
      fontSizePt ?? fontSize * imageWidthPoints;

  @override
  TextAnnotation copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    double? fontSize,
    double? fontSizePt,
    int? color,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
  }) => TextAnnotation(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
    fontSizePt: fontSizePt ?? this.fontSizePt,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strikethrough: strikethrough ?? this.strikethrough,
  );
}

class AnnotationPoint {
  const AnnotationPoint(this.x, this.y);

  final double x;
  final double y;
}

class SignatureAnnotation extends PageAnnotation {
  SignatureAnnotation({
    required List<List<AnnotationPoint>> strokes,
    this.color = 0x000000,
    super.id,
    super.x = .1,
    super.y = .65,
    super.width = .5,
    super.height = .18,
  }) : strokes = List.unmodifiable(
         strokes.map(List<AnnotationPoint>.unmodifiable),
       );

  /// Each stroke contains points relative to this signature's own box.
  final List<List<AnnotationPoint>> strokes;
  final int color;

  @override
  SignatureAnnotation copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    List<List<AnnotationPoint>>? strokes,
    int? color,
  }) => SignatureAnnotation(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    strokes: strokes ?? this.strokes,
    color: color ?? this.color,
  );
}

/// An opaque color box baked into the exported image before text/signatures.
class CoverAnnotation extends PageAnnotation {
  CoverAnnotation({
    this.color = 0xffffff,
    super.id,
    super.x = .1,
    super.y = .3,
    super.width = .5,
    super.height = .08,
  });

  final int color;

  @override
  CoverAnnotation copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? color,
  }) => CoverAnnotation(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    color: color ?? this.color,
  );
}
