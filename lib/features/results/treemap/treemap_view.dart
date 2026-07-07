import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../src/rust/api/ops.dart';
import '../../../src/rust/api/scan.dart';
import '../../../theme.dart';
import '../../../util/format.dart';
import '../../../util/platform.dart';
import '../../insights/delete_flow.dart';
import '../../insights/insights_providers.dart';
import '../tree_providers.dart';
import 'squarify.dart';

const _tileGap = 3.0;
const _tileRadius = 7.0;

/// Interactive squarified treemap of the focused directory.
///
/// Design: folders and files sit on quiet sequential ramps (bigger → richer)
/// so the map reads as terrain; saturated color is reserved for meaning —
/// emerald for "safe to reclaim", amber for "review", dim + lock for
/// protected. Folder tiles paint a one-level mini-map of their children and
/// carry an emerald chip when reclaimable space hides inside.
class TreemapView extends ConsumerWidget {
  const TreemapView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusNodeProvider);
    if (focus == null) return const SizedBox.shrink();
    final children = ref.watch(childrenProvider(focus.id));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: children.isEmpty
          ? Center(
              key: ValueKey('empty-${focus.id}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 10),
                  Text('Nothing to show in here',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                ],
              ),
            )
          : _TreemapBody(key: ValueKey('map-${focus.id}'), nodes: children),
    );
  }
}

class _TreemapBody extends StatelessWidget {
  const _TreemapBody({super.key, required this.nodes});

  final List<FsNode> nodes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final rects = squarify(
          nodes.map((n) => n.size.toDouble()).toList(),
          bounds.deflate(_tileGap / 2),
        );
        // Size ranking for the sequential ramp: 0 = biggest in view.
        final n = nodes.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < nodes.length; i++)
              if (rects[i].width > _tileGap && rects[i].height > _tileGap)
                Positioned.fromRect(
                  rect: rects[i].deflate(_tileGap / 2),
                  child: _Tile(
                    node: nodes[i],
                    rampT: n <= 1 ? 0 : i / (n - 1),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Tile extends ConsumerStatefulWidget {
  const _Tile({required this.node, required this.rampT});

  final FsNode node;

  /// 0 → biggest in the current view, 1 → smallest.
  final double rampT;

  @override
  ConsumerState<_Tile> createState() => _TileState();
}

class _TileState extends ConsumerState<_Tile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tiers = theme.tiers;
    final map = theme.map;
    final isDark = theme.brightness == Brightness.dark;
    final node = widget.node;
    final deleted = ref.watch(deletedIdsProvider).contains(node.id);
    final selected = ref.watch(selectedNodeProvider)?.id == node.id;

    // Tier fills override the ramp: color = meaning.
    Color fill;
    Color ink;
    Color inkFaint;
    var tinted = false; // tile carries a tier color
    if (deleted) {
      fill = map.chunk;
      ink = map.inkFaint;
      inkFaint = map.inkFaint;
    } else {
      switch (node.tier) {
        case FsTier.safe:
          fill = tiers.safe;
          ink = isDark ? const Color(0xFF04251A) : Colors.white;
          inkFaint = ink.withValues(alpha: 0.72);
          tinted = true;
        case FsTier.review:
          fill = tiers.review;
          ink = isDark ? const Color(0xFF2A1D04) : Colors.white;
          inkFaint = ink.withValues(alpha: 0.72);
          tinted = true;
        case FsTier.protected:
          fill = map.chunk;
          ink = map.inkFaint;
          inkFaint = map.inkFaint.withValues(alpha: 0.8);
        case FsTier.none:
          fill = switch (node.kind) {
            FsKind.dir => map.folderAt(widget.rampT),
            FsKind.file => map.fileAt(widget.rampT),
            _ => map.chunk,
          };
          ink = map.ink;
          inkFaint = map.inkFaint;
      }
    }
    if (_hovered && !deleted) {
      fill = Color.lerp(fill, isDark ? Colors.white : Colors.black, 0.06)!;
    }

    final canDrill =
        node.kind == FsKind.dir && node.childCount > 0 && node.id >= 0;

    return MouseRegion(
      cursor: canDrill ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        richMessage: TextSpan(
          children: [
            TextSpan(
              text: '${node.name}\n',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text:
                  '${formatBytes(node.size)}${node.kind == FsKind.dir ? ' · ${formatCount(node.fileCount)} files' : ''}'
                  '${node.ruleName != null ? '\n${node.ruleName}' : ''}'
                  '${deleted ? '\nMoved to Trash' : ''}'
                  '${canDrill ? '\nDouble-click to open' : ''}',
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () {
            ref.read(selectedNodeProvider.notifier).select(node);
            if (canDrill && selected) {
              ref.read(focusTrailProvider.notifier).drillInto(node);
            }
          },
          onDoubleTap: canDrill
              ? () => ref.read(focusTrailProvider.notifier).drillInto(node)
              : null,
          onSecondaryTapDown: (details) {
            ref.read(selectedNodeProvider.notifier).select(node);
            _showTileMenu(context, ref, details.globalPosition, node);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(_tileRadius),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : _hovered
                        ? scheme.primary.withValues(alpha: 0.55)
                        : isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.7),
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                if (selected || _hovered)
                  BoxShadow(
                    color: scheme.primary
                        .withValues(alpha: selected ? 0.30 : 0.14),
                    blurRadius: selected ? 18 : 12,
                  ),
              ],
            ),
            child: _TileContent(
              node: node,
              ink: ink,
              inkFaint: inkFaint,
              tinted: tinted,
              deleted: deleted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-click actions for a tile: Open, Reveal, Copy Path, Move to Trash.
/// No-op for aggregates (small-files / "N more") which have no single path.
Future<void> _showTileMenu(
    BuildContext context, WidgetRef ref, Offset globalPos, FsNode node) async {
  if (node.id < 0 ||
      node.kind == FsKind.smallFiles ||
      node.kind == FsKind.rest) {
    return;
  }
  final isProtected = node.tier == FsTier.protected;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPos & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: [
      _menuItem('open', Icons.open_in_new_rounded, 'Open'),
      _menuItem('reveal', Icons.visibility_rounded, 'Reveal'),
      _menuItem('copy', Icons.copy_rounded, 'Copy Path'),
      if (!isProtected) const PopupMenuDivider(),
      if (!isProtected)
        _menuItem('trash', Icons.delete_outline_rounded, 'Move to $trashName'),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'open':
      try {
        openItem(nodeId: node.id);
      } catch (_) {}
    case 'reveal':
      try {
        revealInFileManager(nodeId: node.id);
      } catch (_) {}
    case 'copy':
      await Clipboard.setData(ClipboardData(text: node.path));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Path copied')),
        );
      }
    case 'trash':
      await confirmAndTrash(context, ref, [node]);
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
  return PopupMenuItem<String>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );
}

class _TileContent extends ConsumerWidget {
  const _TileContent({
    required this.node,
    required this.ink,
    required this.inkFaint,
    required this.tinted,
    required this.deleted,
  });

  final FsNode node;
  final Color ink;
  final Color inkFaint;
  final bool tinted;
  final bool deleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, size) {
        final w = size.maxWidth;
        final h = size.maxHeight;
        final showLabel = !deleted && w >= 64 && h >= 40;
        final showSize = showLabel && h >= 56;
        // One-level mini-map inside roomy, untinted folder tiles.
        final showPreview = !deleted &&
            !tinted &&
            node.kind == FsKind.dir &&
            node.tier != FsTier.protected &&
            node.childCount > 0 &&
            w >= 120 &&
            h >= 96;
        final reclaimable = node.kind == FsKind.dir && !tinted && !deleted
            ? ref.watch(reclaimableUnderProvider(node.path))
            : 0;
        final showChip = reclaimable > 0 && w >= 110 && h >= 64;

        return ClipRRect(
          borderRadius: BorderRadius.circular(_tileRadius - 1),
          child: Stack(
            children: [
              if (showPreview)
                Positioned.fill(
                  top: showSize ? 46 : (showLabel ? 30 : 6),
                  left: 6,
                  right: 6,
                  bottom: showChip ? 30 : 6,
                  child: _ChildPreview(nodeId: node.id),
                ),
              if (showLabel)
                Positioned(
                  left: 9,
                  top: 7,
                  right: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (node.tier == FsTier.protected) ...[
                            Icon(Icons.lock_rounded, size: 11, color: ink),
                            const SizedBox(width: 4),
                          ],
                          if (tinted &&
                              node.tier == FsTier.safe &&
                              w >= 90) ...[
                            Icon(Icons.check_circle_rounded,
                                size: 12, color: ink),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: displayFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ink,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (showSize)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            formatBytes(node.size),
                            style: mono(10.5, color: inkFaint),
                          ),
                        ),
                    ],
                  ),
                ),
              if (deleted)
                Center(
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: inkFaint),
                ),
              if (showChip)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _ReclaimChip(bytes: reclaimable),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Emerald "value hidden inside" badge for folders whose subtree contains
/// rules-verified reclaimable space.
class _ReclaimChip extends StatelessWidget {
  const _ReclaimChip({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safe = theme.tiers.safe;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0A1F17).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: safe.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cleaning_services_rounded, size: 10, color: safe),
          const SizedBox(width: 4),
          Text(formatBytes(bytes),
              style: mono(10, weight: FontWeight.w600, color: safe)),
        ],
      ),
    );
  }
}

