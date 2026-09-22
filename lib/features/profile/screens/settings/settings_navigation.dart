import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/features/profile/screens/settings/settings_dialog.dart';
import 'package:mangabaka_app/features/profile/screens/settings_category_screen.dart';
import 'package:mangabaka_app/features/profile/screens/settings_screen.dart';

/// A settings category's content, for a host that shows categories inline.
class SettingsCategoryContent {
  final String title;
  final Widget content;

  const SettingsCategoryContent({required this.title, required this.content});
}

/// Placed above a settings page that shows categories inline rather than
/// navigating to them — the desktop settings page, whose categories open in
/// its right-hand pane.
///
/// [showOrNavigate] hands categories to the nearest host instead of pushing a
/// screen or a dialog page.
class InlineSettingsHost extends InheritedWidget {
  final ValueChanged<SettingsCategoryContent> onOpen;

  const InlineSettingsHost({
    super.key,
    required this.onOpen,
    required super.child,
  });

  static InlineSettingsHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InlineSettingsHost>();

  @override
  bool updateShouldNotify(InlineSettingsHost oldWidget) => false;
}

/// Opens a settings category the way the current layout calls for.
///
/// Portrait pushes a full screen. Landscape keeps the user inside the settings
/// dialog and slides the category in as a new page on the dialog's own stack —
/// pushing a route there would put a full-screen page on top of a dialog,
/// which reads as the dialog having vanished.
///
/// [listenable] rebuilds the category when the settings it displays change;
/// pass null for a category whose rows are all static.
void showOrNavigate(
  BuildContext context, {
  required String title,
  Listenable? listenable,
  required List<Widget> Function(BuildContext) buildChildren,
}) {
  final host = InlineSettingsHost.maybeOf(context);
  final isLandscape =
      host == null &&
      MediaQuery.orientationOf(context) == Orientation.landscape;

  Widget buildInner(BuildContext ctx) {
    final children = buildChildren(ctx);
    // In the dialog the category is already inside a scrolling shell with its
    // own header, so it contributes just the rows.
    return isLandscape || host != null
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : SettingsCategoryScreen(title: title, children: children);
  }

  final content = listenable != null
      ? ListenableBuilder(
          listenable: listenable,
          builder: (ctx, _) => buildInner(ctx),
        )
      : Builder(builder: buildInner);

  if (host != null) {
    host.onOpen(SettingsCategoryContent(title: title, content: content));
    return;
  }

  if (!isLandscape) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => content));
    return;
  }

  final dialogState = SettingsDialog.of(context);
  if (dialogState != null) {
    dialogState.pushCategory(title, content);
    return;
  }

  _showAsStandaloneDialog(context, title: title, content: content);
}

/// Fallback for a landscape category opened from outside the settings dialog.
///
/// The current dialog is dismissed first and the replacement is deferred to
/// the next frame, so the two do not overlap during the pop animation. Going
/// "back" from it reopens the settings root, since there is no dialog stack to
/// return to.
void _showAsStandaloneDialog(
  BuildContext context, {
  required String title,
  required Widget content,
}) {
  Navigator.pop(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final rootContext = AppConstants.navigatorKey.currentContext;
    if (rootContext == null) return;
    SettingsCategoryScreen.showAsDialog(
      rootContext,
      title: title,
      content: content,
      onBack: () {
        final ctx = AppConstants.navigatorKey.currentContext;
        if (ctx != null) SettingsScreen.show(ctx);
      },
    );
  });
}
