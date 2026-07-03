import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../insights/insights_providers.dart';
import '../insights/insights_sheet.dart';
import '../scan/scan_providers.dart';
import '../settings/settings_dialog.dart';
import 'side_panel.dart';
import 'tree_providers.dart';
import 'treemap/treemap_view.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reclaimable = ref.watch(reclaimableTotalProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(child: _Breadcrumbs()),
                const SizedBox(width: 12),
                if (reclaimable > 0)
                  ActionChip(
                    avatar: Icon(Icons.cleaning_services_rounded,
                        size: 18, color: theme.tiers.safe),
                    label: Text('${formatBytes(reclaimable)} reclaimable'),
                    onPressed: () => showInsightsSheet(context),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.insights_rounded, size: 18),
                    label: const Text('Insights'),
                    onPressed: () => showInsightsSheet(context),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'New scan',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () =>
                      ref.read(scanControllerProvider.notifier).reset(),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => showSettingsDialog(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: TreemapView()),
                  const SizedBox(width: 12),
                  SizedBox(width: 300, child: SidePanel()),
                ],
              ),
            ),
          ),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trail = ref.watch(focusTrailProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < trail.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: theme.colorScheme.outline),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: i == trail.length - 1
                  ? null
                  : () => ref.read(focusTrailProvider.notifier).popTo(i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  trail[i].name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight:
                        i == trail.length - 1 ? FontWeight.w700 : null,
                    color: i == trail.length - 1
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends ConsumerWidget {
  const _Legend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insights = ref.watch(insightsProvider);
    final hasReview = insights.any((i) => i.tier == FsTier.review);

    Widget chip(Color color, IconData? icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon != null
                ? Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant)
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
            const SizedBox(width: 5),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        children: [
          chip(theme.tiers.safe, null, 'Safe to reclaim'),
          if (hasReview) chip(theme.tiers.review, null, 'Review first'),
          chip(theme.tiers.protected, Icons.lock_outline_rounded, 'Protected'),
          chip(theme.colorScheme.surfaceContainerHighest, null, 'Folder'),
        ],
      ),
    );
  }
}
