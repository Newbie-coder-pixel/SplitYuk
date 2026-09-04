import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/core/utils/image_mime_type.dart';

void main() {
  group('ImageMimeType.forPath', () {
    test('never returns a non-image type', () {
      // The whole point: an upload declared as anything but an image is
      // what made Gemini reject a real receipt as raw binary.
      for (final path in [
        '/tmp/photo.jpg',
        '/tmp/photo.JPG',
        '/tmp/photo.jpeg',
        '/tmp/photo.png',
        '/tmp/photo.HEIC',
        '/tmp/photo.webp',
        '/tmp/image_picker_1234',
        '/tmp/no.extension.at.all',
        '',
      ]) {
        expect(ImageMimeType.forPath(path).type, 'image', reason: path);
      }
    });

    test('maps the formats a phone camera and gallery actually produce', () {
      expect(ImageMimeType.forPath('/tmp/a.jpg').mimeType, 'image/jpeg');
      expect(ImageMimeType.forPath('/tmp/a.png').mimeType, 'image/png');
      expect(ImageMimeType.forPath('/tmp/a.heic').mimeType, 'image/heic');
      expect(ImageMimeType.forPath('/tmp/a.heif').mimeType, 'image/heic');
      expect(ImageMimeType.forPath('/tmp/a.webp').mimeType, 'image/webp');
    });

    test('is case-insensitive about the extension', () {
      expect(ImageMimeType.forPath('/tmp/IMG_0001.HEIC').mimeType, 'image/heic');
      expect(ImageMimeType.forPath('/tmp/IMG_0001.PNG').mimeType, 'image/png');
    });

    test('falls back to JPEG for an extensionless temp file', () {
      // image_picker hands back paths like this on some devices.
      expect(ImageMimeType.forPath('/tmp/image_picker_A1B2C3').mimeType, 'image/jpeg');
    });
  });
}
