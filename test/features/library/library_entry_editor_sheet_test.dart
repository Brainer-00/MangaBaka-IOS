import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_entry_editor_sheet.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/library_identity.dart';

class _Auth extends SignedInWidgetAuth {
  final _listeners = ChangeNotifier();
  LibraryCacheLease? _lease = testLibraryLease;

  @override
  LibraryCacheLease? get libraryLease => _lease;

  void setLease(LibraryCacheLease? value) {
    _lease = value;
    _listeners.notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) => _listeners.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listeners.removeListener(listener);
}

class _Library extends Fake implements LibraryService {
  LibraryEntry? entry;
  Future<LibraryEntry?> Function()? read;
  Future<List<AccountLibraryList>> Function()? loadLists;
  Future<LibrarySaveResult> Function()? save;
  final reads = <(String, LibraryCacheLease?)>[];
  final listReads = <LibraryCacheLease>[];
  final creates = <LibraryEntryDraft>[];
  final updates = <LibraryEntryDraft>[];

  @override
  Future<LibraryEntry?> fetchAuthoritativeLibraryEntry(
    String seriesId, {
    LibraryCacheLease? lease,
  }) async {
    reads.add((seriesId, lease));
    return read == null ? entry : await read!();
  }

  @override
  Future<List<AccountLibraryList>> fetchAccountLibraryLists(
    LibraryCacheLease lease,
  ) async {
    listReads.add(lease);
    return loadLists == null
        ? const [
            AccountLibraryList(id: 11, name: 'Weekend', isPrivate: false),
            AccountLibraryList(
              id: 22,
              name: 'Private reading',
              isPrivate: true,
            ),
          ]
        : await loadLists!();
  }

