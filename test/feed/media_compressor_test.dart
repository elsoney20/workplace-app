import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:workplace_app/features/feed/data/media_compressor.dart';

void main() {
  test('big photos are resized to 1920 px and saved as JPEG', () {
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(200, 50, 50));
    for (var i = 0; i < 4000; i += 7) {
      img.drawLine(
        big,
        x1: i,
        y1: 0,
        x2: 4000 - i,
        y2: 2999,
        color: img.ColorRgb8(i % 255, 120, 30),
      );
    }
    final original = Uint8List.fromList(img.encodePng(big));
    final result = MediaCompressor.compressImageSync(original, 'image/png')!;
    expect(result.width, 1920);
    expect(result.height, 1440);
    expect(result.mimeType, 'image/jpeg');
    expect(result.bytes.length, lessThan(original.length));
  });

  test('small images are not made bigger', () {
    final small = img.Image(width: 10, height: 10);
    final original = Uint8List.fromList(img.encodeJpg(small, quality: 30));
    final result = MediaCompressor.compressImageSync(original, 'image/jpeg')!;
    expect(result.bytes.length, lessThanOrEqualTo(original.length));
  });

  test('files that are not images are rejected', () {
    expect(
      MediaCompressor.compressImageSync(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      ),
      isNull,
    );
  });
}
