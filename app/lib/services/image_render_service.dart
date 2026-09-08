import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders an on-screen [RepaintBoundary] to PNG bytes — used for FR-3.3's
/// summary image when a manual-entry bill has no original receipt photo.
/// The same widget that's shown to the user as the message preview is what
/// gets captured, so what they approve is exactly what gets sent.
///
/// Returns bytes rather than writing a temp file. That is closer to PRD §3
/// (the image never touches storage at all, so there is nothing to forget
/// to delete), and it is the only form that works on every platform —
/// `dart:io` does not exist on the web build.
class ImageRenderService {
  Future<Uint8List> capture(GlobalKey boundaryKey) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('capture: boundaryKey is not attached to a RepaintBoundary.');
    }
    final image = await renderObject.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('capture: failed to encode PNG.');
    }
    return byteData.buffer.asUint8List();
  }
}
