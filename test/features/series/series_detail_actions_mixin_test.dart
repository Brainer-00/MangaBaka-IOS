import '../../support/library_identity.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/database/database.dart'
    show LibraryCacheLease;
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/constants/mock_series_data.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/series/mixins/series_detail_actions_mixin.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';

// ─── Fake ────────────────────────────────────────────────────────────────────

class _FakeLibraryService extends Fake implements LibraryService {
  @override
  final collectionsRevision = ValueNotifier<int>(0);
  bool throwOnDelete = false;
  int reads = 0;
  bool failRead = false;
  LibraryEntryDraft? createdDraft;
  String? lastDeletedId;
  int deleteCalls = 0;

  @override
  Future<LibraryEntry?> fetchAuthoritativeLibraryEntry(
    String seriesId, {
    LibraryCacheLease? lease,
  }) async {
    reads++;
    if (failRead) throw const FormatException();
    return null;
  }

  @override
  Future<List<AccountLibraryList>> fetchAccountLibraryLists(
    LibraryCacheLease lease,
  ) async => [];

  @override
  Future<LibrarySaveResult> createCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) async {
    createdDraft = draft;
    return const LibrarySaveResult(LibrarySaveOutcome.saved);
  }

  @override
  Future<void> deleteEntry(String seriesId) async {
    deleteCalls++;
    if (throwOnDelete) throw Exception('delete failed');
    lastDeletedId = seriesId;
  }

  @override
  Future<LibrarySaveResult> updateLibraryEntryRating(
    String seriesId,
    int rating, {
    LibraryCacheLease? lease,
  }) async => const LibrarySaveResult(LibrarySaveOutcome.saved);

  @override
  Future<void> updateLibraryEntryProgress(
    String seriesId, {
    int? progressChapter,
    int? progressVolume,
  }) async {}
}

// ─── Host widget ─────────────────────────────────────────────────────────────

class _TestWidget extends StatefulWidget {
  final LibraryService libraryService;
  final Series? seriesOverride;
  const _TestWidget({required this.libraryService, this.seriesOverride});

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget>
    with SeriesDetailActionsMixin<_TestWidget> {
  @override
  LibraryService get libraryService => widget.libraryService;

  @override
  Series get series => widget.seriesOverride ?? mockSeries222;

  @override
  Widget build(BuildContext context) => Scaffold(body: Container());
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(prepareWidgetLibraryIdentity);
  setUpAll(() async {
    await LoggingService.setup();
  });

  setUp(() {
    getIt.registerSingleton<ProfileAuthService>(SignedInWidgetAuth());
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await getIt.unregister<ProfileAuthService>();
  });

  Widget buildWidget(
    _FakeLibraryService svc, {
    Series? seriesOverride,
    MbPalette? palette,
  }) => MaterialApp(
    theme: palette == null
        ? null
        : AppTheme.build(showTooltips: true, palette: palette),
    home: _TestWidget(libraryService: svc, seriesOverride: seriesOverride),
  );

  Series shareableSeries() => Series.fromJson({
    'id': '222',
    'title': 'The Apothecary Diaries',
    'links': ['https://mangabaka.org/series/222'],
  });

  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  };

  group('SeriesDetailActionsMixin.addSeriesToLibrary', () {
    testWidgets('is a no-op when a Library editor is already open', (
      tester,
    ) async {
      final svc = _FakeLibraryService();
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      final editor = state.addSeriesToLibrary();
      await state.addSeriesToLibrary();
      await tester.pumpAndSettle();

      expect(svc.reads, 1);
      expect(svc.createdDraft, isNull);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      await editor;
    });

    testWidgets('opens first, then saves with the original series and lease', (
      tester,
    ) async {
      final svc = _FakeLibraryService();
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      final editor = state.addSeriesToLibrary();
      await tester.pumpAndSettle();
      expect(svc.reads, 1);
      expect(svc.createdDraft, isNull);
      expect(state.libraryEditorOpen, isTrue);
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      await editor;
      expect(svc.createdDraft?.seriesId, '222');
      expect(svc.createdDraft?.lease, same(testLibraryLease));
      expect(state.libraryEditorOpen, isFalse);
    });

    testWidgets(
      'a failed read offers retry and allows closing without a write',
      (tester) async {
        final svc = _FakeLibraryService()..failRead = true;
        await tester.pumpWidget(buildWidget(svc));
        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

        final editor = state.addSeriesToLibrary();
        await tester.pumpAndSettle();
        expect(find.text('library_editor_load_failed'), findsOneWidget);
        expect(find.text('save'), findsNothing);
        await tester.tap(find.text('close'));
        await tester.pumpAndSettle();
        await editor;
        expect(svc.createdDraft, isNull);
        expect(state.libraryEditorOpen, isFalse);
      },
    );
  });

