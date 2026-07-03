// Not part of the test suite (lives outside test/). Regenerates the macOS
// app icon from the landing-screen radar motif:
//
//   flutter test tool/gen_app_icon_test.dart
//   then resize into macos/Runner/Assets.xcassets/AppIcon.appiconset (sips).
//
// Drawing it in Dart keeps the icon reproducible without a design tool.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _emerald = Color(0xFF3ADFB4);

void main() {
  test('render app icon to PNG', () async {
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

    // Orbit arcs, frozen at the landing hero's pose.
    const alphas = [0.85, 0.4, 0.2];
    const phases = [0.62, 0.9, 0.22]; // turns
    const sweeps = [130.0, 190.0, 95.0]; // degrees
    for (var i = 0; i < 3; i++) {
      final radius = 318.0 - i * 40;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        phases[i] * 2 * math.pi,
        sweeps[i] * math.pi / 180,
        false,
        Paint()
          ..color = _emerald.withValues(alpha: alphas[i])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center disc with the radar sweep.
    canvas.drawCircle(center, 176, Paint()..color = const Color(0xFF163227));
    canvas.drawCircle(
      center,
      130,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = _emerald.withValues(alpha: 0.9),
    );
    for (final f in [0.66, 0.33]) {
      canvas.drawCircle(
        center,
        130 * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _emerald.withValues(alpha: 0.28),
      );
    }
    const lead = -math.pi / 4; // needle to the upper right
    const sweep = math.pi * 0.6;
    final rect = Rect.fromCircle(center: center, radius: 126);
    canvas.drawArc(
      rect,
      lead - sweep,
      sweep,
      true,
      Paint()
        ..shader = ui.Gradient.sweep(
          center,
          [
            _emerald.withValues(alpha: 0),
            _emerald.withValues(alpha: 0.18),
            _emerald.withValues(alpha: 0.5),
          ],
          [0.0, 0.6 * sweep / (2 * math.pi), sweep / (2 * math.pi)],
          TileMode.clamp,
          lead - sweep,
          lead,
        ),
    );
    final tipDir = Offset(math.cos(lead), math.sin(lead));
    final tip = center + tipDir * 122;
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = _emerald
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      tip,
      26,
      Paint()
        ..color = _emerald.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(tip, 15, Paint()..color = _emerald);
    canvas.drawCircle(center, 13, Paint()..color = _emerald);

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
