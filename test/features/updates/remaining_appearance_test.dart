import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/collections/screens/collection_detail_screen.dart';
import 'package:mangabaka_app/features/collections/services/collection_service.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';
import 'package:mangabaka_app/features/staff/models/staff.dart';
import 'package:mangabaka_app/features/staff/widgets/staff_list_item.dart';
import 'package:mangabaka_app/features/updates/models/app_release.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/features/updates/widgets/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UpdateService extends Fake implements UpdateService {
  @override
  bool get supportsInAppUpdate => true;
}

class _CollectionService extends Fake implements CollectionService {
  int calls = 0;
  @override
  Future<PagedList<SeriesWork>> fetchCollectionWorks(
    String collectionId, {
    int page = 1,
    int limit = 30,
  }) async {
    calls++;
    return PagedList([
      SeriesWork(
        id: '1',
        subTitle: 'Volume One',
        countType: 'volume',
        releaseDate: '2024',
        sequenceString: '1',
        pages: 100,
        priceString: '10 USD',
      ),
    ], hasNext: false);
  }
}

const _release = AppRelease(
  tagName: 'v2.0.0',
  name: 'Version 2',
  body: 'Release notes',
  htmlUrl: 'https://github.com/example/release',
  draft: false,
  prerelease: false,
  assets: [],
);

final _collection = SeriesCollection(
  id: 'collection-1',
  title: 'Collection',
  format: 'tankobon',
  type: 'manga',
  status: 'ongoing',
  medium: 'print',
  publisherName: 'Publisher',
  editionName: 'Standard',
  countMain: 1,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    await resetServiceLocator();
  });
  tearDown(() async => resetServiceLocator());

  final palettes = [
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  ];

  for (var index = 0; index < palettes.length; index++) {
    final palette = palettes[index];
    testWidgets('update dialog uses readable palette $index', (tester) async {
      getIt.registerSingleton<UpdateService>(_UpdateService());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: const Scaffold(body: UpdateDialog(release: _release)),
        ),
      );
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, palette.surface);
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.system_update_rounded),
      );
      final badge = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.system_update_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      final badgeColor = (badge.decoration! as BoxDecoration).color!;
      expect(
        MbPalette.contrastRatio(icon.color!, badgeColor),
        greaterThanOrEqualTo(3),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final fill = button.style!.backgroundColor!.resolve({})!;
      final foreground = button.style!.foregroundColor!.resolve({})!;
      expect(
        MbPalette.contrastRatio(foreground, fill),
        greaterThanOrEqualTo(4.5),
      );
      final busyFill = button.style!.backgroundColor!.resolve({
        WidgetState.disabled,
      })!;
      final busyText = button.style!.foregroundColor!.resolve({
        WidgetState.disabled,
      })!;
      expect(
        MbPalette.contrastRatio(busyText, busyFill),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text('Later'));
      await tester.pump();
    });

    testWidgets('staff card follows palette $index', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: StaffListItem(
              staff: Staff(
                id: 1,
                name: 'Staff',
                nativeName: 'Native',
                role: 'Author',
                seriesCount: 2,
              ),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.widget<Card>(find.byType(Card)).color, palette.surface);
      final role = tester.widget<Text>(find.text('Author'));
      expect(
        MbPalette.contrastRatio(role.style!.color!, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(find.byIcon(Icons.person), findsNothing);
      await tester.tap(find.text('Staff'));
      expect(taps, 1);
    });
  }

  testWidgets('collection works survive live palette change', (tester) async {
    final service = _CollectionService();
    getIt.registerSingleton<CollectionService>(service);
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, child) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: CollectionDetailScreen(collection: _collection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vol. 1'), findsOneWidget);
    expect(find.byIcon(Icons.book_outlined), findsOneWidget);
    expect(service.calls, 1);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      EirenYuPalette.dark.background,
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(find.text('Vol. 1'), findsOneWidget);
    expect(service.calls, 1);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      EirenYuPalette.light.background,
    );
    expect(
      tester.widget<Text>(find.text('10 USD')).style!.color,
      EirenYuPalette.light.textMuted,
    );
  });
}
