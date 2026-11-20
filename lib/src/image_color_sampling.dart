import 'dart:typed_data';

import 'document_page.dart';

/// Samples straight RGBA pixels at a point on the final, rotated photo.
///
/// [x] and [y] are normalized displayed coordinates. Image codecs should already
/// have applied EXIF orientation; [quarterTurns] is the editor's extra rotation.
/// Transparent pixels are composited onto white before the preview filter.
int sampleRgbaColor({
  required Uint8List rgba,
  required int width,
  required int height,
  required double x,
  required double y,
  int quarterTurns = 0,
  ScanFilter filter = ScanFilter.original,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  if (rgba.length < width * height * 4) {
    throw ArgumentError.value(
      rgba.length,
      'rgba',
      'Image pixel data is incomplete.',
    );
  }
  if (!x.isFinite || !y.isFinite) {
    throw ArgumentError('Sample coordinates must be finite.');
  }

  final displayedX = x.clamp(0.0, 1.0);
  final displayedY = y.clamp(0.0, 1.0);
  final (sourceX, sourceY) = switch (quarterTurns % 4) {
    0 => (displayedX, displayedY),
    1 => (displayedY, 1 - displayedX),
    2 => (1 - displayedX, 1 - displayedY),
    _ => (1 - displayedY, displayedX),
  };
  final pixelX = (sourceX * width).floor().clamp(0, width - 1);
  final pixelY = (sourceY * height).floor().clamp(0, height - 1);
  final offset = (pixelY * width + pixelX) * 4;
  return photoPixelColor(
    red: rgba[offset].toDouble(),
    green: rgba[offset + 1].toDouble(),
    blue: rgba[offset + 2].toDouble(),
    alpha: rgba[offset + 3] / 255,
    filter: filter,
  );
}

/// Shared preview/export color transform without temporary pixel allocations.
///
/// Input color channels are straight (unpremultiplied) values from 0 to 255,
/// and [alpha] is from 0 to 1. Transparency is composited onto white before
/// applying the same filter matrix used by the photo preview.
int photoPixelColor({
  required double red,
  required double green,
  required double blue,
  required double alpha,
  ScanFilter filter = ScanFilter.original,
}) {
  final compositedRed = red * alpha + 255 * (1 - alpha);
  final compositedGreen = green * alpha + 255 * (1 - alpha);
  final compositedBlue = blue * alpha + 255 * (1 - alpha);

  final int outputRed;
  final int outputGreen;
  final int outputBlue;
  switch (filter) {
    case ScanFilter.original:
      outputRed = _channel(compositedRed);
      outputGreen = _channel(compositedGreen);
      outputBlue = _channel(compositedBlue);
    case ScanFilter.grayscale:
      final gray = _channel(
        .2126 * compositedRed +
            .7152 * compositedGreen +
            .0722 * compositedBlue,
      );
      outputRed = outputGreen = outputBlue = gray;
    case ScanFilter.highContrast:
      final gray = _channel(
        .3827 * compositedRed +
            1.2874 * compositedGreen +
            .1299 * compositedBlue -
            102,
      );
      outputRed = outputGreen = outputBlue = gray;
  }
  return (outputRed << 16) | (outputGreen << 8) | outputBlue;
}

int _channel(double value) => value.round().clamp(0, 255);
