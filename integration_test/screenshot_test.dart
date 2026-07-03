// Renders the real app (real Rust core, real fonts) and writes PNG
// screenshots of the key states in both themes. Used to review the design
// headlessly:
//   flutter test integration_test/screenshot_test.dart -d macos \
//     --dart-define=SHOT_DIR=/path/to/output
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clean_mind/features/scan/scan_providers.dart';
import 'package:clean_mind/features/scan/scan_screen.dart';
import 'package:clean_mind/src/rust/frb_generated.dart';
import 'package:clean_mind/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final _shotKey = GlobalKey();

// Must stay inside the app sandbox; the harness copies files out afterwards.
final _shotDir = '${Directory.systemTemp.path}/cleanmind_shots';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixture;

  setUpAll(() async {
    await RustLib.init();
    fixture = Directory.systemTemp.createTempSync('cleanmind_shots_fixture');
    void writeBytes(String path, int mb) {
      final f = File('${fixture.path}/$path')..createSync(recursive: true);
      f.writeAsBytesSync(Uint8List(mb * 1024 * 1024));
    }

    File('${fixture.path}/webapp/package.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"name":"webapp"}');
    writeBytes('webapp/node_modules/react/react.js', 40);
    writeBytes('webapp/node_modules/lodash/lodash.js', 25);
    writeBytes('webapp/.next/build.bin', 15);
    File('${fixture.path}/cli-tool/Cargo.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]');
    writeBytes('cli-tool/target/debug/cli-tool', 60);
    writeBytes('notes/big-video.mov', 30);
    writeBytes('assets/design.sketch', 22);
    writeBytes('backups/archive.tar', 18);
    Directory(_shotDir).createSync(recursive: true);
    // ignore: avoid_print
    print('SHOT_DIR=$_shotDir');
  });

  tearDownAll(() => fixture.deleteSync(recursive: true));

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    final tag = mode == ThemeMode.dark ? 'dark' : 'light';
    testWidgets('capture $tag', (tester) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _shotKey,
          child: ProviderScope(
            overrides: [
              scanRootProvider.overrideWith(() => _FixedRoot(fixture.path)),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: CleanMindTheme.light,
              darkTheme: CleanMindTheme.dark,
              themeMode: mode,
              home: const ScanScreen(),
            ),
          ),
        ),
      );
      await _pumpFor(tester, 600);
      await _shoot(tester, '$tag-1-landing');

      // Scan and wait for results.
      await tester.tap(find.text('Scan'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScanScreen)),
      );
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (container.read(scanControllerProvider) is! ScanDone &&
          DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _pumpFor(tester, 800);

      // Select the biggest tile so the side panel is populated.
      await tester.tap(find.text('webapp').first, warnIfMissed: false);
      await _pumpFor(tester, 400);
      await _shoot(tester, '$tag-2-results');

      // Insights sheet.
      await tester.tap(find.textContaining('reclaimable'),
          warnIfMissed: false);
      await _pumpFor(tester, 900);
      await _shoot(tester, '$tag-3-insights');
      await tester.tapAt(const Offset(12, 12)); // dismiss barrier
      await _pumpFor(tester, 600);

      // Settings dialog.
      await tester.tap(find.byTooltip('Settings'), warnIfMissed: false);
      await _pumpFor(tester, 700);
      await _shoot(tester, '$tag-4-settings');
      await tester.tapAt(const Offset(12, 12));
      await _pumpFor(tester, 400);
    });
  }
}

class _FixedRoot extends ScanRootController {
  _FixedRoot(this.path);
  final String path;
  @override
  String build() => path;
}

/// Fixed-duration pumps — never pumpAndSettle, so looping hero animations
/// can't hang the harness.
Future<void> _pumpFor(WidgetTester tester, int ms) async {
  const step = 50;
  for (var i = 0; i < ms; i += step) {
    await tester.pump(const Duration(milliseconds: step));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 50));
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  File('$_shotDir/$name.png').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('SHOT $name ${bytes.length ~/ 1024}KB');
}
