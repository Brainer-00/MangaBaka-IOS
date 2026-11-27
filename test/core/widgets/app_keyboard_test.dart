import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/widgets/app_keyboard.dart';
import 'package:mangabaka_app/core/widgets/guarded_draggable_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('touch, drag and route transitions release only editable focus', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    final text = TextEditingController();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(text.dispose);
    var accessoryTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [KeyboardRouteObserver()],
        scrollBehavior: const KeyboardScrollBehavior(),
        builder: (_, child) => AppKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('first'),
                controller: text,
                focusNode: first,
              ),
              TextField(key: const ValueKey('second'), focusNode: second),
              TextFieldTapRegion(
                child: TextButton(
                  onPressed: () => accessoryTaps++,
                  child: const Text('Accessory'),
                ),
              ),
              const SizedBox(height: 48, child: Center(child: Text('Outside'))),
              SizedBox(
                height: 48,
                child: ListView.builder(
                  key: const ValueKey('horizontal'),
                  scrollDirection: Axis.horizontal,
                  itemExtent: 180,
                  itemCount: 10,
                  itemBuilder: (_, i) => Text('Cover $i'),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemExtent: 80,
                  itemCount: 20,
                  itemBuilder: (_, i) => Text('Row $i'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('first')),
      'Retained query',
    );
    await tester.tap(find.text('Accessory'));
    await tester.pump();
    expect(first.hasFocus, isTrue);
    expect(accessoryTaps, 1);
    await tester.tap(find.text('Outside'));
    await tester.pump();
    expect(first.hasFocus, isFalse);
    await tester.tap(find.byKey(const ValueKey('first')));
    await tester.tap(find.byKey(const ValueKey('second')));
    await tester.pump();
    expect(second.hasFocus, isTrue);
    expect(first.hasFocus, isFalse);
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(second.hasFocus, isFalse);
    await tester.tap(find.byKey(const ValueKey('second')));
    await tester.pump();
    expect(second.hasFocus, isTrue);
    await tester.drag(
      find.byKey(const ValueKey('horizontal')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    expect(second.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('first')));
    await tester.pump();
    expect(first.hasFocus, isTrue);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Read only')),
      ),
    );
    await tester.pumpAndSettle();
    expect(first.hasFocus, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(first.hasFocus, isFalse);
    expect(text.text, 'Retained query');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('guarded sheet handles drag, discard and an in-flight save', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    LocalizationService.resetForTesting();
    await LocalizationService().init();
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                enableDrag: false,
                isDismissible: false,
                isScrollControlled: true,
                builder: (_) => _FixtureEditor(busy),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    );
    final handle = find.byKey(const ValueKey('editor_sheet_drag_handle'));
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(handle, findsOneWidget);
    expect(
      tester.getCenter(handle).dx,
      tester.getCenter(find.byType(BottomSheet)).dx,
    );
    busy.value = true;
    await tester.pump();
    await tester.drag(handle, const Offset(0, 330));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handle, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    busy.value = false;
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.drag(handle, const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(handle, findsNothing);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    final form = find.byType(SingleChildScrollView);
    await tester.dragFrom(
      tester.getTopLeft(form) + const Offset(200, 120),
      const Offset(0, 370),
    );
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
  });
}

class _FixtureEditor extends StatefulWidget {
  const _FixtureEditor(this.busy);
  final ValueNotifier<bool> busy;

  @override
  State<_FixtureEditor> createState() => _FixtureEditorState();
}

class _FixtureEditorState extends State<_FixtureEditor>
    with EditorDismissal<_FixtureEditor> {
  final text = TextEditingController();
  @override
  bool get exitLocked => widget.busy.value;
  @override
  bool get hasPendingEdits => text.text.isNotEmpty;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.busy,
    builder: (context, _, _) => guardEditorDismissal(
      GuardedDraggableSheet(
        openExtent: .64,
        dismissExtent: .28,
        canDrag: () => !exitLocked,
        onDismiss: requestEditorDismissal,
        builder: (_, scroll, handle) => Column(
          children: [
            ?handle,
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    TextField(controller: text),
                    const SizedBox(height: 185),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
