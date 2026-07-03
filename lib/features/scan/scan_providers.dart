import 'dart:async';

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

sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanRunning extends ScanState {
  const ScanRunning(this.progress);
  final ScanProgress? progress;
}

class ScanDone extends ScanState {
  const ScanDone({required this.rootId, required this.progress});
  final int rootId;
  final ScanProgress progress;
}

class ScanFailed extends ScanState {
  const ScanFailed(this.message);
  final String message;
}

class ScanController extends Notifier<ScanState> {
  StreamSubscription<ScanProgress>? _sub;

  @override
  ScanState build() {
    ref.onDispose(() => _sub?.cancel());
    return const ScanIdle();
  }

  Future<void> start() async {
    await _sub?.cancel();
    state = const ScanRunning(null);
    final root = ref.read(scanRootProvider);
    _sub = startScan(path: root).listen(
      (progress) {
        switch (progress.stage) {
          case ScanStage.scanning:
            state = ScanRunning(progress);
          case ScanStage.done:
            state = ScanDone(rootId: progress.rootId, progress: progress);
          case ScanStage.cancelled:
            state = const ScanIdle();
          case ScanStage.failed:
            state = const ScanFailed('The scan could not be completed.');
        }
      },
      onError: (Object e) => state = ScanFailed(e.toString()),
    );
  }

  Future<void> cancel() => cancelScan();

  /// Back to the landing screen; the old tree stays in Rust memory until the
  /// next scan replaces it, but the UI treats it as gone.
  void reset() => state = const ScanIdle();
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanState>(ScanController.new);
