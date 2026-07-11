import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mind/features/insights/insights_providers.dart';
import 'package:clean_mind/features/results/tree_providers.dart';
import 'package:clean_mind/src/rust/api/insights.dart';
import 'package:clean_mind/src/rust/api/scan.dart';

Insight insight(
  String path,
  int size, {
  int nodeId = 1,
  FsTier tier = FsTier.safe,
}) {
  return Insight(
    nodeId: nodeId,
    path: path,
    size: size,
    tier: tier,
    ruleId: 'js.node_modules',
    ruleName: 'node_modules',
    category: 'Dependencies',
    regenerability: 'regenerable',
    regenerateWith: 'npm install',
    explanation: 'Reinstalled from the lockfile.',
    staleDays: 10,
  );
}

ProviderContainer container(List<Insight> insights) {
  final c = ProviderContainer(
    overrides: [insightsProvider.overrideWithValue(insights)],
  );
  addTearDown(c.dispose);
  return c;
}

/// The pre-index semantics: bytes of safe, not-deleted insights strictly
/// *under* [path]. The index must match this exactly.
int naiveUnder(List<Insight> insights, Set<int> deleted, String path) =>
    insights
        .where((i) =>
            i.tier == FsTier.safe &&
            !deleted.contains(i.nodeId) &&
            i.path.startsWith('$path/'))
        .fold(0, (sum, i) => sum + i.size);

void main() {
  group('reclaimableIndexProvider', () {
    test('credits every strict ancestor, never the node itself', () {
      final c = container([insight('a/b/c/node_modules', 100)]);
      final index = c.read(reclaimableIndexProvider);
      expect(index, {'a/b/c': 100, 'a/b': 100, 'a': 100});
      expect(index.containsKey('a/b/c/node_modules'), isFalse);
    });

    test('aggregates insights that share ancestors', () {
      final c = container([
        insight('a/x/node_modules', 100, nodeId: 1),
        insight('a/y/target', 40, nodeId: 2),
      ]);
      final index = c.read(reclaimableIndexProvider);
      expect(index['a'], 140);
      expect(index['a/x'], 100);
      expect(index['a/y'], 40);
    });

    test('excludes review-tier insights and reclaimed nodes', () {
      final c = container([
        insight('a/node_modules', 100, nodeId: 1),
        insight('a/maybe', 50, nodeId: 2, tier: FsTier.review),
        insight('a/target', 30, nodeId: 3),
      ]);
      c.read(deletedIdsProvider.notifier).markDeleted([3]);
      expect(c.read(reclaimableIndexProvider), {'a': 100});
    });

    test('a top-level insight credits nothing (no strict ancestor)', () {
      final c = container([insight('node_modules', 100)]);
      expect(c.read(reclaimableIndexProvider), isEmpty);
    });

    test('matches the naive strict-descendant scan on a mixed tree', () {
      final insights = [
        insight('p/app/node_modules', 120, nodeId: 1),
        insight('p/app/web/node_modules', 80, nodeId: 2),
        insight('p/svc/target', 200, nodeId: 3),
        insight('p/svc/target/debug', 60, nodeId: 4, tier: FsTier.review),
        insight('caches/pip', 30, nodeId: 5),
      ];
      final c = container(insights);
      c.read(deletedIdsProvider.notifier).markDeleted([2]);
      final deleted = c.read(deletedIdsProvider);
      final index = c.read(reclaimableIndexProvider);
      for (final prefix in [
        'p',
        'p/app',
        'p/app/web',
        'p/svc',
        'p/svc/target',
        'caches',
        'unrelated',
      ]) {
        expect(index[prefix] ?? 0, naiveUnder(insights, deleted, prefix),
            reason: 'mismatch under "$prefix"');
      }
    });
  });

  group('reclaimableUnderProvider', () {
    test('reads the index and defaults to zero', () {
      final c = container([insight('a/b/node_modules', 100)]);
      expect(c.read(reclaimableUnderProvider('a/b')), 100);
      expect(c.read(reclaimableUnderProvider('nowhere')), 0);
    });
  });

  group('reclaimableTotalProvider', () {
    test('sums safe insights and drops reclaimed ones', () {
      final c = container([
        insight('a/node_modules', 100, nodeId: 1),
        insight('b/target', 50, nodeId: 2),
        insight('c/maybe', 999, nodeId: 3, tier: FsTier.review),
      ]);
      expect(c.read(reclaimableTotalProvider), 150);
      c.read(deletedIdsProvider.notifier).markDeleted([1]);
      expect(c.read(reclaimableTotalProvider), 50);
    });
  });

  group('InsightSelectionController', () {
    test('toggle, setMany, and clear', () {
      final c = container([insight('a/node_modules', 100)]);
      final sel = c.read(insightSelectionProvider.notifier);
      sel.toggle(1);
      sel.toggle(2);
      expect(c.read(insightSelectionProvider), {1, 2});
      sel.toggle(1);
      expect(c.read(insightSelectionProvider), {2});
      sel.setMany([3, 4], true);
      expect(c.read(insightSelectionProvider), {2, 3, 4});
      sel.setMany([2, 3], false);
      expect(c.read(insightSelectionProvider), {4});
      sel.clear();
      expect(c.read(insightSelectionProvider), isEmpty);
    });
  });
}
