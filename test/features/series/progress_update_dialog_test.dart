import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/series/widgets/progress_update_dialog.dart';
import 'package:mangabaka_app/features/series/widgets/rating_icon_button.dart';
import 'package:mangabaka_app/features/series/widgets/rating_selection_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
    await SettingsManager().init();
  });

  Future<void> openDialog(
    WidgetTester tester,
    Future<void> Function(int) onUpdate,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ProgressUpdateDialog(
                  initialValue: 2,
                  title: 'Update chapters',
                  maxValue: '12',
                  onUpdate: onUpdate,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('save awaits success and prevents duplicate submissions', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await openDialog(tester, (value) {
      calls++;
      expect(value, 2);
      return completion.future;
    });

    await tester.tap(find.text('Save'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(ProgressUpdateDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completion.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ProgressUpdateDialog), findsNothing);
  });

  testWidgets('failed save keeps the sheet open and reports an error', (
    tester,
  ) async {
    await openDialog(tester, (_) async => throw StateError('failed'));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressUpdateDialog), findsOneWidget);
    expect(find.text('failed_to_update'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('manual progress input accepts digits but not a minus sign', (
    tester,
  ) async {
    int? submitted;
    await openDialog(tester, (value) async => submitted = value);

    await tester.enterText(find.byType(TextField), '-3');
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted, 3);
  });

  testWidgets('empty progress disables save and cannot submit a stale value', (
    tester,
  ) async {
    var calls = 0;
    await openDialog(tester, (_) async => calls++);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(calls, 0);
  });

  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  };

  for (final entry in palettes.entries) {
    testWidgets('${entry.key} progress and rating sheets use semantic colors', (
      tester,
    ) async {
      final palette = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => ProgressUpdateDialog(
                    initialValue: 2,
                    title: 'Update chapters',
                    maxValue: '12',
                    onUpdate: (_) async {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ProgressUpdateDialog),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((sheet.decoration as BoxDecoration).color, palette.surface);
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.style!.backgroundColor!.resolve({}), palette.accent);
      expect(save.style!.foregroundColor!.resolve({}), palette.onAccent);
      expect(
        MbPalette.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).style?.color,
        palette.text,
      );
      final progressIcon = tester.widget<Icon>(
        find.byIcon(Icons.menu_book_rounded),
      );
      final iconBackground = Color.alphaBlend(
        palette.accent.withValues(alpha: 0.1),
        palette.surface,
      );
      expect(
        MbPalette.contrastRatio(progressIcon.color!, iconBackground),
        greaterThanOrEqualTo(4.5),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      final disabledSave = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(disabledSave.onPressed, isNull);
      expect(
        disabledSave.style!.backgroundColor!.resolve({WidgetState.disabled}),
        palette.surfaceRaised,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: RatingIconButton(currentRating: 40, onRatingChanged: (_) {}),
          ),
        ),
      );
      final ratingButton = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RatingIconButton),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((ratingButton.decoration as BoxDecoration).color, palette.surface);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      final ratingSheet = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(RatingSelectionDialog),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((ratingSheet.decoration as BoxDecoration).color, palette.surface);
      final star = tester.widget<Icon>(find.byIcon(Icons.star_rounded));
      final starBackground = Color.alphaBlend(
        palette.star.withValues(alpha: 0.1),
        palette.surface,
      );
      expect(
        MbPalette.contrastRatio(star.color!, starBackground),
        greaterThanOrEqualTo(3),
      );
      final sliderTheme = tester.widget<SliderTheme>(
        find.byType(SliderTheme).last,
      );
      expect(
        MbPalette.contrastRatio(
          sliderTheme.data.activeTrackColor!,
          palette.surface,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('live theme changes retain progress input and submitting state', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => ProgressUpdateDialog(
                    initialValue: 2,
                    title: 'Update chapters',
                    maxValue: '12',
                    onUpdate: (value) {
                      calls++;
                      expect(value, 7);
                      return completion.future;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '3',
    );
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2',
    );
    await tester.enterText(find.byType(TextField), '7');
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(find.byType(ProgressUpdateDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '7',
    );
    final sheet = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ProgressUpdateDialog),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (sheet.decoration as BoxDecoration).color,
      EirenYuPalette.light.surface,
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 1);
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, EirenYuPalette.light.onAccent);
    expect(
      MbPalette.contrastRatio(spinner.color!, EirenYuPalette.light.accent),
      greaterThanOrEqualTo(4.5),
    );
    palette.value = EirenYuPalette.dark;
    await tester.pump();
    expect(calls, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ProgressUpdateDialog), findsNothing);
  });

  testWidgets('rating selection and cancel survive a live theme switch', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    var calls = 0;
    int? saved;
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: RatingIconButton(
              currentRating: 40,
              onRatingChanged: (value) {
                calls++;
                saved = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(75);
    await tester.pump();
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(find.byType(RatingSelectionDialog), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 75);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(80);
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(saved, 80);
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('tracking sheets fit $size without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() => tester.view.reset());
      await openDialog(tester, (_) async {});
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            showTooltips: true,
            palette: EirenYuPalette.light,
          ),
          home: Scaffold(
            body: RatingIconButton(currentRating: 40, onRatingChanged: (_) {}),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Update'));
      expect(tester.takeException(), isNull);
    });
  }
}
