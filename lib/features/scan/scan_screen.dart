import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../util/format.dart';
import '../results/results_screen.dart';
import 'scan_providers.dart';

/// Root of the app: landing → scanning → results, driven by [ScanState].
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (scan) {
        ScanIdle() => const _LandingView(key: ValueKey('landing')),
        ScanRunning(:final progress) =>
          _ScanningView(key: const ValueKey('scanning'), progress: progress),
        ScanDone() => const ResultsScreen(key: ValueKey('results')),
        ScanFailed(:final message) =>
          _FailedView(key: const ValueKey('failed'), message: message),
      },
    );
  }
}

class _LandingView extends ConsumerWidget {
  const _LandingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final root = ref.watch(scanRootProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.tertiaryContainer,
                      ],
                    ),
                  ),
                  child: Icon(Icons.data_usage_rounded,
                      size: 44, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Clean Mind',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'See what fills your disk — and what is safe to reclaim.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(root,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked =
                            await getDirectoryPath(initialDirectory: root);
                        if (picked != null) {
                          ref.read(scanRootProvider.notifier).set(picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(scanControllerProvider.notifier).start(),
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('Scan'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Fresh scan every time. Nothing leaves your machine unless '
                  'you turn on AI analysis — and even then, only folder '
                  'names and sizes.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanningView extends ConsumerWidget {
  const _ScanningView({super.key, required this.progress});

  final ScanProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes = progress?.bytes ?? 0;
    final files = progress?.files ?? 0;
    final dirs = progress?.dirs ?? 0;
    final current = progress?.currentPath ?? '';

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 28),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: bytes.toDouble()),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, value, _) => Text(
                    formatBytes(value.round()),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text('found so far',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Counter(label: 'files', value: files),
                    const SizedBox(width: 32),
                    _Counter(label: 'folders', value: dirs),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 20,
                  child: Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(scanControllerProvider.notifier).cancel(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(formatCount(value),
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _FailedView extends ConsumerWidget {
  const _FailedView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () =>
                  ref.read(scanControllerProvider.notifier).reset(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
