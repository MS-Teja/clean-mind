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
    final reclaimable = ref.watch(reclaimableTotalProvider);
    final scan = ref.watch(scanControllerProvider);
    final partial = scan is ScanDone && scan.partial;
    final errors = scan is ScanDone ? scan.progress.errors : 0;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Expanded(child: _Breadcrumbs()),
                const SizedBox(width: 12),
                const _FocusReadout(),
                const SizedBox(width: 12),
                _ReclaimablePill(bytes: reclaimable),
                const SizedBox(width: 6),
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
          if (partial || errors > 0)
            _ScanCaveats(partial: partial, errors: errors),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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

/// Non-blocking caveats strip under the header: a visible chip when the scan
/// was cancelled early, and a muted note counting unreadable items.
class _ScanCaveats extends StatelessWidget {
  const _ScanCaveats({required this.partial, required this.errors});

  final bool partial;
  final int errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final review = theme.tiers.review;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          if (partial)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: ShapeDecoration(
                color: review.withValues(alpha: 0.13),
                shape: StadiumBorder(
                  side: BorderSide(color: review.withValues(alpha: 0.45)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timelapse_rounded, size: 15, color: review),
                  const SizedBox(width: 7),
                  Text(
                    'Partial scan — stopped early, sizes are incomplete.',
                    style: theme.textTheme.labelMedium?.copyWith(color: review),
                  ),
                ],
              ),
            ),
          if (partial && errors > 0) const SizedBox(width: 14),
          if (errors > 0)
            Flexible(
              child: Tooltip(
                message: 'Usually permission-protected folders. On macOS, '
                    'granting Full Disk Access reduces this.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$errors item${errors == 1 ? '' : 's'} '
                        "couldn't be read",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reclaimable total as a tappable emerald pill; falls back to a quieter
/// "Insights" chip when there is nothing to reclaim. Always opens the sheet.
class _ReclaimablePill extends StatelessWidget {
  const _ReclaimablePill({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (bytes <= 0) {
      return Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showInsightsSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insights_rounded,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text('Insights',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    final safe = theme.tiers.safe;
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showInsightsSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: ShapeDecoration(
            color: safe.withValues(alpha: 0.13),
            shape: StadiumBorder(
              side: BorderSide(color: safe.withValues(alpha: 0.45)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cleaning_services_rounded, size: 15, color: safe),
              const SizedBox(width: 7),
              Text(formatBytes(bytes),
                  style: mono(13, weight: FontWeight.w600, color: safe)),
              const SizedBox(width: 5),
              Text('reclaimable',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact size/counts readout for the current focus, right of the crumbs.
class _FocusReadout extends ConsumerWidget {
  const _FocusReadout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final focus = ref.watch(focusNodeProvider);
    if (focus == null || focus.kind != FsKind.dir) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatBytes(focus.size),
            style: mono(13,
                weight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        const SizedBox(width: 8),
        Text(
          '${formatCount(focus.fileCount)} files · '
          '${formatCount(focus.dirCount)} folders',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trail = ref.watch(focusTrailProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < trail.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: scheme.outline),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                hoverColor: scheme.onSurface.withValues(alpha: 0.06),
                onTap: i == trail.length - 1
                    ? null
                    : () => ref.read(focusTrailProvider.notifier).popTo(i),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0) ...[
                        Icon(Icons.home_rounded,
                            size: 14,
                            color: i == trail.length - 1
                                ? scheme.onSurface
                                : scheme.primary),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        trail[i].name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              i == trail.length - 1 ? FontWeight.w700 : null,
                          color: i == trail.length - 1
                              ? scheme.onSurface
                              : scheme.primary,
                        ),
                      ),
                    ],
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
    final scheme = theme.colorScheme;
    final insights = ref.watch(insightsProvider);
    final hasReview = insights.any((i) => i.tier == FsTier.review);

    Widget chip(Color? color, IconData? icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon != null
                ? Icon(icon, size: 12, color: scheme.onSurfaceVariant)
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
            const SizedBox(width: 6),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 6,
        children: [
          chip(theme.map.folderAt(0.35), null, 'Folder'),
          chip(theme.map.fileAt(0.35), null, 'File'),
          chip(theme.tiers.safe, null, 'Safe to reclaim'),
          if (hasReview) chip(theme.tiers.review, null, 'Review first'),
          chip(null, Icons.lock_outline_rounded, 'Protected'),
        ],
      ),
    );
  }
}
