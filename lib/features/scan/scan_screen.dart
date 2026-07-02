import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../util/format.dart';
import 'scan_providers.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(scanRootProvider);
    final scan = ref.watch(scanControllerProvider);
    final theme = Theme.of(context);

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
                Icon(Icons.data_usage_rounded,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Clean Mind',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'See what fills your disk — and what is safe to reclaim.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                _RootPicker(root: root),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: scan.isLoading
                      ? null
                      : () =>
                          ref.read(scanControllerProvider.notifier).scan(),
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(scan.isLoading ? 'Scanning…' : 'Scan'),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: switch (scan) {
                    AsyncData(:final value) when value != null =>
                      _SummaryCard(summary: value),
                    AsyncLoading() => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    AsyncError(:final error) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Scan failed: $error',
                              style: TextStyle(
                                  color: theme.colorScheme.error)),
                        ),
                      ),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RootPicker extends ConsumerWidget {
  const _RootPicker({required this.root});

  final String root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_rounded),
        title: Text(root,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium),
        trailing: TextButton(
          onPressed: () async {
            final picked = await getDirectoryPath(initialDirectory: root);
            if (picked != null) {
              ref.read(scanRootProvider.notifier).set(picked);
            }
          },
          child: const Text('Change'),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ScanSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              formatBytes(summary.totalBytes),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            Text('allocated on disk',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(label: 'Files', value: formatCount(summary.files)),
                _Stat(label: 'Folders', value: formatCount(summary.dirs)),
                if (summary.errors > BigInt.zero)
                  _Stat(
                      label: 'Unreadable',
                      value: formatCount(summary.errors)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
