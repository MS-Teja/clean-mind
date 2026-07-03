// End-to-end drive of the real Clean Mind GUI against a fixture directory.
// Pumps the actual app, taps the real Scan button, runs the real Rust scan +
// rules engine + insights over a temp dev tree, and inspects rendered widgets.
import 'dart:io';

import 'package:clean_mind/features/insights/insights_providers.dart';
import 'package:clean_mind/features/insights/insights_sheet.dart';
import 'package:clean_mind/features/results/results_screen.dart';
import 'package:clean_mind/features/results/treemap/treemap_view.dart';
import 'package:clean_mind/features/scan/scan_providers.dart';
import 'package:clean_mind/main.dart';
import 'package:clean_mind/src/rust/api/insights.dart';
import 'package:clean_mind/src/rust/api/scan.dart';
import 'package:clean_mind/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixture;

  setUpAll(() async {
    await RustLib.init();
    // Build a dev tree with known bloat: JS project (stale node_modules +
    // .next), Rust project (target/), and a media dir with NO project markers.
    fixture = Directory.systemTemp.createTempSync('cleanmind_fixture');
    void writeBytes(String path, int mb) {
      final f = File('${fixture.path}/$path')
        ..createSync(recursive: true);
      f.writeAsBytesSync(List.filled(mb * 1024 * 1024, 0));
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
  });

  tearDownAll(() => fixture.deleteSync(recursive: true));

  testWidgets('scan → treemap → insights end to end', (tester) async {
    // Drive the app with the fixture as scan root (the value a user would set
    // via the folder picker). Everything else is the real app.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanRootProvider.overrideWith(() => _FixedRoot(fixture.path)),
        ],
        child: const CleanMindApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Landing screen renders.
    expect(find.text('Clean Mind'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);

    // Tap the real Scan button (its label) and wait for the scan to complete.
    await tester.tap(find.text('Scan'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CleanMindApp)),
    );
    await _waitFor(tester, () =>
        container.read(scanControllerProvider) is ScanDone);

    // Results screen + treemap rendered with real tiles.
    expect(find.byType(ResultsScreen), findsOneWidget);
    expect(find.byType(TreemapView), findsOneWidget);
    // webapp is the largest dir (80MB) — its tile label should be visible.
    expect(find.text('webapp'), findsWidgets);

    // Insights computed by the real rules engine.
    final insights = container.read(insightsProvider);
    final ids = {for (final i in insights) i.ruleId};
    expect(ids, contains('node-modules'),
        reason: 'stale node_modules next to package.json must be flagged');
    expect(ids, contains('cargo-target'),
        reason: 'target/ next to Cargo.toml must be flagged');
    expect(ids, contains('next-build'),
        reason: '.next next to package.json must be flagged');

    // node_modules is Tier-1 safe; nothing from the media dir is flagged.
    final nodeModules =
        insights.firstWhere((i) => i.ruleId == 'node-modules');
    expect(nodeModules.tier, FsTier.safe);
    expect(insights.any((i) => i.path.contains('notes')), isFalse,
        reason: 'a media dir with no project markers must not be flagged');

    // Reclaimable total = node_modules(65) + .next(15) + target(60) = 140MB.
    final reclaimable = container.read(reclaimableTotalProvider);
    expect(reclaimable, greaterThan(130 * 1000 * 1000));
    expect(reclaimable, lessThan(150 * 1024 * 1024));

    // Open the insights sheet through the real UI and see the tiers.
    await tester.tap(find.textContaining('reclaimable'));
    await tester.pumpAndSettle();
    expect(find.byType(InsightsSheet), findsOneWidget);
    expect(find.text('Node.js dependencies'), findsWidgets);
    expect(find.textContaining('safe to reclaim'), findsWidgets);

    // Report the observed numbers into the test log for the evidence capture.
    // ignore: avoid_print
    print('OBSERVED insights=${insights.length} '
        'rules=${ids.toList()} '
        'reclaimableBytes=$reclaimable '
        'nodeModulesTier=${nodeModules.tier}');
  });

  // Probe: drill into a folder via the treemap and confirm navigation works
  // (breadcrumb + get_children, including nested rule matching under focus).
  testWidgets('probe: treemap drill-down navigates into a folder',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanRootProvider.overrideWith(() => _FixedRoot(fixture.path)),
        ],
        child: const CleanMindApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CleanMindApp)),
    );
    await _waitFor(tester, () =>
        container.read(scanControllerProvider) is ScanDone);
    await tester.pumpAndSettle();

    // Double-tap the "webapp" tile to drill in.
    await tester.tap(find.text('webapp').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('webapp').first);
    await tester.pumpAndSettle();

    // node_modules (the 65MB child of webapp) now shows inside the map.
    expect(find.text('node_modules'), findsWidgets,
        reason: 'drilling into webapp should reveal its node_modules tile');
    // ignore: avoid_print
    print('OBSERVED drilled into webapp; child tiles rendered');
  });
}

/// Overrides the scan root the way a folder-picker selection would.
class _FixedRoot extends ScanRootController {
  _FixedRoot(this.path);
  final String path;
  @override
  String build() => path;
}

Future<void> _waitFor(WidgetTester tester, bool Function() cond,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!cond()) {
    throw TimeoutException('condition not met within $timeout');
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.message);
  final String message;
  @override
  String toString() => 'TimeoutException: $message';
}
