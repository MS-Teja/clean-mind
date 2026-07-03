import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/insights.dart';
import '../../src/rust/api/llm.dart';
import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../results/tree_providers.dart';
import '../settings/settings_dialog.dart';
import '../settings/settings_providers.dart';
import 'delete_flow.dart';
import 'insights_providers.dart';

void showInsightsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) => const FractionallySizedBox(
      heightFactor: 0.88,
      child: InsightsSheet(),
    ),
  );
}

class InsightsSheet extends ConsumerWidget {
  const InsightsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insights = ref.watch(insightsProvider);
    final deleted = ref.watch(deletedIdsProvider);
    final selection = ref.watch(insightSelectionProvider);

    final safe = insights
        .where((i) => i.tier == FsTier.safe && !deleted.contains(i.nodeId))
        .toList();
    final review = insights
        .where((i) => i.tier == FsTier.review && !deleted.contains(i.nodeId))
        .toList();
    final selectedInsights = [...safe, ...review]
        .where((i) => selection.contains(i.nodeId))
        .toList();
    final selectedTotal =
        selectedInsights.fold<int>(0, (s, i) => s + i.size);

    final byCategory = <String, List<Insight>>{};
    for (final insight in safe) {
      byCategory.putIfAbsent(insight.category, () => []).add(insight);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Row(
            children: [
              Text('Insights',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (safe.isNotEmpty)
                Text(
                  '${formatBytes(safe.fold(0, (s, i) => s + i.size))} safe to reclaim',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.tiers.safe),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            children: [
              if (safe.isEmpty && review.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 40, color: theme.tiers.safe),
                      const SizedBox(height: 8),
                      Text(
                        'No known developer bloat found in this scan.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              for (final entry in byCategory.entries) ...[
                _CategoryHeader(
                  title: entry.key,
                  insights: entry.value,
                ),
                for (final insight in entry.value)
                  _InsightTile(insight: insight),
                const SizedBox(height: 8),
              ],
              if (review.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.help_outline_rounded,
                        size: 16, color: theme.tiers.review),
                    const SizedBox(width: 6),
                    Text('Review before deleting',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                for (final insight in review) _InsightTile(insight: insight),
              ],
              const SizedBox(height: 16),
              const _AiSection(),
            ],
          ),
        ),
        if (selectedInsights.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selectedInsights.length} selected · ${formatBytes(selectedTotal)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: Icon(Icons.warning_amber_rounded,
                          color: theme.colorScheme.error),
                      onPressed: () => _deleteSelected(
                          context, ref, selectedInsights,
                          permanent: true),
                      child: const Text('Delete permanently…'),
                    ),
                  ],
                  builder: (context, controller, _) => IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Move to Trash'),
                  onPressed: () =>
                      _deleteSelected(context, ref, selectedInsights),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deleteSelected(
      BuildContext context, WidgetRef ref, List<Insight> insights,
      {bool permanent = false}) async {
    final nodes = insights
        .map((i) => getNode(id: i.nodeId))
        .whereType<FsNode>()
        .toList();
    if (nodes.isEmpty) return;
    if (permanent) {
      await confirmAndDeletePermanently(context, ref, nodes);
    } else {
      await confirmAndTrash(context, ref, nodes);
    }
    ref.read(insightSelectionProvider.notifier).clear();
  }
}

class _CategoryHeader extends ConsumerWidget {
  const _CategoryHeader({required this.title, required this.insights});

  final String title;
  final List<Insight> insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(insightSelectionProvider);
    final ids = insights.map((i) => i.nodeId).toList();
    final allSelected = ids.every(selection.contains);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(
            formatBytes(insights.fold(0, (s, i) => s + i.size)),
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => ref
                .read(insightSelectionProvider.notifier)
                .setMany(ids, !allSelected),
            child: Text(allSelected ? 'Deselect all' : 'Select all'),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends ConsumerWidget {
  const _InsightTile({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected =
        ref.watch(insightSelectionProvider).contains(insight.nodeId);
    final staleness = formatStaleness(insight.staleDays);
    final tierColor =
        insight.tier == FsTier.safe ? theme.tiers.safe : theme.tiers.review;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) =>
            ref.read(insightSelectionProvider.notifier).toggle(insight.nodeId),
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Expanded(
              child: Text(insight.ruleName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Text(formatBytes(insight.size),
                style: theme.textTheme.titleSmall?.copyWith(
                    color: tierColor, fontWeight: FontWeight.w700)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(insight.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 3),
            Text(insight.explanation, style: theme.textTheme.bodySmall),
            const SizedBox(height: 3),
            Wrap(
              spacing: 12,
              children: [
                if (insight.regenerateWith != null)
                  Text('↻ ${insight.regenerateWith}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontFamily: 'monospace')),
                if (staleness.isNotEmpty)
                  Text(staleness,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSection extends ConsumerWidget {
  const _AiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ai = ref.watch(aiAnalysisProvider);
    final settings = ref.watch(llmSettingsProvider);
    final configured = settings.provider == 'ollama' ||
        ref.watch(hasApiKeyProvider(settings.provider));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('AI analysis',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (configured)
                  FilledButton.tonal(
                    onPressed: ai.isLoading
                        ? null
                        : () =>
                            ref.read(aiAnalysisProvider.notifier).analyze(),
                    child: Text(ai.isLoading ? 'Analyzing…' : 'Analyze'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!configured) ...[
              Text(
                'Point Clean Mind at your own LLM — an Anthropic or '
                'OpenAI-compatible API key, or a local Ollama model — and it '
                'will look through the largest folders for things the rules '
                'engine doesn\'t know about. Only folder names, sizes, and '
                'ages are sent; never file contents.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => showSettingsDialog(context),
                child: const Text('Set up a provider'),
              ),
            ] else
              switch (ai) {
                AsyncData(:final value) when value == null => Text(
                    'Sends the largest folders (names, sizes, ages — never '
                    'contents${settings.redact ? ', with names pseudonymized' : ''}) '
                    'to ${settings.model}. Suggestions always land in the '
                    '"review" tier — nothing is deleted automatically.',
                    style: theme.textTheme.bodySmall,
                  ),
                AsyncData(:final value) when value != null && value.isEmpty =>
                  Text('No additional suggestions — the rules engine already '
                      'covered what the model found.',
                      style: theme.textTheme.bodySmall),
                AsyncData(:final value) when value != null => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suggestions from ${settings.model} — always double-check '
                        'before deleting:',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      for (final rec in value) _AiTile(rec: rec),
                    ],
                  ),
                AsyncLoading() => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text('Asking ${settings.model}…',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                AsyncError(:final error) => Text(
                    'Analysis failed: $error',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                _ => const SizedBox.shrink(),
              },
          ],
        ),
      ),
    );
  }
}

class _AiTile extends ConsumerWidget {
  const _AiTile({required this.rec});

  final AiRecommendation rec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final deleted = ref.watch(deletedIdsProvider).contains(rec.nodeId);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.tiers.review.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: theme.tiers.review.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(rec.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(formatBytes(rec.size),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(rec.reasoning, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'confidence ${(rec.confidence * 100).round()}%'
                '${rec.regenerability.isNotEmpty ? ' · ${rec.regenerability}' : ''}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const Spacer(),
              if (deleted)
                Text('Moved to Trash', style: theme.textTheme.labelSmall)
              else
                TextButton(
                  onPressed: () {
                    final node = getNode(id: rec.nodeId);
                    if (node != null) {
                      confirmAndTrash(context, ref, [node]);
                    }
                  },
                  child: const Text('Move to Trash'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
