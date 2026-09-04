import 'package:http_parser/http_parser.dart';

/// The MIME type to declare when uploading a photo.
///
/// This exists because getting it wrong fails silently and confusingly:
/// `http.MultipartFile.fromPath` defaults to `application/octet-stream`
/// when no content type is given, and a receipt uploaded that way reached
/// Gemini as an opaque binary blob — the model replied that it had been
/// handed "corrupted/raw binary file text instead of a valid receipt
/// image" rather than reading the receipt. Nothing about the failure
/// pointed at the upload, so state the type explicitly everywhere.
class ImageMimeType {
  ImageMimeType._();

  /// The content type for the file at [path], guessed from its extension
  /// and defaulting to JPEG — what both the camera and `image_picker`
  /// produce on Android and iOS.
  static MediaType forPath(String path) {
    final dot = path.lastIndexOf('.');
    final extension = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();

    switch (extension) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
      case 'heif':
        return MediaType('image', 'heic');
      case 'gif':
        return MediaType('image', 'gif');
      default:
        return MediaType('image', 'jpeg');
    }
  }
}
