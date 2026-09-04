import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Wraps on-device OCR (Google ML Kit, per PRD §13). Mobile-only (Android
/// & iOS) — there is no web/desktop implementation, matching the fact that
/// scanning a physical receipt is inherently a phone-camera feature.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Runs text recognition on the photo at [imagePath]. The image itself
  /// is read directly off disk by the recognizer and never leaves the
  /// device (PRD §9.2/§12).
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() {
    _recognizer.close();
  }
}
