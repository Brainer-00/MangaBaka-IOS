import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banner.dart';
import 'package:mangabaka_app/features/library/widgets/library_search_bar.dart';
import 'package:mangabaka_app/features/library/widgets/library_tab_bar.dart';
import 'package:mangabaka_app/features/library/widgets/sync_progress_overlay.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';

class _FakeLibraryService extends Fake implements LibraryService {
  @override
  final syncStatus = ValueNotifier<LibrarySyncStatus>(
    const LibrarySyncStatus(isSyncing: true, currentEntries: 5),
  );
  bool cancelled = false;

  @override
  void cancelSync() => cancelled = true;
}

void main() {
  testWidgets(
    'Sync overlay uses readable palette roles and keeps Stop active',
    (tester) async {
      await resetServiceLocator();
      final service = _FakeLibraryService();
      getIt.registerSingleton<LibraryService>(service);
      addTearDown(() async {
        await resetServiceLocator();
        service.syncStatus.dispose();
      });
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: const Scaffold(
              body: Stack(children: [SyncProgressOverlay()]),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      palette.value = EirenYuPalette.light;
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SyncProgressOverlay), findsOneWidget);
      final stopLabel = LocalizationService().translate('stop');
      final stop = tester.widget<Text>(find.text(stopLabel));
      final stopBackground = Color.alphaBlend(
        palette.value.error.withValues(alpha: 0.12),
        palette.value.surface,
      );
      expect(
        MbPalette.contrastRatio(stop.style!.color!, stopBackground),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text(stopLabel));
      expect(service.cancelled, isTrue);
      service.syncStatus.value = const LibrarySyncStatus(
        error: 'Interrupted',
        currentEntries: 5,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Interrupted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Library search text and filters survive palette changes', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    String query = '';
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: LibrarySearchBar(
              onChanged: (value) => query = value,
              initialFilters: SearchFilters(type: ['manga']),
              showFilterButton: false,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'One Piece');
    expect(query, 'One Piece');
    for (final colors in [
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'One Piece');
      expect(field.style!.color, colors.text);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Library status tabs and banners remain readable across palettes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TabController(length: 8, vsync: const TestVSync());
      addTearDown(controller.dispose);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      const statusKeys = [
        'all',
        'reading',
        'paused',
        'completed',
        'plan_to_read',
        'dropped',
        'rereading',
        'considering',
      ];
      expect(
        AppConstants.getColorForState('considering'),
        const Color(0xFF9B8CF4),
      );
      expect(
        AppConstants.getColorForState('rereading'),
        const Color(0xFF4FA6C8),
      );
      expect(
        AppConstants.getColorForState('considering'),
        isNot(AppConstants.getColorForState('rereading')),
      );
      final counts = {
        for (var index = 0; index < statusKeys.length; index++)
          statusKeys[index]: index + 1,
      };
      final l10n = LocalizationService();

      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              appBar: AppBar(
                bottom: LibraryTabBar(
                  controller: controller,
                  counts: counts,
                  isLandscape: false,
                ),
              ),
              body: LibraryStatusBanner(
                message: 'Sync failed',
                icon: Icons.error_outline,
                color: colors.error,
              ),
            ),
          ),
        ),
      );

      for (final colors in [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        ThemePresets.byId('nord')!.dark!,
      ]) {
        palette.value = colors;
        await tester.pump();
        for (var index = 0; index < statusKeys.length; index++) {
          controller.animateTo(
            index,
            duration: const Duration(milliseconds: 1),
          );
          await tester.pumpAndSettle();
          final indicator =
              tester.widget<TabBar>(find.byType(TabBar)).indicator!
                  as BoxDecoration;
          final paused = statusKeys[index] == 'paused';
          final expected = paused
              ? const Color(0xFFFBD24B)
              : MbPalette.ensureContrast(
                  statusKeys[index] == 'all'
                      ? EirenYuPalette.crimsonMoon
                      : AppConstants.getColorForState(statusKeys[index]),
                  colors.background,
                  minimum: 3.0,
                );
          expect(indicator.color, expected);
          expect(
            MbPalette.contrastRatio(
              (indicator.border as Border?)?.top.color ?? indicator.color!,
              colors.background,
            ),
            greaterThanOrEqualTo(3.0),
          );
          final selected = tester.widget<Text>(
            find.text(l10n.translate(statusKeys[index]).toUpperCase()),
          );
          expect(
            MbPalette.contrastRatio(selected.style!.color!, indicator.color!),
            greaterThanOrEqualTo(4.5),
          );
          final count = tester.widget<Text>(find.text('${index + 1}'));
          expect(
            MbPalette.contrastRatio(count.style!.color!, indicator.color!),
            greaterThanOrEqualTo(4.5),
          );
          final inactiveIndex = (index + 1) % statusKeys.length;
          final inactive = tester.widget<Text>(
            find.text(l10n.translate(statusKeys[inactiveIndex]).toUpperCase()),
          );
          expect(
            MbPalette.contrastRatio(inactive.style!.color!, colors.background),
            greaterThanOrEqualTo(4.5),
          );
        }
        final banner = tester.widget<Text>(find.text('Sync failed'));
        final bannerBackground = Color.alphaBlend(
          colors.error.withValues(alpha: 0.12),
          colors.background,
        );
        expect(
          MbPalette.contrastRatio(banner.style!.color!, bannerBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      }

      palette.value = EirenYuPalette.light;
      controller.animateTo(0, duration: const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      controller.animateTo(1, duration: const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final midpoint =
          (tester.widget<TabBar>(find.byType(TabBar)).indicator!
                  as BoxDecoration)
              .color!;
      final expectedMidpoint = MbPalette.ensureContrast(
        Color.lerp(
          EirenYuPalette.crimsonMoon,
          AppConstants.getColorForState('reading'),
          controller.animation!.value,
        )!,
        EirenYuPalette.light.background,
        minimum: 3.0,
      );
      expect(midpoint, expectedMidpoint);
      expect(
        MbPalette.contrastRatio(midpoint, EirenYuPalette.light.background),
        greaterThanOrEqualTo(3.0),
      );
      for (final (index, key) in [(0, 'all'), (1, 'reading')]) {
        final weight = (1.0 - (controller.animation!.value - index).abs())
            .clamp(0.0, 1.0);
        final swipeBackground = Color.alphaBlend(
          midpoint.withValues(alpha: weight),
          palette.value.background,
        );
        final text = tester.widget<Text>(
          find.text(l10n.translate(key).toUpperCase()),
        );
        expect(
          MbPalette.contrastRatio(text.style!.color!, swipeBackground),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(700, 320);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    },
  );
}
