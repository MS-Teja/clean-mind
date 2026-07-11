import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mind/features/results/tree_providers.dart';
import 'package:clean_mind/src/rust/api/scan.dart';

FsNode dir(int id, String name) {
  return FsNode(
    id: id,
    name: name,
    path: name,
    kind: FsKind.dir,
    size: 1000,
    logicalSize: 1000,
    mtime: 0,
    fileCount: 1,
    dirCount: 1,
    itemCount: 0,
    childCount: 1,
    tier: FsTier.none,
  );
}

ProviderContainer container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('FocusTrailController', () {
    test('drill, back, and forward follow browser semantics', () {
      final c = container();
      final trail = c.read(focusTrailProvider.notifier);
      expect(c.read(focusTrailProvider), isEmpty);
      expect(trail.canGoBack, isFalse);
      expect(trail.canGoForward, isFalse);

      final (a, b) = (dir(1, 'a'), dir(2, 'b'));
      trail.drillInto(a);
      trail.drillInto(b);
      expect(c.read(focusTrailProvider), [a, b]);
      expect(trail.canGoBack, isTrue);

      trail.goBack();
      expect(c.read(focusTrailProvider), [a]);
      expect(trail.canGoForward, isTrue);

      trail.goForward();
      expect(c.read(focusTrailProvider), [a, b]);
      expect(trail.canGoForward, isFalse);
    });

    test('a new drill after going back drops the forward history', () {
      final c = container();
      final trail = c.read(focusTrailProvider.notifier);
      final (a, b, x) = (dir(1, 'a'), dir(2, 'b'), dir(3, 'x'));
      trail.drillInto(a);
      trail.drillInto(b);
      trail.goBack();
      trail.drillInto(x);
      expect(c.read(focusTrailProvider), [a, x]);
      expect(trail.canGoForward, isFalse);
      trail.goBack();
      expect(c.read(focusTrailProvider), [a]);
    });

    test('popTo truncates the trail to the tapped crumb', () {
      final c = container();
      final trail = c.read(focusTrailProvider.notifier);
      final (a, b, x) = (dir(1, 'a'), dir(2, 'b'), dir(3, 'x'));
      trail.drillInto(a);
      trail.drillInto(b);
      trail.drillInto(x);
      trail.popTo(0);
      expect(c.read(focusTrailProvider), [a]);
      // popTo is a new visit, not a rewind: Back returns to the deep trail.
      expect(trail.canGoForward, isFalse);
      trail.goBack();
      expect(c.read(focusTrailProvider), [a, b, x]);
    });

    test('every navigation clears the side-panel selection', () {
      final c = container();
      final trail = c.read(focusTrailProvider.notifier);
      final selected = c.read(selectedNodeProvider.notifier);
      final (a, b) = (dir(1, 'a'), dir(2, 'b'));

      void expectCleared(void Function() navigate) {
        selected.select(a);
        expect(c.read(selectedNodeProvider), a);
        navigate();
        expect(c.read(selectedNodeProvider), isNull,
            reason: 'selection must not survive navigation');
      }

      expectCleared(() => trail.drillInto(a)); // [a]
      expectCleared(() => trail.drillInto(b)); // [a, b]
      expectCleared(() => trail.goBack()); // [a]
      expectCleared(() => trail.goForward()); // [a, b]
      expectCleared(() => trail.popTo(0)); // [a]
    });
  });

  group('SearchQueryController', () {
    test('debounces typing and keeps only the last value', () async {
      final c = container();
      final search = c.read(searchQueryProvider.notifier);
      search.set('no');
      search.set('node');
      expect(c.read(searchQueryProvider), '',
          reason: 'query must not land before the debounce window');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.read(searchQueryProvider), 'node');
    });

    test('clearing takes effect immediately', () async {
      final c = container();
      final search = c.read(searchQueryProvider.notifier);
      search.set('node');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.read(searchQueryProvider), 'node');
      search.set('');
      expect(c.read(searchQueryProvider), '');
    });

    test('a clear cancels a pending debounced query', () async {
      final c = container();
      final search = c.read(searchQueryProvider.notifier);
      search.set('node');
      search.set('');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.read(searchQueryProvider), '');
    });
  });

  group('DeletedIdsController', () {
    test('accumulates trashed ids across calls', () {
      final c = container();
      final deleted = c.read(deletedIdsProvider.notifier);
      deleted.markDeleted([1, 2]);
      deleted.markDeleted([2, 3]);
      expect(c.read(deletedIdsProvider), {1, 2, 3});
    });
  });
}