/// Flat one-level mini-map of a folder's children, painted inside its tile.
class _ChildPreview extends ConsumerWidget {
  const _ChildPreview({required this.nodeId});

  final int nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider(nodeId));
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _ChildPreviewPainter(
        children: children,
        map: theme.map,
        tiers: theme.tiers,
        isDark: theme.brightness == Brightness.dark,
      ),
      size: Size.infinite,
    );
  }
}

class _ChildPreviewPainter extends CustomPainter {
  _ChildPreviewPainter({
    required this.children,
    required this.map,
    required this.tiers,
    required this.isDark,
  });

  final List<FsNode> children;
  final MapColors map;
  final TierColors tiers;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rects = squarify(
      children.map((n) => n.size.toDouble()).toList(),
      Offset.zero & size,
    );
    final n = children.length;
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final r = rects[i].deflate(1);
      if (r.width < 2 || r.height < 2) continue;
      final child = children[i];
      final t = n <= 1 ? 0.0 : i / (n - 1);
      paint.color = switch (child.tier) {
        FsTier.safe => tiers.safe.withValues(alpha: 0.85),
        FsTier.review => tiers.review.withValues(alpha: 0.85),
        FsTier.protected => map.chunk,
        FsTier.none => switch (child.kind) {
            FsKind.dir => map.folderAt(t * 0.6).withValues(alpha: 0.55),
            FsKind.file => map.fileAt(t * 0.6).withValues(alpha: 0.55),
            _ => map.chunk.withValues(alpha: 0.7),
          },
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChildPreviewPainter old) =>
      old.children != children || old.isDark != isDark;
}
