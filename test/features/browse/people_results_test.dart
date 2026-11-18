import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/browse/models/browse_type.dart';
import 'package:mangabaka_app/features/browse/widgets/results/browse_content.dart';
import 'package:mangabaka_app/features/publisher/models/publisher.dart';
import 'package:mangabaka_app/features/publisher/widgets/publisher_list_item.dart';
import 'package:mangabaka_app/features/staff/models/staff.dart';
import 'package:mangabaka_app/features/staff/widgets/staff_list_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

Publisher _publisher(int i) => Publisher(
  id: '$i',
  type: 'company',
  subType: 'publisher',
  aliases: const [],
  name: 'Publisher $i',
  founded: 1990,
  description: 'A publisher of comics.',
);

Widget _content(BrowseType type, List<dynamic> results) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          BrowseContent(
            searchResults: results,
            browseType: type,
            isLoading: false,
            isLoadingMore: false,
            error: null,
            scrollController: ScrollController(),
            onRetry: () {},
            onNavigateToDetail: (_) {},
            onNavigateToResults: (_, _, {type, staff, publisher}) {},
            onNavigateToMix: () {},
            onNavigateToDiscoveryQueue: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    await resetServiceLocator();
  });

  tearDown(() => DesktopLayout.debugOverride = null);

  group('list items', () {
    final palettes = [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
      ThemePresets.byId('catppuccin')!.light!,
      EirenYuPalette.light.withAccent(const Color(0xFF808080)),
    ];
    for (var index = 0; index < palettes.length; index++) {
      final colors = palettes[index];
      testWidgets('publisher card contrast in palette $index', (tester) async {
        var taps = 0;
        final publisher = Publisher(
          id: 'closed',
          type: 'company',
          subType: 'publisher',
          aliases: const [],
          name: 'Closed Press',
          founded: 1990,
          closed: 2020,
          description: 'A publisher of comics.',
          links: [
            PublisherLink(
              type: 'website',
              link: 'https://example.org',
              language: 'en',
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: Scaffold(
              body: PublisherListItem(
                publisher: publisher,
                onTap: () => taps++,
              ),
            ),
          ),
        );
        final card = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(InkWell).first,
                matching: find.byType(Container),
              )
              .first,
        );
        expect((card.decoration! as BoxDecoration).color, colors.surface);
        final badge = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('PUBLISHER'),
                matching: find.byType(Container),
              )
              .first,
        );
        final badgeFill = (badge.decoration! as BoxDecoration).color!;
        final badgeText = tester.widget<Text>(find.text('PUBLISHER'));
        expect(
          MbPalette.contrastRatio(badgeText.style!.color!, badgeFill),
          greaterThanOrEqualTo(4.5),
        );
        final closed = tester.widget<Text>(find.text('Closed 2020'));
        expect(
          MbPalette.contrastRatio(closed.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final link = tester.widget<Icon>(find.byIcon(Icons.link_rounded));
        final chevron = tester.widget<Icon>(
          find.byIcon(Icons.chevron_right_rounded),
        );
        expect(
          MbPalette.contrastRatio(link.color!, colors.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          MbPalette.contrastRatio(chevron.color!, colors.surface),
          greaterThanOrEqualTo(3),
        );
        expect(find.text('Est. 1990'), findsOneWidget);
        await tester.tap(find.text('Closed Press'));
        expect(taps, 1);
      });
    }
    testWidgets('a publisher has no icon tile', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PublisherListItem(publisher: _publisher(1), onTap: () {}),
          ),
        ),
      );
      expect(find.text('Publisher 1'), findsOneWidget);
      expect(find.byIcon(Icons.business_rounded), findsNothing);
    });

    testWidgets('a person with no photo gets no stand-in glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffListItem(staff: Staff(id: 1, name: 'Akira Toriyama')),
          ),
        ),
      );
      expect(find.text('Akira Toriyama'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.leading, isNull);
    });
  });

  group('results layout', () {
    testWidgets('desktop shows publishers as a grid of cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DesktopLayout.debugOverride = true;

      await tester.pumpWidget(
        _content(BrowseType.publishers, [
          for (var i = 0; i < 6; i++) _publisher(i),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      // Cards sit side by side rather than one per row, and none is stretched
      // across the whole window.
      final first = tester.getRect(find.byType(PublisherListItem).at(0));
      final second = tester.getRect(find.byType(PublisherListItem).at(1));
      expect(second.top, first.top);
      expect(first.width, lessThanOrEqualTo(460));
    });

    testWidgets('desktop shows staff as a grid too', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DesktopLayout.debugOverride = true;

      await tester.pumpWidget(
        _content(BrowseType.staff, [
          for (var i = 0; i < 6; i++)
            Staff(id: i, name: 'Person $i', seriesCount: i),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(StaffListItem), findsWidgets);
    });

    testWidgets('the phone keeps the vertical list', (tester) async {
      DesktopLayout.debugOverride = false;

      await tester.pumpWidget(
        _content(BrowseType.publishers, [
          for (var i = 0; i < 3; i++) _publisher(i),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
