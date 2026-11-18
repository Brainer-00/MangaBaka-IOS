import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/profile/widgets/dialogs/content_preferences_dialog.dart';
import 'package:mangabaka_app/features/profile/widgets/dialogs/list_style_dialogs.dart';
import 'package:mangabaka_app/features/profile/widgets/dialogs/logout_dialog.dart';
import 'package:mangabaka_app/features/profile/widgets/dialogs/selection_bottom_sheet.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/list_scope_tab_selector.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/list_style_preview_item.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/list_style_preview_thumbnails.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/settings_stepper_row.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/list_customization_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
  });

  Future<void> pumpShell(
    WidgetTester tester,
    ValueNotifier<MbPalette> palette,
    Widget Function(BuildContext) child,
  ) => tester.pumpWidget(
    ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (_, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(body: Builder(builder: child)),
      ),
    ),
  );

  final palettes = [
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets('scope tabs and thumbnail roles follow live palettes', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(palettes.first);
    final selected = ValueNotifier<ListScopeTab>(ListScopeTab.library);
    addTearDown(palette.dispose);
    addTearDown(selected.dispose);
    await pumpShell(
      tester,
      palette,
      (_) => Column(
        children: [
          ValueListenableBuilder<ListScopeTab>(
            valueListenable: selected,
            builder: (_, tab, _) => ListScopeTabSelector(
              active: tab,
              libraryLabel: 'Library',
              browseLabel: 'Browse',
              onChanged: (next) => selected.value = next,
            ),
          ),
          SizedBox(
            height: 200,
            child: ListStylePreviewItem(
              style: AppListStyle.comfortable,
              isSelected: true,
              label: 'Comfortable',
              onTap: () {},
            ),
          ),
        ],
      ),
    );
    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      final indicator = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ListScopeTabSelector),
              matching: find.byType(Container),
            )
            .at(1),
      );
      final indicatorColor = (indicator.decoration! as BoxDecoration).color!;
      expect(
        MbPalette.contrastRatio(indicatorColor, colors.surface),
        greaterThanOrEqualTo(3),
      );
      final labels = tester
          .widgetList<AnimatedDefaultTextStyle>(
            find.descendant(
              of: find.byType(ListScopeTabSelector),
              matching: find.byType(AnimatedDefaultTextStyle),
            ),
          )
          .toList();
      expect(
        MbPalette.contrastRatio(
          labels[selected.value.isLibrary ? 0 : 1].style.color!,
          indicatorColor,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MbPalette.contrastRatio(
          labels[selected.value.isLibrary ? 1 : 0].style.color!,
          colors.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final preview = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ListStylePreviewItem),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((preview.decoration! as BoxDecoration).color, colors.background);
      expect(find.byType(ListStylePreviewThumbnails), findsOneWidget);
      final thumbnailColors = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ListStylePreviewThumbnails),
              matching: find.byType(Container),
            ),
          )
          .map(
            (container) => (container.decoration is BoxDecoration)
                ? (container.decoration! as BoxDecoration).color
                : container.color,
          )
          .toList();
      expect(thumbnailColors, contains(colors.surface));
      expect(thumbnailColors, contains(colors.surfaceRaised));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Browse'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(selected.value, ListScopeTab.browse);
  });

  testWidgets('selection sheet stays open and selected through theme change', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    String? chosen;
    await pumpShell(
      tester,
      palette,
      (context) => TextButton(
        onPressed: () => SelectionBottomSheet.showSelectionBottomSheet<String>(
          context: context,
          title: 'Pick one',
          subtitle: 'Choose a value',
          options: ['First', 'Second'],
          currentValue: 'First',
          getLabel: (value) => value,
          onSelected: (value) => chosen = value,
        ),
        child: const Text('Open'),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      expect(find.text('First'), findsOneWidget);
      final row = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('First'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final actualBackground = Color.alphaBlend(
        colors.accent.withValues(alpha: 0.14),
        colors.surface,
      );
      expect(
        (row.decoration! as BoxDecoration).color,
        colors.accent.withValues(alpha: 0.14),
      );
      final label = tester.widget<Text>(find.text('First'));
      expect(
        MbPalette.contrastRatio(label.style!.color!, actualBackground),
        greaterThanOrEqualTo(4.5),
      );
      final inactive = tester.widget<Text>(find.text('Second'));
      expect(
        MbPalette.contrastRatio(inactive.style!.color!, colors.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(chosen, 'Second');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'content preferences sheet retains settings while theme changes',
    (tester) async {
      final settings = SettingsManager();
      await settings.setContentPreferences(['safe']);
      tester.view.physicalSize = const Size(620, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(palettes.first);
      addTearDown(palette.dispose);
      await pumpShell(
        tester,
        palette,
        (context) => TextButton(
          onPressed: () =>
              ContentPreferencesDialogs.showContentPreferencesDialog(context),
          child: const Text('Open'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final colors in palettes.take(3)) {
        palette.value = colors;
        await tester.pump();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(settings.contentPreferences, ['safe']);
        final sheet = tester.widget<Container>(
          find
              .ancestor(
                of: find.text(
                  LocalizationService()
                      .translate('content_preferences')
                      .toUpperCase(),
                ),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((sheet.decoration! as BoxDecoration).color, colors.surface);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(
        find.text(LocalizationService().translate('suggestive')),
      );
      await tester.tap(
        find.text(LocalizationService().translate('suggestive')),
      );
      await tester.pump();
      expect(settings.contentPreferences, contains('suggestive'));
      tester.view.physicalSize = const Size(280, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('list style sheet recolors without losing its current value', (
    tester,
  ) async {
    final settings = SettingsManager();
    await settings.setListStyle(AppListStyle.compact);
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    await pumpShell(
      tester,
      palette,
      (context) => TextButton(
        onPressed: () => ListStyleDialogs.showListStyleSelectionDialog(context),
        child: const Text('Open'),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final colors in palettes.take(3)) {
      palette.value = colors;
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(settings.currentListStyle, AppListStyle.compact);
      expect(find.byType(ListStylePreviewItem), findsWidgets);
      final sheet = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(LocalizationService().translate('list_style')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((sheet.decoration! as BoxDecoration).color, colors.surface);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is ListStylePreviewItem && w.style == AppListStyle.comfortable,
      ),
    );
    await tester.pump();
    expect(settings.currentListStyle, AppListStyle.comfortable);
  });

  testWidgets('logout dialog recolors and returns Cancel or Confirm only', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    bool? result;
    await pumpShell(
      tester,
      palette,
      (context) => TextButton(
        onPressed: () async =>
            result = await LogoutDialog.showLogoutConfirmationDialog(context),
        child: const Text('Open'),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final colors in palettes.take(3)) {
      palette.value = colors;
      await tester.pump();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, colors.surface);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      final foreground = confirm.style!.foregroundColor!.resolve({})!;
      final background = confirm.style!.backgroundColor!.resolve({})!;
      expect(
        MbPalette.contrastRatio(foreground, background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pump();
    await tester.tap(find.text(LocalizationService().translate('cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('stepper distinguishes enabled and disabled controls', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    int value = 0;
    await pumpShell(
      tester,
      palette,
      (_) => SettingsStepperRow(
        label: 'Columns',
        value: value,
        min: 0,
        max: 1,
        onChanged: (next) => value = next,
      ),
    );
    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      final buttons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .toList();
      expect(buttons.first.onPressed, isNull);
      expect(buttons.last.onPressed, isNotNull);
      expect(buttons.first.disabledColor, isNot(buttons.last.color));
      expect(
        MbPalette.contrastRatio(buttons.last.color!, colors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    expect(value, 1);
  });
}
