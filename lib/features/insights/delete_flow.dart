import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../../src/rust/api/ops.dart';
import '../../src/rust/api/scan.dart';
import '../../util/format.dart';
import '../results/tree_providers.dart';

/// Move items to the OS Trash after a lightweight confirmation.
Future<void> confirmAndTrash(
    BuildContext context, WidgetRef ref, List<FsNode> nodes) async {
  final total = nodes.fold<int>(0, (s, n) => s + n.size);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move to Trash?'),
      content: Text(
        nodes.length == 1
            ? '"${nodes.first.name}" (${formatBytes(total)}) will move to the '
                'Trash. You can restore it from there.'
            : '${nodes.length} items (${formatBytes(total)}) will move to the '
                'Trash. You can restore them from there.',
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
  _reportOutcomes(context, ref, nodes, outcomes, 'Moved to Trash');
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
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error),
        title: const Text('Delete permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${nodes.length == 1 ? '"${nodes.first.name}"' : '${nodes.length} items'} '
              '(${formatBytes(total)}) will be deleted immediately. '
              'This cannot be undone — nothing goes to the Trash.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
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
    List<OpOutcome> outcomes, String verb) {
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
