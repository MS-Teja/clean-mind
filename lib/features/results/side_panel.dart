import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/ops.dart';
import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../ui/widgets.dart';
import '../../util/format.dart';
import '../insights/delete_flow.dart';
import 'tree_providers.dart';

/// Details for the selected tile; falls back to the focused directory.
class SidePanel extends ConsumerWidget {
  const SidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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

    final isProtected = node.tier == FsTier.protected;
    final headerColor = isProtected
        ? theme.tiers.protected
        : (tierColor ?? scheme.primary);
    final headerIcon = isProtected
        ? Icons.lock_rounded
        : switch (node.kind) {
            FsKind.dir => Icons.folder_rounded,
            FsKind.file => Icons.insert_drive_file_rounded,
            FsKind.smallFiles => Icons.grain_rounded,
            FsKind.rest => Icons.more_horiz_rounded,
          };

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: headerIcon, color: headerColor, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    node.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatBytes(node.size),
            style: mono(28, weight: FontWeight.w700, color: scheme.onSurface),
          ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text('${percent.toStringAsFixed(1)}% of this view',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          if (node.kind == FsKind.dir) ...[
            _MetaRow(label: 'Files', value: formatCount(node.fileCount)),
            const SizedBox(height: 6),
            _MetaRow(label: 'Folders', value: formatCount(node.dirCount)),
          ],
          if (node.kind == FsKind.smallFiles)
            _MetaRow(label: 'Items', value: formatCount(node.itemCount)),
          if (node.path.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassPanel(
              color: scheme.surfaceContainer,
              radius: 10,
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      node.path,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: 'Copy path',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: node.path));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Path copied')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (tierColor != null && node.ruleName != null) ...[
            const SizedBox(height: 14),
            _TierCard(node: node, color: tierColor),
          ] else if (isProtected) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: theme.tiers.protected),
                const SizedBox(width: 8),
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
                  style: mono(12, color: scheme.onSurfaceVariant)),
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
                if (!isProtected) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Trash'),
                      onPressed: () => confirmAndTrash(context, ref, [node]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        Text(value,
            style: mono(12, color: theme.colorScheme.onSurface)),
      ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
                size: 15,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  node.ruleName ?? '',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
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
