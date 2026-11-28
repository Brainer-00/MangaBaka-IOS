import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/widgets/guarded_draggable_sheet.dart';
import 'package:mangabaka_app/features/library/widgets/collection_header_search.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/stacks/stack_controller.dart';
import 'package:mangabaka_app/features/stacks/stack_models.dart';
import 'package:mangabaka_app/features/stacks/stack_service.dart';
import 'package:mangabaka_app/features/stacks/stack_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends ProfileAuthService {
  LibraryCacheLease? owner;
  bool read = true;
  bool write = true;
  int generation = 0;
  @override
  LibraryCacheLease? get libraryLease => owner;
  @override
  bool get isLoggedIn => owner != null;
  @override
  bool get canReadStacks => owner != null && read;
  @override
  bool get canWriteStacks => owner != null && write;
  @override
  int get stackAuthorizationGeneration => generation;
  @override
  Future<String> getValidAccessToken() async => 'test-token';

  void switchTo(LibraryCacheLease? lease) {
    owner = lease;
    notifyListeners();
  }

  void replaceGrant({required bool read, required bool write}) {
    this.read = read;
    this.write = write;
    generation++;
    notifyListeners();
  }
}

StackJson _status(StackRelationship relation) => {
  'id': 1,
  'has_voted': false,
  'has_saved': relation != StackRelationship.none,
  'has_followed': relation == StackRelationship.following,
  'save_count': relation == StackRelationship.none ? 0 : 1,
  'follow_count': relation == StackRelationship.following ? 1 : 0,
  'vote_count': 0,
  'library_count': 0,
};

StackJson _stack({
  int id = 1,
  String title = 'Manga from the 1970s',
  String owner = 'other',
  String visibility = 'public',
  int count = 5,
}) => {
  'id': id,
  'title': title,
  'owner': {'id': owner, 'name': 'Reader'},
  'visibility': visibility,
  'content_rating': 'safe',
  'is_spoiler': false,
  'entry_count': count,
  'save_count': 0,
  'vote_count': 0,
  'covers': [],
};

final _summary = StackSummary.fromJson(_stack());

StackJson _publicDetail({String description = 'A private description'}) => {
  ..._stack(count: 1),
  'description': description,
  'is_comments_enabled': true,
  'entries': [
    {
      'rank': 1,
      'series_id': 9,
      'note': 'A private note',
      'issue': null,
      'series': {
        'id': 9,
        'title': 'Stack member',
        'state': 'active',
        'content_rating': 'safe',
      },
    },
  ],
};

http.Response _page(List<StackJson> data) => http.Response(
  jsonEncode({
    'status': 200,
    'data': data,
    'pagination': {'next': null},
  }),
  200,
);

