import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../src/rust/api/scan.dart';
import '../../../theme.dart';
import '../../../util/format.dart';
import '../tree_providers.dart';
import 'squarify.dart';

const _tileGap = 2.0;
const _tileRadius = 4.0;

/// Interactive squarified treemap of the focused directory.
class TreemapView extends ConsumerWidget {
  const TreemapView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusNodeProvider);
    if (focus == null) return const SizedBox.shrink();
    final children = ref.watch(childrenProvider(focus.id));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: children.isEmpty
          ? Center(
              key: ValueKey('empty-${focus.id}'),
              child: Text(
                'Nothing to show in here',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : _TreemapBody(key: ValueKey('map-${focus.id}'), nodes: children),
    );
  }
}

class _TreemapBody extends ConsumerWidget {
  const _TreemapBody({super.key, required this.nodes});

  final List<FsNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final rects = squarify(
          nodes.map((n) => n.size.toDouble()).toList(),
          bounds.deflate(_tileGap / 2),
        );
        return Stack(
          children: [
            for (var i = 0; i < nodes.length; i++)
              if (rects[i].width > _tileGap && rects[i].height > _tileGap)
                Positioned.fromRect(
                  rect: rects[i].deflate(_tileGap / 2),
                  child: _Tile(node: nodes[i]),
                ),
          ],
        );
      },
    );
  }
}

class _Tile extends ConsumerStatefulWidget {
  const _Tile({required this.node});

  final FsNode node;

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
    final node = widget.node;
    final deleted = ref.watch(deletedIdsProvider).contains(node.id);
    final selected = ref.watch(selectedNodeProvider)?.id == node.id;

    final Color fill;
    final Color ink;
    switch (node.tier) {
      case FsTier.safe when !deleted:
        fill = tiers.safe.withValues(alpha: _hovered ? 0.95 : 0.82);
        ink = Colors.white;
      case FsTier.review when !deleted:
        fill = tiers.review.withValues(alpha: _hovered ? 0.95 : 0.82);
        ink = Colors.black87;
      case FsTier.protected:
        fill = tiers.protected.withValues(alpha: 0.30);
        ink = scheme.onSurfaceVariant;
      default:
        if (deleted) {
          fill = scheme.surfaceContainerLow;
          ink = scheme.outline;
        } else {
          final base = switch (node.kind) {
            FsKind.dir => scheme.surfaceContainerHighest,
            FsKind.file => scheme.secondaryContainer.withValues(alpha: 0.55),
            _ => scheme.surfaceContainerHigh.withValues(alpha: 0.6),
          };
          fill = _hovered ? Color.lerp(base, scheme.primary, 0.10)! : base;
          ink = scheme.onSurface;
        }
    }

    final canDrill =
        node.kind == FsKind.dir && node.childCount > 0 && node.id >= 0;
    final showLabel = !deleted;

    return MouseRegion(
      cursor: canDrill ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        richMessage: TextSpan(
          children: [
            TextSpan(
              text: '${node.name}\n',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text:
                  '${formatBytes(node.size)}${node.kind == FsKind.dir ? ' · ${formatCount(node.fileCount)} files' : ''}'
                  '${node.ruleName != null ? '\n${node.ruleName}' : ''}'
                  '${deleted ? '\nMoved to Trash' : ''}',
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () {
            ref.read(selectedNodeProvider.notifier).select(node);
            if (canDrill && selected) {
              // Second tap on an already-selected folder drills in.
              ref.read(focusTrailProvider.notifier).drillInto(node);
            }
          },
          onDoubleTap: canDrill
              ? () => ref.read(focusTrailProvider.notifier).drillInto(node)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(_tileRadius),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : _hovered
                        ? scheme.outline
                        : scheme.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 2 : 1,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, size) {
                if (!showLabel ||
                    size.maxWidth < 56 ||
                    size.maxHeight < 34) {
                  return const SizedBox.expand();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (node.tier == FsTier.protected) ...[
                            Icon(Icons.lock_outline_rounded,
                                size: 12, color: ink),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formatBytes(node.size),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: ink.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
