import 'dart:math' as math;

// A4 PDF dimensions and the page margin used by the exporter, in points.
const pageWidthPoints = 595.275590551181;
const pageHeightPoints = 841.889763779528;
const pageMarginPoints = 24.0;

double imageWidthPointsForAspectRatio(double aspectRatio) => math.min(
  pageWidthPoints - 2 * pageMarginPoints,
  (pageHeightPoints - 2 * pageMarginPoints) * aspectRatio,
);
