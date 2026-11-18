import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Result of preparing an image for upload.
class CompressedImage {
  const CompressedImage(this.bytes, this.width, this.height, this.mimeType);
  final Uint8List bytes;
  final int width;
  final int height;
  final String mimeType;
}

/// Shrinks photos before upload so they load fast and use little storage.
///
/// * Longest side at most [defaultMaxSide] pixels (1920 = sharp on any screen).
/// * Saved as JPEG quality 80 (a 6 MB phone photo usually becomes ~300 KB).
/// * GIFs are kept as they are, so animations still play.
/// * If the result would be bigger than the original, the original is kept.
abstract final class MediaCompressor {
  static const int defaultMaxSide = 1920;
  static const int jpegQuality = 80;

  static Future<CompressedImage?> compressImage(
    Uint8List original,
    String mimeType, {
    int maxSide = defaultMaxSide,
  }) {
    return Isolate.run(
      () => compressImageSync(original, mimeType, maxSide: maxSide),
    );
  }

  /// Same as [compressImage] but on the current thread (used by tests).
  static CompressedImage? compressImageSync(
    Uint8List original,
    String mimeType, {
    int maxSide = defaultMaxSide,
  }) {
    final decoded = img.decodeImage(original);
    if (decoded == null) return null;
    if (mimeType == 'image/gif') {
      return CompressedImage(original, decoded.width, decoded.height, mimeType);
    }
    // Phone photos are often stored sideways with a rotation flag.
    var image = img.bakeOrientation(decoded);
    if (image.width > maxSide || image.height > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxSide,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxSide,
              interpolation: img.Interpolation.average,
            );
    }
    final hasAlpha = image.hasAlpha && mimeType == 'image/png';
    final bytes = hasAlpha
        ? Uint8List.fromList(img.encodePng(image, level: 6))
        : Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));
    if (bytes.length >= original.length && image.width == decoded.width) {
      return CompressedImage(original, decoded.width, decoded.height, mimeType);
    }
    return CompressedImage(
      bytes,
      image.width,
      image.height,
      hasAlpha ? 'image/png' : 'image/jpeg',
    );
  }
}
