import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/insights.dart';
import '../../src/rust/api/llm.dart';
import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../ui/widgets.dart';
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Insights', style: theme.textTheme.headlineSmall),
              const Spacer(),
              if (safe.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatBytes(safe.fold(0, (s, i) => s + i.size)),
                      style: mono(15,
                          weight: FontWeight.w700, color: theme.tiers.safe),
                    ),
                    const SizedBox(width: 6),
                    Text('safe to reclaim',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            children: [
              // AI entry point stays at the top: with a page of insights it
              // would otherwise be scrolled out of existence.
              const _AiSection(),
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
                _CategoryHeader(title: entry.key, insights: entry.value),
                for (final insight in entry.value)
                  _InsightTile(insight: insight),
                const SizedBox(height: 8),
              ],
              if (review.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 14, bottom: 4),
                  child: _ReviewHeader(),
                ),
                for (final insight in review) _InsightTile(insight: insight),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: selectedInsights.isEmpty
              ? const SizedBox(width: double.infinity)
              : _SelectionBar(
                  count: selectedInsights.length,
                  total: selectedTotal,
                  onTrash: () => _deleteSelected(context, ref, selectedInsights),
                  onDeletePermanently: () => _deleteSelected(
                      context, ref, selectedInsights,
                      permanent: true),
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

/// Floating action bar shown while insights are selected.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.onTrash,
    required this.onDeletePermanently,
  });

  final int count;
  final int total;
  final VoidCallback onTrash;
  final VoidCallback onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
        radius: 16,
        color: theme.colorScheme.surfaceContainerHigh,
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.titleSmall,
                  children: [
                    TextSpan(text: '$count selected · '),
                    TextSpan(
                      text: formatBytes(total),
                      style: mono(14,
                          weight: FontWeight.w600,
                          color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error),
                  onPressed: onDeletePermanently,
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
              onPressed: onTrash,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.help_outline_rounded, size: 16, color: theme.tiers.review),
        const SizedBox(width: 6),
        Text('Review before deleting',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
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
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(
            formatBytes(insights.fold(0, (s, i) => s + i.size)),
            style: mono(12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
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
    final scheme = theme.colorScheme;
    final selected =
        ref.watch(insightSelectionProvider).contains(insight.nodeId);
    final staleness = formatStaleness(insight.staleDays);
    final tierColor =
        insight.tier == FsTier.safe ? theme.tiers.safe : theme.tiers.review;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref
              .read(insightSelectionProvider.notifier)
              .toggle(insight.nodeId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? theme.tiers.safe.withValues(alpha: 0.05)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.tiers.safe.withValues(alpha: 0.5)
                    : scheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => ref
                        .read(insightSelectionProvider.notifier)
                        .toggle(insight.nodeId),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(insight.ruleName,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text(formatBytes(insight.size),
                              style: mono(13,
                                  weight: FontWeight.w700, color: tierColor)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(insight.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(10.5, color: scheme.outline)),
                      const SizedBox(height: 5),
                      Text(insight.explanation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (insight.regenerateWith != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('↻ ${insight.regenerateWith}',
                                  style: mono(10.5, color: scheme.primary)),
                            ),
                          if (staleness.isNotEmpty)
                            Text(staleness,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: scheme.outline)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.auto_awesome_rounded, size: 30),
              const SizedBox(width: 10),
              Text('AI analysis',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (configured)
                FilledButton.tonal(
                  onPressed: ai.isLoading
                      ? null
                      : () => ref.read(aiAnalysisProvider.notifier).analyze(),
                  child: Text(ai.isLoading ? 'Analyzing…' : 'Analyze'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!configured) ...[
            Text(
              'Point Clean Mind at your own LLM — an Anthropic or '
              'OpenAI-compatible API key, or a local Ollama model — and it '
              'will look through the largest folders for things the rules '
              'engine doesn\'t know about. Only folder names, sizes, and '
              'ages are sent; never file contents.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
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
    );
  }
}

class _AiTile extends ConsumerWidget {
  const _AiTile({required this.rec});

  final AiRecommendation rec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final review = theme.tiers.review;
    final deleted = ref.watch(deletedIdsProvider).contains(rec.nodeId);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: review.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: review.withValues(alpha: 0.3)),
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
                    style: mono(11.5, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(formatBytes(rec.size),
                  style: mono(12, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          Text(rec.reasoning, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    value: rec.confidence.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: scheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation(review),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${(rec.confidence * 100).round()}%',
                  style: mono(10, color: scheme.onSurfaceVariant)),
              if (rec.regenerability.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(rec.regenerability,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.outline)),
                ),
              ],
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
