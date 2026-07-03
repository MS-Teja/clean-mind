import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/ops.dart';
import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../insights/delete_flow.dart';
import 'tree_providers.dart';

/// Details for the selected tile; falls back to the focused directory.
class SidePanel extends ConsumerWidget {
  const SidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final node = ref.watch(selectedNodeProvider) ?? ref.watch(focusNodeProvider);
    if (node == null) return const SizedBox.shrink();
    final deleted = ref.watch(deletedIdsProvider).contains(node.id);
    final focus = ref.watch(focusNodeProvider);
    final percent = focus != null && focus.size > 0 && node.id != focus.id
        ? node.size / focus.size * 100
        : null;

    final tierColor = switch (node.tier) {
      FsTier.safe => theme.tiers.safe,
      FsTier.review => theme.tiers.review,
      FsTier.protected => theme.tiers.protected,
      FsTier.none => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (node.kind) {
                    FsKind.dir => Icons.folder_rounded,
                    FsKind.file => Icons.insert_drive_file_rounded,
                    FsKind.smallFiles => Icons.grain_rounded,
                    FsKind.rest => Icons.more_horiz_rounded,
                  },
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatBytes(node.size),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            if (percent != null)
              Text('${percent.toStringAsFixed(1)}% of this view',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            if (node.kind == FsKind.dir)
              Text(
                '${formatCount(node.fileCount)} files · '
                '${formatCount(node.dirCount)} folders',
                style: theme.textTheme.bodySmall,
              ),
            if (node.kind == FsKind.smallFiles)
              Text('${formatCount(node.itemCount)} small files, shown together',
                  style: theme.textTheme.bodySmall),
            if (node.path.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                node.path,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (tierColor != null && node.ruleName != null) ...[
              const SizedBox(height: 12),
              _TierCard(node: node, color: tierColor),
            ] else if (node.tier == FsTier.protected) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 16, color: theme.tiers.protected),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Protected — Clean Mind never deletes from here.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            if (deleted)
              Center(
                child: Text('Moved to Trash',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.outline)),
              )
            else if (node.id >= 0 && node.kind != FsKind.smallFiles) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Reveal'),
                      onPressed: () {
                        try {
                          revealInFileManager(nodeId: node.id);
                        } catch (_) {}
                      },
                    ),
                  ),
                  if (node.tier != FsTier.protected) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        label: const Text('Trash'),
                        onPressed: () =>
                            confirmAndTrash(context, ref, [node]),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.node, required this.color});

  final FsNode node;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                node.tier == FsTier.safe
                    ? Icons.check_circle_rounded
                    : Icons.help_outline_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.ruleName ?? '',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            node.tier == FsTier.safe
                ? 'Safe to reclaim — see Insights for details.'
                : 'Worth reviewing — see Insights for details.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
