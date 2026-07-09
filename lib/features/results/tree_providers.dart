import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../src/rust/api/system.dart';
import '../scan/scan_providers.dart';

const treemapChildLimit = 40;

/// Breadcrumb trail: root → current focus. Rebuilt from scratch per scan.
///
/// Also keeps a linear visited-history with a cursor so the results screen can
/// offer browser-style Back/Forward. The trail is the *hierarchical* path;
/// history is the *temporal* sequence of trails the user has visited.
class FocusTrailController extends Notifier<List<FsNode>> {
  final List<List<FsNode>> _history = [];
  int _cursor = -1;

  @override
  List<FsNode> build() {
    final scan = ref.watch(scanControllerProvider);
    _history.clear();
    _cursor = -1;
    if (scan is ScanDone) {
      final root = getNode(id: scan.rootId);
      final trail = [?root];
      if (root != null) {
        _history.add(trail);
        _cursor = 0;
      }
      return trail;
    }
    return const [];
  }

  /// Record a new trail as the current history entry, dropping any forward
  /// entries (browser semantics).
  void _commit(List<FsNode> trail) {
    if (_cursor < _history.length - 1) {
      _history.removeRange(_cursor + 1, _history.length);
    }
    _history.add(trail);
    _cursor = _history.length - 1;
    state = trail;
  }

  void drillInto(FsNode node) {
    _commit([...state, node]);
    _clearSelection();
  }

  void popTo(int index) {
    _commit(state.sublist(0, index + 1));
    _clearSelection();
  }

  /// Jump to an arbitrary node by id (a search hit or a "largest items" tap).
  /// Focuses the node if it's a directory; otherwise focuses its parent and
  /// returns the node so the caller can select it in the panel.
  FsNode? navigateToId(int id) {
    final chain = nodeAncestry(id: id);
    if (chain.isEmpty) return null;
    final target = chain.last;
    if (target.kind == FsKind.dir) {
      _commit(chain);
      return null;
    }
    _commit(chain.sublist(0, chain.length - 1));
    return target;
  }

  bool get canGoBack => _cursor > 0;
  bool get canGoForward => _cursor >= 0 && _cursor < _history.length - 1;

  void goBack() {
    if (canGoBack) {
      state = _history[--_cursor];
      _clearSelection();
    }
  }

  void goForward() {
    if (canGoForward) {
      state = _history[++_cursor];
      _clearSelection();
    }
  }

  void _clearSelection() =>
      ref.read(selectedNodeProvider.notifier).select(null);
}

final focusTrailProvider = NotifierProvider<FocusTrailController, List<FsNode>>(
  FocusTrailController.new,
);

final focusNodeProvider = Provider<FsNode?>((ref) {
  final trail = ref.watch(focusTrailProvider);
  return trail.isEmpty ? null : trail.last;
});

/// Children of a node, largest first, bounded with a trailing Rest aggregate.
final childrenProvider = Provider.family<List<FsNode>, int>((ref, id) {
  // Recompute when the scan changes.
  ref.watch(scanControllerProvider);
  return getChildren(id: id, limit: treemapChildLimit);
});

/// Node highlighted in the details side panel. Reset only on a new scan;
/// navigation clears it explicitly via [FocusTrailController], so a
/// programmatic selection (e.g. a search hit) isn't clobbered by a trail change.
class SelectedNodeController extends Notifier<FsNode?> {
  @override
  FsNode? build() {
    ref.watch(scanControllerProvider);
    return null;
  }

  void select(FsNode? node) => state = node;
}

final selectedNodeProvider = NotifierProvider<SelectedNodeController, FsNode?>(
  SelectedNodeController.new,
);

/// Navigate the trail to `id` and reflect it in the details panel — focus a
/// directory, or focus a file's parent and select the file. Shared by search
/// results and the inspector's "largest items" list.
void revealNodeId(WidgetRef ref, int id) {
  final selected = ref.read(focusTrailProvider.notifier).navigateToId(id);
  ref.read(selectedNodeProvider.notifier).select(selected);
}

/// How the current directory is rendered in the results screen.
enum ResultsView { treemap, list }

final resultsViewProvider =
    NotifierProvider<ResultsViewController, ResultsView>(
      ResultsViewController.new,
    );

class ResultsViewController extends Notifier<ResultsView> {
  @override
  ResultsView build() => getUiPrefs().resultsView == 'list'
      ? ResultsView.list
      : ResultsView.treemap;

  void set(ResultsView v) {
    state = v;
    // Remember the choice across restarts.
    final p = getUiPrefs();
    setUiPrefs(
      prefs: UiPrefs(
        resultsView: v == ResultsView.list ? 'list' : 'treemap',
        sortKey: p.sortKey,
        sortAscending: p.sortAscending,
      ),
    );
  }
}

/// Whole-scan search query (empty = not searching). Cleared on a new scan.
class SearchQueryController extends Notifier<String> {
  Timer? _debounce;

  @override
  String build() {
    ref.watch(scanControllerProvider);
    ref.onDispose(() => _debounce?.cancel());
    return '';
  }

  void set(String q) {
    _debounce?.cancel();
    if (q.isEmpty) {
      // Clearing is instant — no need to wait out the debounce.
      state = q;
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), () => state = q);
    }
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

/// Results for the current search query, largest first. Empty when not
/// searching. Recomputes as the query or scan changes.
final searchResultsProvider = Provider<List<FsNode>>((ref) {
  ref.watch(scanControllerProvider);
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return const [];
  return searchNodes(query: q, limit: 200);
});

/// Node ids the user already sent to the trash this session (grayed out).
class DeletedIdsController extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    ref.watch(scanControllerProvider);
    return const {};
  }

  void markDeleted(Iterable<int> ids) => state = {...state, ...ids};
}

final deletedIdsProvider = NotifierProvider<DeletedIdsController, Set<int>>(
  DeletedIdsController.new,
);
