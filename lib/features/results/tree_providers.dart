import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../scan/scan_providers.dart';

const treemapChildLimit = 40;

/// Breadcrumb trail: root → current focus. Rebuilt from scratch per scan.
class FocusTrailController extends Notifier<List<FsNode>> {
  @override
  List<FsNode> build() {
    final scan = ref.watch(scanControllerProvider);
    if (scan is ScanDone) {
      final root = getNode(id: scan.rootId);
      return [?root];
    }
    return const [];
  }

  void drillInto(FsNode node) => state = [...state, node];

  void popTo(int index) => state = state.sublist(0, index + 1);
}

final focusTrailProvider =
    NotifierProvider<FocusTrailController, List<FsNode>>(
        FocusTrailController.new);

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

/// Node highlighted in the details side panel.
class SelectedNodeController extends Notifier<FsNode?> {
  @override
  FsNode? build() {
    ref.watch(focusTrailProvider);
    return null;
  }

  void select(FsNode? node) => state = node;
}

final selectedNodeProvider =
    NotifierProvider<SelectedNodeController, FsNode?>(
        SelectedNodeController.new);

/// Node ids the user already sent to the trash this session (grayed out).
class DeletedIdsController extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    ref.watch(scanControllerProvider);
    return const {};
  }

  void markDeleted(Iterable<int> ids) => state = {...state, ...ids};
}

final deletedIdsProvider =
    NotifierProvider<DeletedIdsController, Set<int>>(DeletedIdsController.new);
