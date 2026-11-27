import 'package:flutter/material.dart';

/// Text fields keep their own tap regions so accessories and selection work
/// while touch outside a field follows the same focus policy as a mouse tap.
class AppKeyboard extends StatelessWidget {
  const AppKeyboard({super.key, required this.child});

  final Widget child;

  static void dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorStateOfType<EditableTextState>() != null) {
      focus!.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
    },
    child: child,
  );
}

class KeyboardScrollBehavior extends MaterialScrollBehavior {
  const KeyboardScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;
}

class KeyboardRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null &&
        (route is PageRoute || route is ModalBottomSheetRoute)) {
      AppKeyboard.dismiss();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute) AppKeyboard.dismiss();
  }
}
