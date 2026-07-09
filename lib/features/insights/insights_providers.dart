import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/insights.dart';
import '../../src/rust/api/llm.dart';
import '../../src/rust/api/scan.dart';
import '../results/tree_providers.dart';
import '../scan/scan_providers.dart';

/// Everything the rules engine flagged in the current scan, largest first.
final insightsProvider = Provider<List<Insight>>((ref) {
  final scan = ref.watch(scanControllerProvider);
  if (scan is! ScanDone) return const [];
  return getInsights();
});

/// Total bytes in Tier-1 (rules-verified) items not yet reclaimed.
final reclaimableTotalProvider = Provider<int>((ref) {
  final deleted = ref.watch(deletedIdsProvider);
  return ref
      .watch(insightsProvider)
      .where((i) => i.tier == FsTier.safe && !deleted.contains(i.nodeId))
      .fold(0, (sum, i) => sum + i.size);
});

/// Not-yet-reclaimed Tier-1 bytes, indexed by every ancestor path prefix of
/// each qualifying insight (built once per insights/deleted change, instead
/// of re-scanning all insights per tile). An insight at `a/b/c/d` adds its
/// size under `a/b/c`, `a/b`, and `a` — never under `a/b/c/d` itself, which
/// matches the strict-descendant semantics of the prior `startsWith` scan.
final reclaimableIndexProvider = Provider<Map<String, int>>((ref) {
  final deleted = ref.watch(deletedIdsProvider);
  final index = <String, int>{};
  for (final i in ref.watch(insightsProvider)) {
    if (i.tier != FsTier.safe || deleted.contains(i.nodeId)) continue;
    var p = i.path;
    while (true) {
      final slash = p.lastIndexOf('/');
      if (slash <= 0) break;
      p = p.substring(0, slash);
      index[p] = (index[p] ?? 0) + i.size;
    }
  }
  return index;
});

/// Bytes of not-yet-reclaimed Tier-1 items living *under* the given path
/// (exclusive). Lets the treemap show "65 MB reclaimable inside" on a plain
/// folder whose subtree contains flagged items.
final reclaimableUnderProvider = Provider.autoDispose.family<int, String>((
  ref,
  path,
) {
  return ref.watch(reclaimableIndexProvider)[path] ?? 0;
});

/// Node ids ticked in the insights sheet.
class InsightSelectionController extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    ref.watch(insightsProvider);
    return const {};
  }

  void toggle(int id) => state =
      state.contains(id) ? ({...state}..remove(id)) : {...state, id};

  void setMany(Iterable<int> ids, bool selected) => state =
      selected ? {...state, ...ids} : ({...state}..removeAll(ids));

  void clear() => state = const {};
}

final insightSelectionProvider =
    NotifierProvider<InsightSelectionController, Set<int>>(
        InsightSelectionController.new);

/// AI analysis lifecycle. `null` data = not run yet for this scan.
class AiAnalysisController extends AsyncNotifier<List<AiRecommendation>?> {
  @override
  Future<List<AiRecommendation>?> build() async {
    ref.watch(scanControllerProvider);
    return null;
  }

  Future<void> analyze() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(runAiAnalysis);
  }
}

final aiAnalysisProvider =
    AsyncNotifierProvider<AiAnalysisController, List<AiRecommendation>?>(
        AiAnalysisController.new);
