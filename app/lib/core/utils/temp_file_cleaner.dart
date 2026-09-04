import 'dart:io';

/// Deletes transient photo files SplitYuk itself created or copied — the
/// receipt photo the camera/gallery plugin wrote to disk before OCR could
/// read it (PRD §17 open item: this temp file must not outlive the
/// session it belongs to).
class TempFileCleaner {
  TempFileCleaner._();

  static Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup — a failed delete must never crash the app or
      // block the user from continuing/closing their session.
    }
  }
}