  group('SeriesDetailActionsMixin.shareLink', () {
    testWidgets(
      'shows no_sharing_link snackbar when series has no mangabaka link',
      (tester) async {
        // mockSeries222 has links: const [] — no mangabaka link present
        final svc = _FakeLibraryService();
        await tester.pumpWidget(buildWidget(svc));
        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

        state.shareLink();
        await tester.pump();

        // LocalizationService not initialised in tests; translate returns the key
        expect(find.text('no_sharing_link'), findsOneWidget);
      },
    );

    for (final entry in palettes.entries) {
      testWidgets('${entry.key} share sheet uses readable palette colors', (
        tester,
      ) async {
        final colors = entry.value;
        final svc = _FakeLibraryService();
        await tester.pumpWidget(
          buildWidget(svc, seriesOverride: shareableSeries(), palette: colors),
        );
        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

        state.shareLink();
        await tester.pumpAndSettle();

        final sheet = tester.widget<Container>(
          find.byKey(const Key('series_share_sheet')),
        );
        expect((sheet.decoration! as BoxDecoration).color, colors.background);
        expect(find.byKey(const Key('series_share_action')), findsOneWidget);
        expect(find.byKey(const Key('series_copy_action')), findsOneWidget);
        final handle = tester.widget<Container>(
          find.byKey(const Key('series_share_handle')),
        );
        expect((handle.decoration! as BoxDecoration).color, colors.border);
        final title = tester.widget<Text>(find.text('share_series'));
        expect(
          MbPalette.contrastRatio(title.style!.color!, colors.background),
          greaterThanOrEqualTo(4.5),
        );
        final icon = tester.widget<Icon>(find.byIcon(Icons.share_rounded));
        final iconSurface = Color.alphaBlend(
          colors.accent.withValues(alpha: 0.1),
          colors.background,
        );
        expect(
          MbPalette.contrastRatio(icon.color!, iconSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('share sheet stays open and recolors when the theme changes', (
      tester,
    ) async {
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final svc = _FakeLibraryService();
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (context, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: _TestWidget(
              libraryService: svc,
              seriesOverride: shareableSeries(),
            ),
          ),
        ),
      );
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state.shareLink();
      await tester.pumpAndSettle();
      palette.value = EirenYuPalette.light;
      await tester.pumpAndSettle();

      final sheet = tester.widget<Container>(
        find.byKey(const Key('series_share_sheet')),
      );
      expect(
        (sheet.decoration! as BoxDecoration).color,
        EirenYuPalette.light.background,
      );
      expect(find.byKey(const Key('series_share_action')), findsOneWidget);
      expect(find.byKey(const Key('series_copy_action')), findsOneWidget);
    });

    testWidgets('copy action preserves the selected link in the clipboard', (
      tester,
    ) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final svc = _FakeLibraryService();
      await tester.pumpWidget(
        buildWidget(svc, seriesOverride: shareableSeries()),
      );
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state.shareLink();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series_copy_action')));
      await tester.pumpAndSettle();

      expect(copiedText, 'https://mangabaka.org/series/222');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('share sheet and delete dialog fit narrow viewports', (
      tester,
    ) async {
      final originalSize = tester.view.physicalSize;
      final originalDpr = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalDpr;
      });

      for (final viewport in const [Size(320, 568), Size(568, 320)]) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        final svc = _FakeLibraryService();
        await tester.pumpWidget(
          buildWidget(svc, seriesOverride: shareableSeries()),
        );
        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

        state.shareLink();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('series_share_sheet')), findsOneWidget);
        expect(tester.takeException(), isNull);

        Navigator.of(state.context).pop();
        await tester.pumpAndSettle();
        state.showDeleteConfirmationDialog();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('series_delete_dialog')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('cancel'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('SeriesDetailActionsMixin.copyToClipboard', () {
    testWidgets('shows a snackbar with the copied text', (tester) async {
      final svc = _FakeLibraryService();
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.copyToClipboard('https://mangabaka.dev/series/222');
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('SeriesDetailActionsMixin.showDeleteConfirmationDialog', () {
    testWidgets('shows dialog with cancel and confirm buttons', (tester) async {
      final svc = _FakeLibraryService();
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.showDeleteConfirmationDialog();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // LocalizationService not initialised; translate returns the key
      expect(find.text('cancel'), findsOneWidget);
      expect(find.text('confirm'), findsOneWidget);
    });

    for (final entry in palettes.entries) {
      testWidgets('${entry.key} delete dialog uses readable danger colors', (
        tester,
      ) async {
        final colors = entry.value;
        final svc = _FakeLibraryService();
        await tester.pumpWidget(buildWidget(svc, palette: colors));
        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
        state.showDeleteConfirmationDialog();
        await tester.pumpAndSettle();

        final dialog = tester.widget<AlertDialog>(
          find.byKey(const Key('series_delete_dialog')),
        );
        expect(dialog.backgroundColor, colors.surface);
        final title = tester.widget<Text>(find.text('DELETE_FROM_LIBRARY'));
        final body = tester.widget<Text>(find.text('delete_confirmation'));
        final cancel = tester.widget<Text>(find.text('cancel'));
        expect(
          MbPalette.contrastRatio(title.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          MbPalette.contrastRatio(body.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          MbPalette.contrastRatio(cancel.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(confirm.style!.backgroundColor!.resolve({}), colors.error);
        final dangerForeground = confirm.style!.foregroundColor!.resolve({})!;
        expect(
          MbPalette.contrastRatio(dangerForeground, colors.error),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('delete dialog remains open and recolors during theme change', (
      tester,
    ) async {
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final svc = _FakeLibraryService();
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (context, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: _TestWidget(libraryService: svc),
          ),
        ),
      );
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state.showDeleteConfirmationDialog();
      await tester.pumpAndSettle();
      palette.value = EirenYuPalette.light;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series_delete_dialog')), findsOneWidget);
      expect(
        tester
            .widget<AlertDialog>(find.byKey(const Key('series_delete_dialog')))
            .backgroundColor,
        EirenYuPalette.light.surface,
      );
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(svc.deleteCalls, 0);
    });

    testWidgets('calls deleteEntry when confirm tapped', (tester) async {
      final svc = _FakeLibraryService();
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.showDeleteConfirmationDialog();
      await tester.pumpAndSettle();

      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();

      expect(svc.lastDeletedId, '222');
      expect(svc.deleteCalls, 1);
    });

    testWidgets('shows error snackbar when deleteEntry throws', (tester) async {
      final svc = _FakeLibraryService()..throwOnDelete = true;
      await tester.pumpWidget(buildWidget(svc));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.showDeleteConfirmationDialog();
      await tester.pumpAndSettle();

      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
