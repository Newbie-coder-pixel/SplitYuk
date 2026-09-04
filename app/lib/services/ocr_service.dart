import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../logic/ocr_layout.dart';

/// Wraps on-device OCR (Google ML Kit, per PRD §13). Mobile-only (Android
/// & iOS) — there is no web/desktop implementation, matching the fact that
/// scanning a physical receipt is inherently a phone-camera feature.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Runs text recognition on the photo at [imagePath]. The image itself
  /// is read directly off disk by the recognizer and never leaves the
  /// device (PRD §9.2/§12).
  ///
  /// Returns the text rebuilt in *visual* reading order via [OcrLayout],
  /// not ML Kit's own `RecognizedText.text`. That property joins blocks in
  /// block order, which on a receipt regularly emits the description
  /// column separately from the amount column and leaves the parser with
  /// prices detached from the items they belong to — see [OcrLayout] for
  /// the full explanation. Falls back to the raw `.text` only if the
  /// geometry-based reconstruction yields nothing at all.
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(inputImage);

    final lines = <OcrTextLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        lines.add(OcrTextLine(
          text: line.text,
          left: box.left,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
        ));
      }
    }

    final ordered = OcrLayout.toReadingOrder(lines);
    return ordered.trim().isEmpty ? result.text : ordered;
  }

  void dispose() {
    _recognizer.close();
  }
}
