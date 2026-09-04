import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Renders an on-screen [RepaintBoundary] to a PNG file — used for FR-3.3's
/// summary image when a manual-entry bill has no original receipt photo.
/// The same widget that's shown to the user as the message preview is what
/// gets captured, so what they approve is exactly what gets sent.
class ImageRenderService {
  Future<String> captureToFile(GlobalKey boundaryKey, String fileName) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('captureToFile: boundaryKey is not attached to a RepaintBoundary.');
    }
    final image = await renderObject.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('captureToFile: failed to encode PNG.');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }
}
