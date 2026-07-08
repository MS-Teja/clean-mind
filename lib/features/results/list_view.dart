import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../src/rust/api/system.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../scan/scan_providers.dart';
import 'tree_providers.dart';

/// (column, ascending?) the list view is sorted by. Descending by size default.
final _listSortProvider =
    NotifierProvider<_ListSortController, (SortKey, bool)>(
      _ListSortController.new,
    );

class _ListSortController extends Notifier<(SortKey, bool)> {
  @override
  (SortKey, bool) build() {
    final p = getUiPrefs();
    final key = switch (p.sortKey) {
      'name' => SortKey.name,
      'items' => SortKey.items,
      _ => SortKey.size,
    };
    return (key, p.sortAscending);
  }

  /// Toggle direction if the same column is tapped, else switch column
  /// (size/items start descending; name starts ascending).
  void tap(SortKey key) {
    final (cur, asc) = state;
    if (cur == key) {
      state = (key, !asc);
    } else {
      state = (key, key == SortKey.name);
    }
    _persist();
  }

  void _persist() {
    final (key, asc) = state;
    final p = getUiPrefs();
    setUiPrefs(
      prefs: UiPrefs(
        resultsView: p.resultsView,
        sortKey: switch (key) {
          SortKey.name => 'name',
          SortKey.items => 'items',
          SortKey.size => 'size',
        },
        sortAscending: asc,
      ),
    );
  }
}

/// Sortable table of the focused directory's children — the list alternative
/// to the treemap.
class ListDirView extends ConsumerWidget {
  const ListDirView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusNodeProvider);
    if (focus == null) return const SizedBox.shrink();
    final (key, asc) = ref.watch(_listSortProvider);
    ref.watch(scanControllerProvider); // recompute on a new scan
    final rows = getChildrenSorted(
      id: focus.id,
      key: key,
      ascending: asc,
      limit: 500,
    );
    final selectedId = ref.watch(selectedNodeProvider)?.id;

    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Nothing to show in here',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        _HeaderRow(sortKey: key, ascending: asc),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _Row(node: rows[i], selected: rows[i].id == selectedId),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends ConsumerWidget {
  const _HeaderRow({required this.sortKey, required this.ascending});

  final SortKey sortKey;
  final bool ascending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(_listSortProvider.notifier);

    Widget head(String label, SortKey key, {TextAlign align = TextAlign.left}) {
      final active = sortKey == key;
      return InkWell(
        onTap: () => ctrl.tap(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: align == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: active
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (active)
                Icon(
                  ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurface,
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: head('Name', SortKey.name)),
          Expanded(
            flex: 2,
            child: head('Items', SortKey.items, align: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: head('Size', SortKey.size, align: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.node, required this.selected});

  final FsNode node;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final deleted = ref.watch(deletedIdsProvider).contains(node.id);
    final canDrill =
        node.kind == FsKind.dir && node.childCount > 0 && node.id >= 0;
    final items = node.fileCount + node.dirCount;

    final tierColor = switch (node.tier) {
      FsTier.safe => theme.tiers.safe,
      FsTier.review => theme.tiers.review,
      FsTier.protected => theme.tiers.protected,
      FsTier.none => null,
    };

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(selectedNodeProvider.notifier).select(node),
        onDoubleTap: canDrill
            ? () => ref.read(focusTrailProvider.notifier).drillInto(node)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Icon(
                      node.tier == FsTier.protected
                          ? Icons.lock_rounded
                          : switch (node.kind) {
                              FsKind.dir => Icons.folder_rounded,
                              FsKind.file => Icons.insert_drive_file_rounded,
                              FsKind.smallFiles => Icons.grain_rounded,
                              FsKind.rest => Icons.more_horiz_rounded,
                            },
                      size: 15,
                      color: tierColor ?? scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: deleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: deleted ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    if (tierColor != null && node.tier == FsTier.safe) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: tierColor,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  node.kind == FsKind.dir || node.kind == FsKind.smallFiles
                      ? formatCount(
                          node.kind == FsKind.smallFiles
                              ? node.itemCount
                              : items,
                        )
                      : '—',
                  textAlign: TextAlign.right,
                  style: mono(11.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatBytes(node.size),
                  textAlign: TextAlign.right,
                  style: mono(12, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whole-scan search results — flat list of matches, largest first, each
/// tappable to jump to it in the tree.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final results = ref.watch(searchResultsProvider);
    final selectedId = ref.watch(selectedNodeProvider)?.id;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No matches',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text(
            '${results.length} match${results.length == 1 ? '' : 'es'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final node = results[i];
              final tierColor = switch (node.tier) {
                FsTier.safe => theme.tiers.safe,
                FsTier.review => theme.tiers.review,
                FsTier.protected => theme.tiers.protected,
                FsTier.none => null,
              };
              return Material(
                color: node.id == selectedId
                    ? scheme.primary.withValues(alpha: 0.10)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => revealNodeId(ref, node.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          node.kind == FsKind.dir
                              ? Icons.folder_rounded
                              : Icons.insert_drive_file_rounded,
                          size: 15,
                          color: tierColor ?? scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                node.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(
                                  10.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatBytes(node.size),
                          style: mono(12, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
