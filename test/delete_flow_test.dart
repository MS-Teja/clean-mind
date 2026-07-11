import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mind/features/insights/delete_flow.dart';
import 'package:clean_mind/src/rust/api/scan.dart';
import 'package:clean_mind/util/platform.dart';

FsNode file(int id, String name) {
  return FsNode(
    id: id,
    name: name,
    path: name,
    kind: FsKind.file,
    size: 2048,
    logicalSize: 2048,
    mtime: 0,
    fileCount: 1,
    dirCount: 0,
    itemCount: 0,
    childCount: 0,
    tier: FsTier.safe,
  );
}

/// Hosts a button that opens one of the delete dialogs. The tests only ever
/// dismiss the dialogs (Cancel / gate checks) — confirming would call into
/// the Rust bridge, which isn't loaded in a widget test.
Widget host(
  Future<void> Function(BuildContext, WidgetRef, List<FsNode>) flow,
) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => flow(context, ref, [file(1, 'old.bin')]),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('trash dialog is cancellable', (tester) async {
    await tester.pumpWidget(host(confirmAndTrash));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Move to $trashName?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Move to $trashName?'), findsNothing);
  });

  testWidgets('permanent delete is gated behind typing DELETE',
      (tester) async {
    await tester.pumpWidget(host(confirmAndDeletePermanently));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently?'), findsOneWidget);

    FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete forever'));
    expect(confirm().onPressed, isNull,
        reason: 'enabled before anything was typed');

    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull,
        reason: 'the gate must be exact, not case-insensitive');

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently?'), findsNothing);
  });
}
