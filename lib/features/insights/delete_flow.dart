import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../../src/rust/api/ops.dart';
import '../../src/rust/api/scan.dart';
import '../../src/rust/api/system.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../results/tree_providers.dart';

/// Move items to the OS Trash after a lightweight confirmation.
Future<void> confirmAndTrash(
    BuildContext context, WidgetRef ref, List<FsNode> nodes) async {
  final total = nodes.fold<int>(0, (s, n) => s + n.size);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          size: 22,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: const Text('Move to Trash?'),
      content: nodes.length == 1
          ? RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: '"'),
                  TextSpan(text: nodes.first.name),
                  const TextSpan(text: '" ('),
                  TextSpan(
                    text: formatBytes(total),
                    style: mono(13, weight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: ') will move to the Trash. You can restore it from there.',
                  ),
                ],
              ),
            )
          : RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(text: '${nodes.length} items ('),
                  TextSpan(
                    text: formatBytes(total),
                    style: mono(13, weight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: ') will move to the Trash. You can restore them from there.',
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Move to Trash'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final outcomes =
      await moveToTrash(nodeIds: Int64List.fromList([for (final n in nodes) n.id]));
  if (!context.mounted) return;
  _reportOutcomes(context, ref, nodes, outcomes, 'Moved to Trash',
      trashed: true);
}

/// Permanent deletion: gated behind a type-to-confirm dialog. Never the
/// default anywhere in the UI.
Future<void> confirmAndDeletePermanently(
    BuildContext context, WidgetRef ref, List<FsNode> nodes) async {
  final total = nodes.fold<int>(0, (s, n) => s + n.size);
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        title: const Text('Delete permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            nodes.length == 1
                ? RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        const TextSpan(text: '"'),
                        TextSpan(text: nodes.first.name),
                        const TextSpan(text: '" ('),
                        TextSpan(
                          text: formatBytes(total),
                          style: mono(13, weight: FontWeight.w600),
                        ),
                        const TextSpan(
                          text: ') will be deleted immediately. This cannot be undone — nothing goes to the Trash.',
                        ),
                      ],
                    ),
                  )
                : RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        TextSpan(text: '${nodes.length} items ('),
                        TextSpan(
                          text: formatBytes(total),
                          style: mono(13, weight: FontWeight.w600),
                        ),
                        const TextSpan(
                          text: ') will be deleted immediately. This cannot be undone — nothing goes to the Trash.',
                        ),
                      ],
                    ),
                  ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: mono(14),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: controller.text.trim() == 'DELETE'
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Delete forever'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final outcomes = await deletePermanently(
      nodeIds: Int64List.fromList([for (final n in nodes) n.id]),
      confirmed: true);
  if (!context.mounted) return;
  _reportOutcomes(context, ref, nodes, outcomes, 'Deleted');
}

/// Outcomes come back in request order, so zip them against the nodes.
void _reportOutcomes(BuildContext context, WidgetRef ref, List<FsNode> nodes,
    List<OpOutcome> outcomes, String verb,
    {bool trashed = false}) {
  final succeededIds = <int>[];
  OpOutcome? firstFailure;
  for (var i = 0; i < outcomes.length; i++) {
    if (outcomes[i].ok) {
      if (i < nodes.length) succeededIds.add(nodes[i].id);
    } else {
      firstFailure ??= outcomes[i];
    }
  }
  ref.read(deletedIdsProvider.notifier).markDeleted(succeededIds);

  final failedCount = outcomes.length - succeededIds.length;
  final message = failedCount == 0
      ? '$verb ${succeededIds.length} item${succeededIds.length == 1 ? '' : 's'}. '
          'Rescan to update sizes.'
      : '$verb ${succeededIds.length}, $failedCount failed: '
          '${firstFailure?.message ?? 'unknown error'}';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    action: trashed && succeededIds.isNotEmpty
        ? SnackBarAction(label: 'Open Trash', onPressed: openTrash)
        : null,
  ));
}
