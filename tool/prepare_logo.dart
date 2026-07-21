import 'dart:io';

import 'package:image/image.dart' as img;

/// Prepares branding assets from the source logo:
///  - logo.png : the full lockup (for splash / in-app)
///  - icon.png : the crowned-bull emblem, padded square (for the app icon)
///
/// Crop box is tuned by eye against the 1254x1254 source; adjust the
/// constants and re-run if the emblem needs recentering.
void main() {
  const source = 'assets/branding/WhatsApp Image 2026-07-21 at 1.17.30 PM.jpeg';
  final src = img.decodeImage(File(source).readAsBytesSync())!;
  stdout.writeln('source ${src.width}x${src.height}');

  // Full logo → 1024 PNG.
  final full = img.copyResize(src, width: 1024, height: 1024);
  File('assets/branding/logo.png').writeAsBytesSync(img.encodePng(full));

  // Emblem crop (crown + bull + rising chart), excluding the GMP wordmark.
  const cropX = 235;
  const cropY = 118;
  const cropW = 905;
  const cropH = 565;
  final crop = img.copyCrop(src, x: cropX, y: cropY, width: cropW, height: cropH);

  // Pad to a square black canvas so nothing is clipped.
  const side = 1024;
  final canvas = img.Image(width: side, height: side);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  final scale = (side * 0.94) / (cropW > cropH ? cropW : cropH);
  final rw = (cropW * scale).round();
  final rh = (cropH * scale).round();
  final resized = img.copyResize(crop, width: rw, height: rh);
  img.compositeImage(canvas, resized,
      dstX: (side - rw) ~/ 2, dstY: (side - rh) ~/ 2);
  File('assets/branding/icon.png').writeAsBytesSync(img.encodePng(canvas));

  // Adaptive-icon foreground: gold emblem on transparent (dark background
  // keyed out), scaled into the ~66% safe zone so masks don't clip it.
  final keyed = crop.convert(numChannels: 4);
  for (final p in keyed) {
    if (p.r + p.g + p.b < 96) p.a = 0;
  }
  final fg = img.Image(width: side, height: side, numChannels: 4);
  final fgScale = (side * 0.62) / (cropW > cropH ? cropW : cropH);
  final fw = (cropW * fgScale).round();
  final fh = (cropH * fgScale).round();
  final fgResized = img.copyResize(keyed, width: fw, height: fh);
  img.compositeImage(fg, fgResized,
      dstX: (side - fw) ~/ 2, dstY: (side - fh) ~/ 2);
  File('assets/branding/icon_foreground.png')
      .writeAsBytesSync(img.encodePng(fg));

  // Native launch-screen logo (centered on black while the app loads).
  final splashDir = Directory('android/app/src/main/res/drawable-nodpi')
    ..createSync(recursive: true);
  final splash = img.copyResize(src, width: 440, height: 440);
  File('${splashDir.path}/splash_logo.png')
      .writeAsBytesSync(img.encodePng(splash));

  stdout.writeln('wrote logo.png, icon.png, icon_foreground.png, splash_logo.png');
}
