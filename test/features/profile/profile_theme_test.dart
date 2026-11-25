import '../../support/library_identity.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/screens/profile_screen.dart';
import 'package:mangabaka_app/features/profile/screens/statistics_screen.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/profile/services/snapshot_service.dart';
import 'package:mangabaka_app/features/profile/widgets/login/browser_sign_in_prompt.dart';
import 'package:mangabaka_app/features/profile/widgets/snapshot/profile_snapshot_section.dart';
import 'package:mangabaka_app/features/profile/widgets/statistics/profile_statistics_section.dart';
import 'package:mangabaka_app/features/profile/widgets/statistics/standout_pick_card.dart';
import 'package:mangabaka_app/features/profile/widgets/statistics/statistic_card.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _profile = MbProfile(
  id: 'profile-1',
  role: 'user',
  scopes: const [],
  nickname: 'Reader',
);
final _entry = LibraryEntry(
  id: 'entry-1',
  state: 'reading',
  series: Series.fromJson({'id': 'series-1', 'title': 'Cached Series'}),
);

class _FakeAuth extends Fake with WidgetLibraryIdentity {
  bool loggedIn = false;
  MbProfile? profile;
  Future<MbProfile> Function()? response;
  int fetchCount = 0;
  int cancelCount = 0;
  int reopenCount = 0;
  @override
  final ValueNotifier<bool> awaitingBrowser = ValueNotifier(false);

  @override
  bool get isLoggedIn => loggedIn;
  @override
  MbProfile? get cachedProfile => profile;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) {
    fetchCount++;
    return response != null ? response!() : Future.value(profile ?? _profile);
  }

  @override
  void cancelLogin() => cancelCount++;
  @override
  Future<void> reopenBrowser() async => reopenCount++;
}

class _FakeLibrary extends Fake implements LibraryService {
  @override
  final ValueNotifier<LibrarySyncStatus> syncStatus = ValueNotifier(
    const LibrarySyncStatus(),
  );
  @override
  Future<void> performInitialSyncIfNeeded() async {}
}

class _FakeSnapshot extends Fake implements SnapshotService {
  int fetchCount = 0;
  @override
  Future<List<LibraryEntry>> fetchSnapshot({
    required String sortBy,
    int page = 1,
    int limit = 10,
  }) async {
    fetchCount++;
    return page == 1 ? [_entry] : [];
  }
}

