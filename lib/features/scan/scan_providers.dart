import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';

/// Directory the next scan will walk. Defaults to the user's home directory;
/// never persisted — every launch starts fresh.
class ScanRootController extends Notifier<String> {
  @override
  String build() => defaultScanRoot();

  void set(String path) => state = path;
}

final scanRootProvider =
    NotifierProvider<ScanRootController, String>(ScanRootController.new);

/// Runs scans and exposes the latest result. `null` means no scan yet.
class ScanController extends AsyncNotifier<ScanSummary?> {
  @override
  Future<ScanSummary?> build() async => null;

  Future<void> scan() async {
    final root = ref.read(scanRootProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => scanSummary(path: root));
  }
}

final scanControllerProvider =
    AsyncNotifierProvider<ScanController, ScanSummary?>(ScanController.new);
