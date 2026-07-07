import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../insights/insights_providers.dart';
import '../insights/insights_sheet.dart';
import '../scan/scan_providers.dart';
import '../settings/settings_dialog.dart';
import 'list_view.dart';
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
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    final view = ref.watch(resultsViewProvider);

    final trail = ref.read(focusTrailProvider.notifier);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            trail.goBack,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
            trail.goBack,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            trail.goForward,
        const SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
            trail.goForward,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Container(
                height: 60,
                // Inset the left edge on macOS so the nav buttons clear the
                // window traffic lights under the transparent title bar.
                padding: EdgeInsets.only(
                  left: Platform.isMacOS ? 82 : 20,
                  right: 20,
                  top: 12,
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    const _NavButtons(),
                    const SizedBox(width: 4),
                    const Expanded(child: _Breadcrumbs()),
                    const SizedBox(width: 10),
                    const _SearchField(),
                    const SizedBox(width: 10),
                    _ReclaimablePill(bytes: reclaimable),
                    const SizedBox(width: 6),
                    const _ViewToggle(),
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
                      Expanded(
                        child: searching
                            ? const SearchResultsView()
                            : view == ResultsView.list
                                ? const ListDirView()
                                : const TreemapView(),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(width: 300, child: SidePanel()),
                    ],
                  ),
                ),
              ),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Browser-style back/forward through visited folders.
class _NavButtons extends ConsumerWidget {
  const _NavButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when the trail changes so enabled-state stays fresh.
    ref.watch(focusTrailProvider);
    final trail = ref.read(focusTrailProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Back',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: trail.canGoBack ? trail.goBack : null,
        ),
        IconButton(
          tooltip: 'Forward',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          onPressed: trail.canGoForward ? trail.goForward : null,
        ),
      ],
    );
  }
}

/// Treemap ⇄ list toggle for the current directory.
class _ViewToggle extends ConsumerWidget {
  const _ViewToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(resultsViewProvider);
    final ctrl = ref.read(resultsViewProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Treemap',
          visualDensity: VisualDensity.compact,
          isSelected: view == ResultsView.treemap,
          icon: const Icon(Icons.grid_view_rounded, size: 20),
          onPressed: () => ctrl.set(ResultsView.treemap),
        ),
        IconButton(
          tooltip: 'List',
          visualDensity: VisualDensity.compact,
          isSelected: view == ResultsView.list,
          icon: const Icon(Icons.view_list_rounded, size: 20),
          onPressed: () => ctrl.set(ResultsView.list),
        ),
      ],
    );
  }
}

/// Whole-scan search box. Filters by name across the entire tree.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Keep the field in sync when a new scan clears the query.
    final query = ref.watch(searchQueryProvider);
    if (query.isEmpty && _controller.text.isNotEmpty) {
      _controller.clear();
    }
    return SizedBox(
      width: 210,
      height: 36,
      child: TextField(
        controller: _controller,
        onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search this scan',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () =>
                      ref.read(searchQueryProvider.notifier).set(''),
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
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
                    'granting Full Disk Access reduces this. Click to see which.',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _showSkippedPaths(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
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
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dialog listing the itemized paths that couldn't be read during the scan.
void _showSkippedPaths(BuildContext context) {
  final paths = scanSkippedPaths();
  showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: const Text("Folders that couldn't be read"),
        content: SizedBox(
          width: 520,
          child: paths.isEmpty
              ? const Text(
                  'No specific paths were recorded for this scan.\n\n'
                  'These are usually permission-protected system folders. On '
                  'macOS, granting Full Disk Access in System Settings reduces '
                  'this.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skipped during the scan (usually permission-protected). '
                      'On macOS, Full Disk Access reduces this.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: paths.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: SelectableText(
                            paths[i],
                            style: mono(11.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
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