http.Response _response(dynamic data) =>
    http.Response(jsonEncode({'status': 200, 'data': data}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _Auth auth;
  late LibraryCacheLease owner;
  late StackRelationship serverState;
  late StackController controller;
  late List<http.Request> requests;
  Future<http.Response?> Function(http.Request)? intercept;
  StackAccess access() => controller.authorization!;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _Auth();
    owner = await database.ownedLibraryDao.activate(
      VerifiedLibraryOwner.fromVerifiedAccountId('reader'),
    );
    auth.switchTo(owner);
    serverState = StackRelationship.none;
    requests = [];
    intercept = null;
    controller = StackController(
      StackService(
        auth,
        client: MockClient((request) async {
          requests.add(request);
          expect(
            request.headers['authorization'],
            request.url.path.startsWith('/v2/my/') ? 'Bearer test-token' : null,
          );
          final response = await intercept?.call(request);
          if (response != null) return response;
          final path = request.url.path;
          if (path.endsWith('/status')) {
            expect(request.url.queryParametersAll['id'], ['1']);
            return _response([_status(serverState)]);
          }
          serverState = switch ((request.method, path.split('/')[4])) {
            ('PUT', 'saved') when serverState == StackRelationship.none =>
              StackRelationship.saved,
            ('PUT', 'saved') => serverState,
            ('PUT', 'followed') => StackRelationship.following,
            ('DELETE', 'saved') => StackRelationship.none,
            ('DELETE', 'followed')
                when serverState == StackRelationship.following =>
              StackRelationship.saved,
            _ => serverState,
          };
          return _response(_status(serverState));
        }),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    auth.dispose();
    await database.close();
  });

  Future<StackWriteResult> mutate(StackAction action, {bool confirm = false}) =>
      controller.changeRelationship(
        access(),
        _summary,
        controller.viewer(1)!,
        action,
        confirmCoupledRemoval: () async => confirm,
      );

  void expectMembership(StackRelationship expected) {
    expect(controller.viewer(1)?.relationship, expected);
    expect(controller.section(StackSection.created).items, isEmpty);
    expect(
      controller.section(StackSection.saved).items.map((item) => item.id),
      expected == StackRelationship.none ? [] : [1],
    );
    expect(
      controller.section(StackSection.following).items.map((item) => item.id),
      expected == StackRelationship.following ? [1] : [],
    );
  }

  for (final (before, action, after) in [
    (StackRelationship.none, StackAction.save, StackRelationship.saved),
    (StackRelationship.none, StackAction.follow, StackRelationship.following),
    (StackRelationship.saved, StackAction.follow, StackRelationship.following),
    (StackRelationship.saved, StackAction.unsave, StackRelationship.none),
    (
      StackRelationship.following,
      StackAction.unfollow,
      StackRelationship.saved,
    ),
    (StackRelationship.following, StackAction.unsave, StackRelationship.none),
  ]) {
    test('${before.name} → ${action.name} → ${after.name}', () async {
      serverState = before;
      await controller.refreshStatus(access(), 1);
      if (before == StackRelationship.following &&
          action == StackAction.unsave) {
        expect(await mutate(action), StackWriteResult.cancelled);
        expect(requests.map((r) => r.method), ['GET', 'GET']);
      }
      final priorRequests = requests.length;
      expect(await mutate(action, confirm: true), StackWriteResult.confirmed);
      expectMembership(after);
      expect(requests.skip(priorRequests).map((r) => r.method), [
        if (action == StackAction.unsave) 'GET',
        if (action == StackAction.unsave &&
            before == StackRelationship.following)
          'GET',
        action.method,
      ]);
      expect(requests.last.method, action.method);
      expect(requests.last.url.path, '/v2/my/stacks/${action.path}/1');
      expect(requests.last.body, isEmpty);
    });
  }

  test('external follow stops an originally save-only Unsave', () async {
    serverState = StackRelationship.saved;
    await controller.refreshStatus(access(), 1);
    serverState = StackRelationship.following;
    expect(await mutate(StackAction.unsave), StackWriteResult.rejected);
    expectMembership(StackRelationship.following);
    expect(controller.writeError(1), 'stack_relationship_changed');
    expect(requests.map((request) => request.method), ['GET', 'GET']);
  });

  test(
    'late writes under a replaced grant cannot unlock a new reservation',
    () async {
      await controller.refreshStatus(access(), 1);
      final olderStarted = Completer<void>();
      final older = Completer<http.Response>();
      final newerStarted = Completer<void>();
      final newer = Completer<http.Response>();
      intercept = (request) async {
        if (request.method != 'PUT') return null;
        if (request.url.path.endsWith('/followed/1')) {
          olderStarted.complete();
          return older.future;
        }
        newerStarted.complete();
        return newer.future;
      };
      final obsolete = mutate(StackAction.follow);
      await olderStarted.future;
      auth.replaceGrant(read: false, write: false);
      auth.replaceGrant(read: true, write: true);
      expect(controller.lease, same(owner));
      await controller.refreshStatus(access(), 1);
      final current = mutate(StackAction.save);
      await newerStarted.future;
      older.complete(_response(_status(StackRelationship.following)));
      expect(await obsolete, StackWriteResult.invalidated);
      expect(controller.busy(1), isTrue);
      expect(await mutate(StackAction.follow), StackWriteResult.rejected);
      expectMembership(StackRelationship.none);
      newer.complete(_response(_status(StackRelationship.saved)));
      expect(await current, StackWriteResult.confirmed);
      expectMembership(StackRelationship.saved);
      expect(controller.busy(1), isFalse);
      expect(requests.map((request) => request.method), [
        'GET',
        'PUT',
        'GET',
        'PUT',
      ]);
    },
  );

  test(
    'grant restoration rejects old catalogue, detail, status, draft and picker results',
    () async {
      const responses = {
        '/v2/my/stacks/saved',
        '/v2/stacks/1',
        '/v2/my/stacks/status',
        '/v2/my/stacks',
        '/v2/my/series/9/stacks',
      };
      final started = Completer<void>();
      final replies = {
        for (final path in responses) path: Completer<http.Response>(),
      };
      var received = 0;
      intercept = (request) async {
        final reply = replies[request.url.path];
        if (reply == null) return null;
        if (++received == responses.length) started.complete();
        return reply.future;
      };
      final obsolete = access();
      final catalog = controller.loadSection(obsolete, StackSection.saved, [
        'safe',
      ]);
      final detail = controller.readDetail(obsolete, 1, owned: false);
      final status = controller.refreshStatus(obsolete, 1);
      final draft = controller.create(obsolete, 'Obsolete draft');
      final picker = expectLater(
        controller.service.forSeries(obsolete, 9),
        throwsA(
          isA<StackFailure>().having(
            (e) => e.code,
            'code',
            'stack_session_changed',
          ),
        ),
      );
      await started.future;
      auth.replaceGrant(read: false, write: false);
      auth.replaceGrant(read: true, write: true);
      expect(access().lease, same(owner));
      expect(controller.liveAccess(obsolete), isFalse);
      intercept = (request) async {
        if (request.url.path == '/v2/stacks/1') {
          return _response(_publicDetail(description: 'Fresh description'));
        }
        return null;
      };
      await controller.readDetail(access(), 1, owned: false);
      serverState = StackRelationship.saved;
      await controller.refreshStatus(access(), 1);
      replies['/v2/my/stacks/saved']!.complete(_page([_stack()]));
      replies['/v2/stacks/1']!.complete(_response(_publicDetail()));
      replies['/v2/my/stacks/status']!.complete(
        _response([_status(StackRelationship.following)]),
      );
      replies['/v2/my/stacks']!.complete(_response({}));
      replies['/v2/my/series/9/stacks']!.complete(_response([]));
      await catalog;
      await picker;
      expect(await detail, isNull);
      expect(await status, isNull);
      expect(await draft, isNull);
      expect(controller.detail(1)?.description, 'Fresh description');
      expectMembership(StackRelationship.saved);
      expect(controller.section(StackSection.saved).loaded, isFalse);
    },
  );

  test('grant replacement fences uncertain-write readback', () async {
    await controller.refreshStatus(access(), 1);
    final reading = Completer<void>();
    final readback = Completer<http.Response>();
    intercept = (request) async {
      if (request.method == 'PUT') return http.Response('{}', 503);
      reading.complete();
      return readback.future;
    };
    final follow = mutate(StackAction.follow);
    await reading.future;
    auth.replaceGrant(read: true, write: true);
    readback.complete(_response([_status(StackRelationship.following)]));
    expect(await follow, StackWriteResult.invalidated);
    expect(controller.viewer(1), isNull);
    expect(controller.uncertain(1), isFalse);
    expect(controller.section(StackSection.following).items, isEmpty);
    expect(requests.map((request) => request.method), ['GET', 'PUT', 'GET']);
  });

  for (final denial in [403, 404]) {
    test(
      'verified detail denial clears private data and permits later recovery ($denial)',
      () async {
        serverState = StackRelationship.saved;
        intercept = (request) async => request.url.path == '/v2/stacks/1'
            ? _response(_publicDetail())
            : null;
        await controller.readDetail(access(), 1, owned: false);
        final expected = (await controller.refreshStatus(access(), 1))!;
        expect(controller.detail(1)?.entries.single.note, 'A private note');
        expectMembership(StackRelationship.saved);

        intercept = (_) async =>
            http.Response('{"status":$denial,"message":"Unavailable"}', denial);
        await expectLater(
          controller.readDetail(access(), 1, owned: false),
          throwsA(
            isA<StackFailure>().having(
              (error) => error.verifiedDetailDenial,
              'verified',
              true,
            ),
          ),
        );
        expect(controller.detail(1), isNull);
        expect(controller.viewer(1), isNull);
        expect(controller.isDetailUnavailable(1), isTrue);
        expect(controller.wasDeleted(1), isFalse);
        expect(controller.section(StackSection.saved).items.single.id, 1);
        expect(
          await controller.changeRelationship(
            access(),
            _summary,
            expected,
            StackAction.unsave,
          ),
          StackWriteResult.rejected,
        );
        expect(requests.where((r) => r.method != 'GET'), isEmpty);

        intercept = (request) async => request.url.path == '/v2/stacks/1'
            ? _response(_publicDetail(description: 'Verified again'))
            : null;
        await controller.readDetail(access(), 1, owned: false);
        await controller.refreshStatus(access(), 1);
        expect(controller.detail(1)?.description, 'Verified again');
        expect(controller.isDetailUnavailable(1), isFalse);
        expectMembership(StackRelationship.saved);
      },
    );
  }

  test(
    'temporary and malformed detail errors retain stale content until recovery',
    () async {
      intercept = (_) async => _response(_publicDetail());
      final detail = await controller.readDetail(access(), 1, owned: false);
      for (final code in [503, 404, 403]) {
        intercept = (_) async =>
            http.Response('<html>Unexpected error</html>', code);
        await expectLater(
          controller.readDetail(access(), 1, owned: false),
          throwsA(isA<StackFailure>()),
        );
        expect(controller.detail(1), same(detail));
        expect(controller.isDetailStale(1), isTrue);
        expect(controller.isDetailUnavailable(1), isFalse);
      }
      intercept = (_) async =>
          _response(_publicDetail(description: 'New detail'));
      await controller.readDetail(access(), 1, owned: false);
      expect(controller.detail(1)?.description, 'New detail');
      expect(controller.isDetailStale(1), isFalse);
    },
  );

  test(
    'a late detail response cannot restore content after a verified denial',
    () async {
      final started = Completer<void>();
      final delayed = Completer<http.Response>();
      intercept = (_) {
        started.complete();
        return delayed.future;
      };
      final reading = controller.readDetail(access(), 1, owned: false);
      await started.future;
      intercept = (_) async =>
          http.Response('{"status":404,"message":"Unavailable"}', 404);
      await expectLater(
        controller.readDetail(access(), 1, owned: false),
        throwsA(isA<StackFailure>()),
      );
      delayed.complete(_response(_publicDetail()));
      expect(await reading, isNull);
      expect(controller.detail(1), isNull);
      expect(controller.isDetailUnavailable(1), isTrue);
      intercept = (_) async =>
          _response(_publicDetail(description: 'Reverified detail'));
      expect(
        (await controller.readDetail(access(), 1, owned: false))?.description,
        'Reverified detail',
      );
    },
  );

  test(
    'an old edit response cannot restore detail after a verified denial',
    () async {
      final original = {
        ..._stack(owner: 'reader', visibility: 'draft', count: 0),
        'description': 'Original description',
        'is_comments_enabled': true,
        'token': 'revision',
        'is_spoiler_locked': false,
        'min_content_rating': null,
        'entries': [],
      };
      intercept = (_) async => _response(original);
      final base = (await controller.readDetail(access(), 1, owned: true))!;
      final reading = Completer<void>();
      final denied = Completer<http.Response>();
      final writing = Completer<void>();
      final edited = Completer<http.Response>();
      intercept = (request) {
        if (request.method == 'PUT') {
          writing.complete();
          return edited.future;
        }
        reading.complete();
        return denied.future;
      };
      final denial = expectLater(
        controller.readDetail(access(), 1, owned: true),
        throwsA(isA<StackFailure>()),
      );
      await reading.future;
      final edit = controller.update(
        access(),
        StackDraft.fromDetail(base)..description = 'Edited',
      );
      await writing.future;
      denied.complete(
        http.Response('{"status":403,"message":"Unavailable"}', 403),
      );
      await denial;
      edited.complete(
        _response({
          ...original,
          'description': 'Edited',
          'token': 'another-revision',
        }),
      );
      expect(await edit, isNull);
      expect(controller.detail(1), isNull);
      expect(controller.isDetailUnavailable(1), isTrue);
      expect(controller.busy(1), isFalse);
      expect(requests.map((request) => request.method), ['GET', 'GET', 'PUT']);
    },
  );

  test(
    'inaccessible readback after uncertain delete does not prove deletion',
    () async {
      final original = {
        ..._stack(owner: 'reader', visibility: 'draft', count: 0),
        'description': 'A private description',
        'is_comments_enabled': true,
        'token': 'revision',
        'is_spoiler_locked': false,
        'min_content_rating': null,
        'entries': [],
      };
      var sentDelete = false;
      intercept = (request) async {
        if (request.method == 'DELETE') {
          sentDelete = true;
          return http.Response('{}', 503);
        }
        return sentDelete
            ? http.Response('{"status":404,"message":"Unavailable"}', 404)
            : _response(original);
      };
      final base = (await controller.readDetail(access(), 1, owned: true))!;
      await expectLater(
        controller.delete(access(), base),
        throwsA(
          isA<StackFailure>().having(
            (error) => error.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(controller.isDetailUnavailable(1), isTrue);
      expect(controller.wasDeleted(1), isFalse);
      expect(controller.detail(1), isNull);
      expect(requests.map((request) => request.method), [
        'GET',
        'GET',
        'DELETE',
        'GET',
      ]);
    },
  );

  test(
    'Unsave rechecks after confirmation while holding the reservation',
    () async {
      serverState = StackRelationship.following;
      final expected = (await controller.refreshStatus(access(), 1))!;
      final dialog = Completer<void>();
      final confirm = Completer<bool>();
      final removal = controller.changeRelationship(
        access(),
        _summary,
        expected,
        StackAction.unsave,
        confirmCoupledRemoval: () {
          dialog.complete();
          return confirm.future;
        },
      );
      await dialog.future;
      expect(controller.busy(1), isTrue);
      expect(await mutate(StackAction.unfollow), StackWriteResult.rejected);
      serverState = StackRelationship.saved;
      confirm.complete(true);
      expect(await removal, StackWriteResult.rejected);
      expectMembership(StackRelationship.saved);
      expect(controller.writeError(1), 'stack_relationship_changed');
      expect(requests.map((request) => request.method), ['GET', 'GET', 'GET']);
    },
  );

  for (final afterConfirmation in [false, true]) {
    test(
      'failed authoritative Unsave read sends no deletion ($afterConfirmation)',
      () async {
        serverState = StackRelationship.following;
        final expected = (await controller.refreshStatus(access(), 1))!;
        bool showConfirmation = false;
        intercept = (request) async {
          if (showConfirmation || !afterConfirmation) {
            return http.Response('{}', 503);
          }
          return null;
        };
        final result = await controller.changeRelationship(
          access(),
          _summary,
          expected,
          StackAction.unsave,
          confirmCoupledRemoval: () async {
            showConfirmation = true;
            return true;
          },
        );
        expect(result, StackWriteResult.rejected);
        expect(showConfirmation, afterConfirmation);
        expect(controller.viewer(1)?.relationship, StackRelationship.following);
        expect(requests.map((request) => request.method), [
          'GET',
          'GET',
          if (afterConfirmation) 'GET',
        ]);
        expect(controller.busy(1), isFalse);
      },
    );
  }

  test(
    'rejected write keeps verified state and issues no second write',
    () async {
      await controller.refreshStatus(access(), 1);
      intercept = (request) async =>
          request.method == 'PUT' ? http.Response('{}', 403) : null;
      expect(await mutate(StackAction.follow), StackWriteResult.rejected);
      expectMembership(StackRelationship.none);
      expect(requests, hasLength(2));
    },
  );

  test(
    'uncertain write reads status once and reconciles both sections',
    () async {
      await controller.refreshStatus(access(), 1);
      intercept = (request) async {
        if (request.method != 'PUT') return null;
        serverState = StackRelationship.following;
        return http.Response('{}', 503);
      };
      expect(await mutate(StackAction.follow), StackWriteResult.confirmed);
      expectMembership(StackRelationship.following);
      expect(requests.map((request) => request.method), ['GET', 'PUT', 'GET']);
    },
  );

  test('unverified uncertain write blocks further writes', () async {
    await controller.refreshStatus(access(), 1);
    intercept = (_) async => http.Response('{}', 503);
    expect(await mutate(StackAction.follow), StackWriteResult.uncertain);
    expect(controller.uncertain(1), isTrue);
    expect(await mutate(StackAction.save), StackWriteResult.rejected);
    expect(requests.map((request) => request.method), ['GET', 'PUT', 'GET']);
  });

  test(
    'late status cannot revert a write confirmed while it was pending',
    () async {
      await controller.refreshStatus(access(), 1);
      final reading = Completer<void>();
      final response = Completer<http.Response>();
      intercept = (request) async {
        if (request.method != 'GET') return null;
        reading.complete();
        return response.future;
      };
      final stale = controller.refreshStatus(access(), 1);
      await reading.future;
      expect(await mutate(StackAction.follow), StackWriteResult.confirmed);
      response.complete(_response([_status(StackRelationship.none)]));
      await stale;
      expectMembership(StackRelationship.following);
    },
  );

  test('overlapping writes and stale confirmations are rejected', () async {
    final expected = (await controller.refreshStatus(access(), 1))!;
    final sending = Completer<void>();
    final response = Completer<http.Response>();
    intercept = (request) async {
      if (request.method != 'PUT') return null;
      sending.complete();
      return response.future;
    };
    final follow = mutate(StackAction.follow);
    await sending.future;
    expect(await mutate(StackAction.save), StackWriteResult.rejected);
    response.complete(_response(_status(StackRelationship.following)));
    expect(await follow, StackWriteResult.confirmed);
    expect(
      await controller.changeRelationship(
        access(),
        _summary,
        expected,
        StackAction.unsave,
        confirmCoupledRemoval: () async => true,
      ),
      StackWriteResult.rejected,
    );
    expect(requests, hasLength(2));
    expectMembership(StackRelationship.following);
  });

  test(
    'account switch drops cached state and a pending write response',
    () async {
      await controller.refreshStatus(access(), 1);
      final sending = Completer<void>();
      final response = Completer<http.Response>();
      intercept = (request) async {
        if (request.method != 'PUT') return null;
        sending.complete();
        return response.future;
      };
      final follow = mutate(StackAction.follow);
      await sending.future;
      auth.switchTo(
        await database.ownedLibraryDao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('next-reader'),
        ),
      );
      response.complete(_response(_status(StackRelationship.following)));
      expect(await follow, StackWriteResult.invalidated);
      expect(controller.viewer(1), isNull);
      expect(controller.section(StackSection.saved).items, isEmpty);
      expect(controller.section(StackSection.following).items, isEmpty);
    },
  );

  test(
    'foreign pagination URL is rejected before any follow-up request',
    () async {
      intercept = (_) async => http.Response(
        jsonEncode({
          'status': 200,
          'data': [],
          'pagination': {
            'next': 'https://example.com/v2/my/stacks/followed?page=2',
          },
        }),
        200,
      );
      await controller.loadSection(access(), StackSection.following, ['safe']);
      expect(
        controller.section(StackSection.following).error,
        'stack_invalid_pagination',
      );
      expect(requests, hasLength(1));
    },
  );

  test('the parser rejects a followed-but-unsaved response', () {
    expect(
      () => StackViewer.fromJson({
        ..._status(StackRelationship.following),
        'has_saved': false,
      }),
      throwsFormatException,
    );
  });

  test('create, revise and delete use only Stack endpoints', () async {
    StackJson server = {
      ..._stack(owner: 'reader', visibility: 'draft', count: 0),
      'description': null,
      'is_comments_enabled': true,
      'token': 'r1',
      'is_spoiler_locked': false,
      'min_content_rating': null,
      'entries': [],
    };
    intercept = (request) async {
      switch (request.method) {
        case 'POST':
          expect(request.url.path, '/v2/my/stacks');
          expect(jsonDecode(request.body), {'title': 'A new draft'});
          server['title'] = 'A new draft';
          return _response(server);
        case 'PUT':
          expect(request.url.path, '/v2/my/stacks/1');
          final data = jsonDecode(request.body) as StackJson;
          expect(data['token'], 'r1');
          expect(data['visibility'], 'draft');
          expect(data['entries'], isEmpty);
          server = {...server, ...data, 'token': 'r2'};
          return _response(server);
        case 'GET':
          expect(request.url.path, '/v2/my/stacks/1');
          return _response(server);
        case 'DELETE':
          expect(request.url.path, '/v2/my/stacks/1');
          expect(request.body, isEmpty);
          return http.Response('{"status":200}', 200);
      }
      return null;
    };
    final created = (await controller.create(access(), ' A new draft '))!;
    expect(created.summary.visibility, StackVisibility.draft);
    expect(
      controller.section(StackSection.created).items.single.title,
      'A new draft',
    );
    final draft = StackDraft.fromDetail(created)..description = 'Revised';
    final updated = (await controller.update(access(), draft))!;
    expect(updated.revision, 'r2');
    expect(updated.description, 'Revised');
    expect(await controller.delete(access(), updated), isTrue);
    expect(requests.map((request) => request.method), [
      'POST',
      'PUT',
      'GET',
      'DELETE',
    ]);
    expect(controller.section(StackSection.created).items, isEmpty);
    expect(controller.detail(1), isNull);
  });

  test(
    'a revision conflict reads back once and rejects a stale retry',
    () async {
      StackJson detail(String revision) => {
        ..._stack(owner: 'reader', visibility: 'draft', count: 0),
        'description': null,
        'is_comments_enabled': true,
        'token': revision,
        'is_spoiler_locked': false,
        'min_content_rating': null,
        'entries': [],
      };
      var revision = 'old';
      intercept = (request) async {
        if (request.method == 'PUT') {
          revision = 'new';
          return http.Response(
            '{"status":409,"message":"Stack changed","code":"stale_token"}',
            409,
          );
        }
        return _response(detail(revision));
      };
      final base = (await controller.readDetail(access(), 1, owned: true))!;
      final draft = StackDraft.fromDetail(base)..description = 'Local edit';
      await expectLater(
        controller.update(access(), draft),
        throwsA(
          isA<StackFailure>().having(
            (failure) => failure.status,
            'status',
            409,
          ),
        ),
      );
      expect(controller.detail(1)?.revision, 'new');
      await expectLater(
        controller.update(access(), draft),
        throwsA(
          isA<StackFailure>().having(
            (failure) => failure.code,
            'code',
            'stack_refresh_required',
          ),
        ),
      );
      expect(requests.map((request) => request.method), ['GET', 'PUT', 'GET']);
    },
  );

  test(
    'full edits preserve order, notes, fields and the original revision',
    () {
      StackJson entry(int id, String note) => {
        'rank': id,
        'series_id': id,
        'note': note,
        'issue': null,
        'series': {'id': id, 'state': 'active', 'content_rating': 'safe'},
      };
      final original = StackDetail.fromJson({
        ..._stack(owner: 'reader', visibility: 'unlisted'),
        'description': 'Original description',
        'is_comments_enabled': false,
        'token': 'old-revision',
        'is_spoiler_locked': false,
        'min_content_rating': null,
        'entries': [for (var id = 1; id <= 5; id++) entry(id, 'Note $id')],
      }, owned: true);
      final draft = StackDraft.fromDetail(original);
      draft.entries.insert(0, draft.entries.removeLast());
      expect(draft.validationError, isNull);
      expect(draft.toJson(), {
        'title': 'Manga from the 1970s',
        'description': 'Original description',
        'visibility': 'unlisted',
        'content_rating': 'safe',
        'is_spoiler': false,
        'is_comments_enabled': false,
        'token': 'old-revision',
        'entries': [
          {'series_id': 5, 'note': 'Note 5'},
          for (var id = 1; id < 5; id++) {'series_id': id, 'note': 'Note $id'},
        ],
      });
      draft.entries.removeLast();
      expect(draft.validationError, 'stack_publication_minimum');
      expect(draft.visibility, StackVisibility.unlisted);
      draft.visibility = StackVisibility.draft;
      expect(draft.validationError, isNull);
      draft.entries.add(draft.entries.first);
      expect(draft.validationError, 'stack_entry_limit');
    },
  );

  Future<void> loadStrings() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    LocalizationService.resetForTesting();
    await LocalizationService().init();
  }

  for (final invalidation in ['denied', 'grant replaced', 'signed out']) {
    testWidgets(
      'open entry note hides content when access changes ($invalidation)',
      (tester) async {
        await tester.runAsync(loadStrings);
        final search = CollectionHeaderSearch();
        addTearDown(search.dispose);
        serverState = StackRelationship.saved;
        intercept = (request) async => switch (request.url.path) {
          '/v2/my/stacks/saved' => _page([_stack()]),
          '/v2/my/stacks' || '/v2/my/stacks/followed' => _page([]),
          '/v2/stacks/1' => _response(_publicDetail()),
          _ => null,
        };
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              showTooltips: true,
              palette: EirenYuPalette.dark,
            ),
            home: Scaffold(
              body: StackOverview(
                controller: controller,
                search: search,
                active: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manga from the 1970s'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Entry note'));
        await tester.pumpAndSettle();
        expect(find.text('A private note', findRichText: true), findsOneWidget);
        final oldAccess = access();
        switch (invalidation) {
          case 'denied':
            intercept = (_) async =>
                http.Response('{"status":404,"message":"Unavailable"}', 404);
            final denial = await tester.runAsync(() async {
              try {
                await controller.readDetail(oldAccess, 1, owned: false);
              } on StackFailure catch (error) {
                return error;
              }
              return null;
            });
            expect(denial?.code, 'stack_unavailable');
            expect(denial?.verifiedDetailDenial, isTrue);
            expect(controller.detail(1), isNull);
            expect(controller.isDetailUnavailable(1), isTrue);
          case 'grant replaced':
            auth.replaceGrant(read: false, write: false);
            auth.replaceGrant(read: true, write: true);
          case 'signed out':
            auth.switchTo(null);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('A private note', findRichText: true), findsNothing);
        if (invalidation == 'denied') {
          expect(controller.detail(1), isNull);
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('This stack is unavailable.'),
            ),
            findsOneWidget,
          );
        } else {
          expect(controller.liveAccess(oldAccess), isFalse);
          expect(
            find.text(
              invalidation == 'grant replaced'
                  ? 'Stack permissions changed. Close this window and try again.'
                  : 'Your MangaBaka account changed. Close this screen and try again.',
              skipOffstage: true,
            ),
            findsWidgets,
          );
        }
      },
    );
  }

  testWidgets('all sections search, and coupled unsave asks before writing', (
    tester,
  ) async {
    await tester.runAsync(loadStrings);
    final search = CollectionHeaderSearch();
    addTearDown(search.dispose);
    serverState = StackRelationship.following;
    final created = _stack(id: 2, title: 'Reading room', owner: 'reader');
    final followed = _stack(count: 0);
    http.Response page(List<StackJson> data) => http.Response(
      jsonEncode({
        'status': 200,
        'data': data,
        'pagination': {'next': null},
      }),
      200,
    );
    intercept = (request) async {
      return switch (request.url.path) {
        '/v2/my/stacks' => page([created]),
        '/v2/my/stacks/saved' || '/v2/my/stacks/followed' => page([followed]),
        '/v2/my/stacks/status' => _response([
          for (final id in request.url.queryParametersAll['id']!)
            if (id == '1')
              _status(serverState)
            else
              {..._status(StackRelationship.none), 'id': 2},
        ]),
        '/v2/stacks/1' => _response({
          ...followed,
          'description': null,
          'is_comments_enabled': true,
          'entries': [],
        }),
        _ => null,
      };
    };
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: EirenYuPalette.dark),
        home: Scaffold(
          body: StackOverview(
            controller: controller,
            search: search,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final headings = ['Created', 'Saved', 'Following'];
    final positions = [
      for (final label in headings) tester.getCenter(find.text(label)).dy,
    ];
    expect(positions, orderedEquals(positions.toList()..sort()));
    expect(find.byTooltip('Create stack'), findsOneWidget);
    search.text.text = '1970s';
    await tester.pumpAndSettle();
    expect(find.text('Reading room'), findsNothing);
    expect(find.text('Manga from the 1970s'), findsNWidgets(2));
    await tester.tap(find.text('Manga from the 1970s').first);
    await tester.pumpAndSettle();
    expect(find.text('Unfollow'), findsOneWidget);
    expect(find.byTooltip('Edit stack'), findsNothing);
    await tester.tap(find.text('Unsave and unfollow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('removed from both Saved and Following'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method != 'GET'), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Unsave and unfollow'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Follow and save'), findsOneWidget);
    expect(
      requests.where((request) => request.method == 'DELETE'),
      hasLength(1),
    );
    expect(controller.viewer(1)?.relationship, StackRelationship.none);
    expect(controller.section(StackSection.saved).items, isEmpty);
    expect(controller.section(StackSection.following).items, isEmpty);
  });

  testWidgets('draft form fits content and guards a dirty downward dismissal', (
    tester,
  ) async {
    await tester.runAsync(loadStrings);
    final search = CollectionHeaderSearch();
    addTearDown(search.dispose);
    intercept = (request) async => http.Response(
      jsonEncode({
        'status': 200,
        'data': [],
        'pagination': {'next': null},
      }),
      200,
    );
    tester.view.physicalSize = const Size(375, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: StackOverview(
            controller: controller,
            search: search,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create stack'));
    await tester.pumpAndSettle();
    final sheet = find.byType(GuardedDraggableSheet);
    expect(tester.getSize(sheet).height, lessThan(370));
    await tester.enterText(find.byType(TextField), 'Draft one');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('editor_sheet_drag_handle')),
      const Offset(0, 130),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });
}