  @override
  Future<LibrarySaveResult> createCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) async {
    creates.add(draft);
    return save == null
        ? const LibrarySaveResult(LibrarySaveOutcome.saved)
        : await save!();
  }

  @override
  Future<LibrarySaveResult> updateCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) async {
    updates.add(draft);
    return save == null
        ? LibrarySaveResult(LibrarySaveOutcome.saved, entry: entry)
        : await save!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Library library;
  late LibraryCacheLease otherLease;
  final series = Series.fromJson({
    'id': 18,
    'title': 'An unfinished series',
    'total_chapters': 12,
  });

  LibraryEntry existing({List<int>? ids, int? rating = 86}) => LibraryEntry(
    id: '48',
    series: series,
    state: 'reading',
    priority: 21.5,
    startDate: '2024-01-02T23:59:59-06:00',
    finishDate: '2024-03-20',
    progressChapter: 11,
    progressVolume: 4,
    numberOfRereads: 2,
    isPrivate: true,
    readLink: 'https://example.test/private',
    listIds: ids,
    rating: rating,
    note: 'A private note\nAnother line',
  );

  setUpAll(() async {
    await prepareWidgetLibraryIdentity();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      otherLease = await db.ownedLibraryDao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('other-widget-account'),
      );
    } finally {
      await db.close();
    }
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
  });

  setUp(() {
    auth = _Auth();
    library = _Library();
  });

  String tr(String key) => LocalizationService().translate(key);
  Finder label(String key) => find.text(tr(key));
  Finder field(String key) => find.byKey(ValueKey(key));
  Finder editor() => find.byType(LibraryEntryEditorSheet);
  Finder action(String key) =>
      find.descendant(of: editor(), matching: label(key));

  Future<void> show(
    WidgetTester tester, {
    bool edit = false,
    bool settle = true,
    MbPalette? palette,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: palette ?? EirenYuPalette.dark,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => LibraryEntryEditorSheet.show(
                context,
                library: library,
                auth: auth,
                lease: auth.libraryLease!,
                series: series,
                title: series.title,
                defaultState: 'considering',
                edit: edit,
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), text);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = action(key);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(field(key)).controller!.text;

  testWidgets('Add waits for confirmed absence and Cancel sends no write', (
    tester,
  ) async {
    final pending = Completer<LibraryEntry?>();
    library.read = () => pending.future;
    await show(tester, settle: false);
    expect(library.reads, [(series.id, testLibraryLease)]);
    expect(action('library_editor_loading'), findsOneWidget);
    expect(action('save'), findsNothing);
    expect(library.creates, isEmpty);

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(action('add_to_library'), findsOneWidget);
    expect(action('considering'), findsOneWidget);
    expect(library.listReads, [testLibraryLease]);
    await tap(tester, 'cancel');
    expect(editor(), findsNothing);
    expect(library.creates, isEmpty);
  });

  for (final error in [
    NetworkException(message: 'fixture timeout'),
    ApiException(message: 'fixture authorization', statusCode: 403),
    const FormatException('fixture malformed response'),
  ]) {
    testWidgets(
      'Failed authoritative read is retryable: ${error.runtimeType}',
      (tester) async {
        library.read = () async => throw error;
        await show(tester);
        expect(action('library_editor_load_failed'), findsOneWidget);
        expect(action('save'), findsNothing);
        expect(library.listReads, isEmpty);
        library.read = null;
        await tap(tester, 'retry');
        expect(action('save'), findsOneWidget);
        expect(library.reads, List.filled(2, (series.id, testLibraryLease)));
        expect(library.creates, isEmpty);
      },
    );
  }

  testWidgets('Add switches to Edit when an existing entry is confirmed', (
    tester,
  ) async {
    library.entry = existing();
    await show(tester);
    expect(action('library_editor_edit'), findsOneWidget);
    expect(textOf(tester, 'library_editor_notes'), library.entry!.note);
    await tap(tester, 'save');
    expect(editor(), findsNothing);
    expect(library.creates, isEmpty);
    expect(library.updates, isEmpty);
  });

  testWidgets('Edit on confirmed absence offers no create action', (
    tester,
  ) async {
    await show(tester, edit: true);
    expect(action('library_editor_missing'), findsOneWidget);
    expect(action('save'), findsNothing);
    expect(library.creates, isEmpty);
  });

  testWidgets('Explicit Add sends tracking payload once and waits for save', (
    tester,
  ) async {
    final pending = Completer<LibrarySaveResult>();
    library.save = () => pending.future;
    await show(tester);
    final status = find.byType(DropdownButtonFormField<String>);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: status,
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .items,
      hasLength(7),
    );
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(label('rereading').last);
    await tester.pumpAndSettle();
    await enter(tester, 'library_editor_priority', '21,5');
    await enter(tester, 'library_editor_start_date', '2024-02-29');
    await enter(tester, 'library_editor_finish_date', '2024-03-02');
    await enter(tester, 'chapters', '18');
    await enter(tester, 'volumes', '6');
    await enter(tester, 'library_editor_rereads', '3');
    await enter(
      tester,
      'library_editor_read_link',
      'https://example.test/read',
    );
    await tap(tester, 'library_editor_private');
    await tap(tester, 'library_editor_lists');
    await tester.ensureVisible(find.text('Private reading'));
    await tester.tap(find.text('Private reading'));
    await tester.pumpAndSettle();
    await enter(tester, 'rating', '100');
    await enter(tester, 'library_editor_notes', 'First line\nSecond line');
    expect(library.creates, isEmpty);

    // Tap from the same frame twice, before the disabled button is rendered.
    await tester.tap(action('save'));
    await tester.tap(action('save'));
    await tester.pumpAndSettle();
    expect(action('library_editor_saving'), findsOneWidget);
    expect(library.creates, hasLength(1));
    expect(library.creates.single.lease, same(testLibraryLease));
    expect(library.creates.single.seriesId, series.id);
    expect(library.creates.single.toJson(), {
      'state': 'rereading',
      'priority': 21.5,
      'start_date': '2024-02-29',
      'finish_date': '2024-03-02',
      'progress_chapter': 18,
      'progress_volume': 6,
      'number_of_rereads': 3,
      'read_link': 'https://example.test/read',
      'is_private': true,
      'lists': [22],
      'rating': 100,
      'note': 'First line\nSecond line',
    });
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(editor(), findsOneWidget);
    pending.complete(const LibrarySaveResult(LibrarySaveOutcome.saved));
    await tester.pumpAndSettle();
    expect(editor(), findsNothing);
  });

  testWidgets('Creation conflict opens existing entry only on request', (
    tester,
  ) async {
    library.save = () async =>
        throw ApiException(message: 'fixture collision', statusCode: 409);
    await show(tester);
    await tap(tester, 'save');
    expect(action('library_editor_conflict'), findsOneWidget);
    expect(action('save'), findsNothing);
    expect(library.creates.single.toJson(), {'state': 'considering'});

    library.entry = existing();
    await tap(tester, 'library_editor_open_existing');
    expect(action('library_editor_edit'), findsOneWidget);
    expect(library.creates, hasLength(1));
    expect(library.updates, isEmpty);
  });

  testWidgets(
    'Edit populates all authoritative fields and sends only changes',
    (tester) async {
      library.entry = existing(ids: [11, 22]);
      await show(tester, edit: true);
      expect(action('reading'), findsOneWidget);
      for (final (key, expected) in [
        ('library_editor_priority', '21.5'),
        ('library_editor_start_date', '2024-01-02'),
        ('library_editor_finish_date', '2024-03-20'),
        ('chapters', '11'),
        ('volumes', '4'),
        ('library_editor_rereads', '2'),
        ('library_editor_read_link', 'https://example.test/private'),
        ('rating', '86'),
        ('library_editor_notes', 'A private note\nAnother line'),
      ]) {
        expect(textOf(tester, key), expected, reason: key);
      }
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await enter(tester, 'library_editor_priority', '21,5');
      await enter(tester, 'rating', '0');
      await enter(tester, 'library_editor_notes', 'Edited note');
      await tap(tester, 'save');
      expect(library.updates.single.toJson(), {
        'rating': 0,
        'note': 'Edited note',
      });
      expect(library.updates.single.lease, same(testLibraryLease));
      expect(editor(), findsNothing);
    },
  );

  testWidgets('Known membership can be intentionally emptied', (tester) async {
    library.entry = existing(ids: [22]);
    await show(tester, edit: true);
    await tap(tester, 'library_editor_lists');
    expect(action('library_editor_private_list'), findsOneWidget);
    await tester.ensureVisible(find.text('Private reading'));
    await tester.tap(find.text('Private reading'));
    await tester.pumpAndSettle();
    await tap(tester, 'save');
    expect(library.updates.single.toJson(), {'lists': <int>[]});
  });

  for (final ids in <List<int>?>[
    null,
    [71],
  ]) {
    testWidgets('Unverified membership stays omitted ($ids)', (tester) async {
      library.entry = existing(ids: ids, rating: null);
      await show(tester, edit: true);
      expect(action('library_editor_membership_unknown'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(textOf(tester, 'rating'), '');
      await enter(tester, 'volumes', '8');
      await tap(tester, 'save');
      expect(library.updates.single.toJson(), {'progress_volume': 8});
    });
  }

  testWidgets(
    'Failed list read can retry without erasing existing memberships',
    (tester) async {
      library.entry = existing(ids: [22]);
      library.loadLists = () async => throw const FormatException();
      await show(tester, edit: true);
      expect(action('library_editor_lists_failed'), findsOneWidget);
      await tap(tester, 'library_editor_retry_lists');
      expect(library.listReads, List.filled(2, testLibraryLease));

      await enter(tester, 'library_editor_notes', 'Changed');
      await tap(tester, 'save');
      expect(library.updates.single.toJson(), {'note': 'Changed'});
    },
  );

  testWidgets('At most 30 owned lists can be selected', (tester) async {
    library.entry = existing(ids: List.generate(30, (index) => index + 1));
    library.loadLists = () async => [
      for (var i = 1; i <= 31; i++)
        AccountLibraryList(id: i, name: 'List $i', isPrivate: false),
    ];
    await show(tester, edit: true);
    await tap(tester, 'library_editor_lists');
    final extra = find.byKey(const ValueKey(31));
    expect(tester.widget<CheckboxListTile>(extra).onChanged, isNull);
    final first = find.byKey(const ValueKey(1));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(extra);
    await tester.tap(extra);
    await tester.pumpAndSettle();
    await tap(tester, 'save');
    expect(library.updates.single.toJson()['lists'], [
      ...List.generate(29, (index) => index + 2),
      31,
    ]);
  });

  testWidgets(
    'Validation shows bad input without rounding or clearing fields',
    (tester) async {
      library.entry = existing();
      await show(tester, edit: true);
      expect(label('library_editor_series_total'), findsNothing);
      expect(find.text('Series total 12'), findsOneWidget);
      expect(
        find.byType(TextFormField).evaluate().last,
        same(tester.element(field('library_editor_notes'))),
      );
      for (final (key, invalid) in [
        ('library_editor_priority', '31'),
        ('library_editor_start_date', '2025-02-29'),
        ('library_editor_finish_date', '2263-01-01'),
        ('chapters', '3.5'),
        ('volumes', '10001'),
        ('library_editor_rereads', '-1'),
        ('library_editor_read_link', 'example.test/no-scheme'),
        ('rating', '101'),
        ('library_editor_notes', ''),
      ]) {
        await enter(tester, key, invalid);
      }
      await tap(tester, 'save');
      final invalidFields = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.errorText != null,
      );
      expect(invalidFields, findsNWidgets(9));
      expect(library.updates, isEmpty);
      await tap(tester, 'cancel');
      expect(library.updates, isEmpty);
    },
  );

  testWidgets('Rejecting a save keeps the draft for deliberate retry', (
    tester,
  ) async {
    library.entry = existing();
    library.save = () async => throw ApiException(
      message: 'private rejection payload',
      statusCode: 400,
    );
    await show(tester, edit: true);
    await enter(tester, 'library_editor_notes', 'Preserve my draft');
    await tap(tester, 'save');
    expect(action('library_editor_rejected'), findsOneWidget);
    expect(find.textContaining('private rejection payload'), findsNothing);
    expect(textOf(tester, 'library_editor_notes'), 'Preserve my draft');
    expect(library.updates, hasLength(1));
    library.save = null;
    await tap(tester, 'save');
    expect(library.updates.map((draft) => draft.toJson()), [
      {'note': 'Preserve my draft'},
      {'note': 'Preserve my draft'},
    ]);
    expect(editor(), findsNothing);
  });

  for (final outcome in [
    LibrarySaveOutcome.refreshPending,
    LibrarySaveOutcome.uncertain,
  ]) {
    testWidgets('$outcome stays read-only, even after a successful GET', (
      tester,
    ) async {
      library.save = () async => LibrarySaveResult(outcome);
      await show(tester);
      await tap(tester, 'save');
      final message = outcome == LibrarySaveOutcome.uncertain
          ? 'library_editor_uncertain'
          : 'library_editor_refresh_pending';
      expect(action(message), findsOneWidget);
      expect(action('save'), findsNothing);
      expect(library.creates, hasLength(1));
      expect(library.reads, hasLength(1));

      library.read = () async =>
          throw NetworkException(message: 'fixture error');
      await tap(tester, 'library_editor_check_entry');
      expect(action('library_editor_check_failed'), findsOneWidget);
      library.read = null;
      library.entry = existing();
      await tap(tester, 'library_editor_check_entry');
      expect(library.reads, List.filled(3, (series.id, testLibraryLease)));
      expect(library.creates, hasLength(1));
      expect(library.updates, isEmpty);
      expect(action('save'), findsNothing);
      expect(
        action(
          outcome == LibrarySaveOutcome.uncertain
              ? 'library_editor_found'
              : 'library_editor_refreshed',
        ),
        findsOneWidget,
      );
      if (outcome == LibrarySaveOutcome.uncertain) {
        expect(action(message), findsOneWidget);
      }
    });
  }

  testWidgets('Lease change during loading hides late account data', (
    tester,
  ) async {
    final pending = Completer<LibraryEntry?>();
    library.read = () => pending.future;
    await show(tester, settle: false);
    auth.setLease(otherLease);
    await tester.pumpAndSettle();
    pending.complete(existing(ids: [22]));
    await tester.pumpAndSettle();
    expect(action('library_editor_session_changed'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(library.listReads, isEmpty);
    expect(library.creates, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A dirty editor cannot save after lease invalidation', (
    tester,
  ) async {
    final pending = Completer<List<AccountLibraryList>>();
    library.entry = existing(ids: [22]);
    library.loadLists = () => pending.future;
    await show(tester, edit: true);
    await enter(tester, 'library_editor_notes', 'Private draft text');
    final save = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    auth.setLease(null);
    save(); // Previous-frame callback while a rebuild has not happened yet.
    pending.complete([
      const AccountLibraryList(
        id: 22,
        name: 'Private list name',
        isPrivate: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(action('library_editor_session_changed'), findsOneWidget);
    expect(action('save'), findsNothing);
    expect(find.text('Private draft text'), findsNothing);
    expect(find.text('Private list name'), findsNothing);
    expect(library.updates, isEmpty);
  });

  testWidgets('Account change and dismissal ignore pending Save completion', (
    tester,
  ) async {
    final pending = Completer<LibrarySaveResult>();
    library.entry = existing(ids: [22]);
    library.save = () => pending.future;
    await show(tester, edit: true);
    await enter(tester, 'library_editor_notes', 'First-account change');
    await tap(tester, 'save');
    expect(library.updates.single.lease, same(testLibraryLease));

    auth.setLease(otherLease);
    await tester.pumpAndSettle();
    expect(action('library_editor_session_changed'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tap(tester, 'close');
    pending.complete(
      LibrarySaveResult(LibrarySaveOutcome.saved, entry: existing()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(library.updates, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dismissing during load makes late completion inert', (
    tester,
  ) async {
    final pending = Completer<LibraryEntry?>();
    library.read = () => pending.future;
    await show(tester, settle: false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    pending.complete(existing());
    await tester.pumpAndSettle();
    expect(editor(), findsNothing);
    expect(library.listReads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Date picker selects a bare date and hides on session change', (
    tester,
  ) async {
    library.entry = existing();
    await show(tester, edit: true);
    final calendar = find.descendant(
      of: field('library_editor_start_date'),
      matching: find.byIcon(Icons.calendar_today_outlined),
    );
    await tester.ensureVisible(calendar);
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.tap(
      find.text(
        MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        ).okButtonLabel,
      ),
    );
    await tester.pumpAndSettle();
    expect(textOf(tester, 'library_editor_start_date'), '2024-01-03');

    await tester.tap(calendar);
    await tester.pumpAndSettle();
    auth.setLease(otherLease);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(library.updates, isEmpty);
  });

  for (final palette in [
    EirenYuPalette.light,
    EirenYuPalette.light.withAccent(const Color(0xFF686868)),
    ThemePresets.byId('nord')!.dark!,
  ]) {
    testWidgets(
      'Small sheet stays scrollable with text scale and keyboard ${palette.accent}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.view.padding = const FakeViewPadding(bottom: 20);
        addTearDown(() => tester.view.reset());
        await show(tester, palette: palette, textScale: 1.65);
        final sheet = tester.element(editor());
        expect(sheet.colors.surface, palette.surface);
        expect(Theme.of(sheet).colorScheme.primary, palette.accent);

        await enter(tester, 'library_editor_notes', 'Typed on a small screen');
        tester.view.viewInsets = const FakeViewPadding(bottom: 270);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          textOf(tester, 'library_editor_notes'),
          'Typed on a small screen',
        );
        expect(action('save').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
