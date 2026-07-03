// Not part of the test suite (lives outside test/). Regenerates the macOS
// app icon from the landing-screen hero mark (_OrbitHero / _OrbitPainter in
// lib/features/scan/scan_screen.dart), frozen at t = 0 and upscaled 6.3x:
//
//   flutter test tool/gen_app_icon_test.dart
//   then resize into macos/Runner/Assets.xcassets/AppIcon.appiconset (sips).
//
// Drawing it in Dart keeps the icon reproducible without a design tool, and
// pixel-faithful to what actually renders on the landing screen.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _emerald = Color(0xFF3ADFB4);

void main() {
  test('render app icon to PNG', () async {
    // Load the Material Icons font so Icons.radar_rounded can be painted as
    // real text (TextPainter can't render glyphs from an unloaded font).
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? '/Users/teja/Development/flutter';
    final fontFile = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(fontFile.readAsBytesSync().buffer.asByteData()));
    await loader.load();

    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    // Squircle tile.
    final tile = RRect.fromRectAndRadius(
      const Rect.fromLTWH(100, 100, 824, 824),
      const Radius.circular(186),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(size / 2, 100),
          const Offset(size / 2, 924),
          [const Color(0xFF141A17), const Color(0xFF0A0E0C)],
        ),
    );
    // Soft emerald bloom behind the mark.
    canvas.save();
    canvas.clipRRect(tile);
    canvas.drawCircle(
      center.translate(0, -40),
      420,
      Paint()
        ..shader = ui.Gradient.radial(
          center.translate(0, -40),
          420,
          [_emerald.withValues(alpha: 0.14), _emerald.withValues(alpha: 0)],
        ),
    );
    canvas.restore();
    canvas.drawRRect(
      tile.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    // --- Landing hero (_OrbitHero / _OrbitPainter), frozen at t = 0 and
    // upscaled 6.3x (units -> px) around the tile/canvas center. ---
    const scale = 6.3;

    // Orbit arcs: _OrbitPainter draws 3 stroked arcs, radii
    // (size/2 - 2 - i*9) for a 104x104 box, i.e. 50/41/32 units.
    const alphas = [0.8, 0.35, 0.18];
    const phases = [0.0, 0.28, 0.6]; // turns; speeds don't matter at t = 0
    const sweeps = [130.0, 190.0, 95.0]; // degrees
    for (var i = 0; i < 3; i++) {
      final radius = (50.0 - i * 9) * scale;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        phases[i] * 2 * math.pi,
        sweeps[i] * math.pi / 180,
        false,
        Paint()
          ..color = _emerald.withValues(alpha: alphas[i])
          ..style = PaintingStyle.stroke
          // Not scaled linearly with `scale` (that would be ~12.6px) — 26px
          // keeps the arcs legible at small icon sizes.
          ..strokeWidth = 26
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center disc (56x56 -> radius 28 units) holding the radar glyph.
    canvas.drawCircle(
      center,
      28 * scale,
      Paint()..color = const Color(0xFF163227),
    );

    // Icons.radar_rounded, painted as real text via the loaded Material
    // Icons font (fontSize 34 units -> 34 * 6.3 = 214px).
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.radar_rounded.codePoint),
        style: const TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: 34 * scale,
          color: _emerald,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE ${out.path} (${out.lengthSync()} bytes)');
  });
}