void main() {
  setUpAll(prepareWidgetLibraryIdentity);
  late _FakeAuth auth;
  late _FakeLibrary library;
  late _FakeSnapshot snapshot;
  late AppDatabase database;

  setUp(() async {
    await resetServiceLocator();
    SharedPreferences.setMockInitialValues({});
    auth = _FakeAuth();
    library = _FakeLibrary();
    snapshot = _FakeSnapshot();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<ProfileAuthService>(auth);
    getIt.registerSingleton<LibraryService>(library);
    getIt.registerSingleton<SnapshotService>(snapshot);
  });

  tearDown(() async {
    await resetServiceLocator();
    await database.close();
    auth.awaitingBrowser.dispose();
    library.syncStatus.dispose();
  });

  Future<void> pumpWithPalette(
    WidgetTester tester,
    ValueNotifier<MbPalette> palette,
    Widget home,
  ) => tester.pumpWidget(
    ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (_, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: home,
      ),
    ),
  );

  testWidgets('logged-out, loading and error Profile colors follow the theme', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpWithPalette(tester, palette, const ProfileScreen());
    expect(
      find.text(LocalizationService().translate('login_prompt_profile')),
      findsOneWidget,
    );
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        colors.background,
      );
      final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
      expect((appBar.title! as Text).style!.color, colors.text);
      final prompt = tester.widget<Text>(
        find.text(LocalizationService().translate('login_prompt_profile')),
      );
      expect(
        MbPalette.contrastRatio(prompt.style!.color!, colors.background),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(auth.fetchCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());

    auth.loggedIn = true;
    final pending = Completer<MbProfile>();
    auth.response = () => pending.future;
    await pumpWithPalette(tester, palette, const ProfileScreen());
    await tester.pump();
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator).first,
    );
    expect(
      MbPalette.contrastRatio(spinner.color!, palette.value.background),
      greaterThanOrEqualTo(3),
    );
    pending.completeError(StateError('fixture failure'));
    await tester.pump();
    await tester.pump();
    final error = tester.widget<Text>(
      find.textContaining('Failed to load profile'),
    );
    expect(
      MbPalette.contrastRatio(error.style!.color!, palette.value.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached Profile and snapshots survive live palette updates', (
    tester,
  ) async {
    auth.loggedIn = true;
    auth.profile = _profile;
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpWithPalette(tester, palette, const ProfileScreen());
    await tester.pump();
    await tester.pump();
    final state = tester.state(find.byType(ProfileScreen));
    final profileFetches = auth.fetchCount;
    final snapshotFetches = snapshot.fetchCount;
    expect(find.text('Cached Series'), findsWidgets);
    expect(find.byType(StatisticCard), findsNWidgets(4));
    for (final colors in [
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      expect(tester.state(find.byType(ProfileScreen)), same(state));
      expect(find.text('Cached Series'), findsWidgets);
      expect(find.byType(StatisticCard), findsNWidgets(4));
      expect(auth.fetchCount, profileFetches);
      expect(snapshot.fetchCount, snapshotFetches);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('statistics screen headings and cards follow live theme', (
    tester,
  ) async {
    auth.loggedIn = true;
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpWithPalette(tester, palette, const StatisticsScreen());
    await tester.pump();
    await tester.pump();
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, colors.background);
      final title =
          tester.widget<AppBar>(find.byType(AppBar).first).title! as Text;
      expect(title.style!.color, colors.text);
      expect(find.byType(StatisticCard), findsNWidgets(7));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('statistics, snapshot and accent text remain readable', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpWithPalette(
      tester,
      palette,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const ProfileStatisticsSection(
                totalSeries: 12,
                chaptersRead: 38,
                volumesRead: 7,
                meanScore: 8.5,
              ),
              ProfileSnapshotSection(
                recentlyChanged: [_entry],
                hasMoreChanged: false,
                onFetchMoreChanged: () {},
                recentlyAdded: [_entry],
                hasMoreAdded: false,
                onFetchMoreAdded: () {},
              ),
              StandoutPickCard(
                icon: Icons.star,
                label: 'Top pick',
                title: 'Accent title',
                value: '9.0',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
      EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
    ]) {
      palette.value = colors;
      await tester.pump();
      final card = find.byType(StatisticCard).first;
      final surface = tester.widget<Container>(
        find.descendant(of: card, matching: find.byType(Container)).first,
      );
      expect((surface.decoration! as BoxDecoration).color, colors.surface);
      final icon = tester.widget<Icon>(
        find.descendant(of: card, matching: find.byType(Icon)).first,
      );
      expect(
        MbPalette.contrastRatio(icon.color!, colors.surface),
        greaterThanOrEqualTo(3),
      );
      final label = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .last;
      expect(
        MbPalette.contrastRatio(label.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      final accent = tester.widget<Text>(find.text('Accent title'));
      expect(
        MbPalette.contrastRatio(accent.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(find.text('Cached Series'), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('browser sign-in prompt is readable and keeps its actions', (
    tester,
  ) async {
    auth.awaitingBrowser.value = true;
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      await tester.binding.setSurfaceSize(size);
      await pumpWithPalette(
        tester,
        palette,
        const Scaffold(body: BrowserSignInPrompt(child: SizedBox.expand())),
      );
      for (final colors in [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        ThemePresets.byId('nord')!.dark!,
        EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
      ]) {
        palette.value = colors;
        await tester.pump();
        final title = tester.widget<Text>(
          find.text(
            LocalizationService().translate('auth_waiting_title').toUpperCase(),
          ),
        );
        expect(
          MbPalette.contrastRatio(title.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final promptCard = tester.widget<Container>(
          find
              .ancestor(
                of: find.text(
                  LocalizationService()
                      .translate('auth_waiting_title')
                      .toUpperCase(),
                ),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((promptCard.decoration! as BoxDecoration).color, colors.surface);
        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator).first,
        );
        expect(
          MbPalette.contrastRatio(spinner.color!, colors.surface),
          greaterThanOrEqualTo(3),
        );
        final cancel = tester.widget<TextButton>(find.byType(TextButton));
        final cancelColor = cancel.style!.foregroundColor!.resolve({})!;
        expect(
          MbPalette.contrastRatio(cancelColor, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final reopen = tester.widget<ElevatedButton>(
          find.byType(ElevatedButton),
        );
        expect(reopen.onPressed, isNotNull);
        expect(
          MbPalette.contrastRatio(colors.onAccent, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      }
    }
    await tester.binding.setSurfaceSize(const Size(620, 500));
    await tester.tap(find.text(LocalizationService().translate('cancel')));
    await tester.tap(
      find.text(LocalizationService().translate('auth_reopen_browser')),
    );
    expect(auth.cancelCount, 1);
    expect(auth.reopenCount, 1);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('statistics and snapshots fit narrow and short viewports', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.light);
    addTearDown(palette.dispose);
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      await tester.binding.setSurfaceSize(size);
      await pumpWithPalette(
        tester,
        palette,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const ProfileStatisticsSection(
                  totalSeries: 12,
                  chaptersRead: 38,
                  volumesRead: 7,
                  meanScore: 8.5,
                ),
                ProfileSnapshotSection(
                  recentlyChanged: [_entry],
                  hasMoreChanged: false,
                  onFetchMoreChanged: () {},
                  recentlyAdded: [_entry],
                  hasMoreAdded: false,
                  onFetchMoreAdded: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(StatisticCard), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
