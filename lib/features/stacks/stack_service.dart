import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/database/database.dart' show LibraryCacheLease;
import '../../core/exceptions/app_exceptions.dart';
import '../../core/network/api_client.dart';
import '../../core/network/backend_health_service.dart';
import '../../core/network/rate_limit_coordinator.dart';
import '../profile/services/profile_auth_service.dart';
import 'stack_models.dart';

typedef StackAccess = ({LibraryCacheLease lease, int generation});
typedef StackPage = ({List<StackSummary> items, Uri? next});
typedef OwnedSeriesStack = ({int id, String title, bool canAdd, bool contains});

final class StackFailure implements Exception {
  const StackFailure(
    this.code, {
    this.status,
    this.uncertain = false,
    this.verifiedDetailDenial = false,
  });

  final String code;
  final int? status;
  final bool uncertain;
  final bool verifiedDetailDenial;
}

/// Owns the Stack transport boundary. A lease is required even for a public
/// detail opened from an account-derived list.
final class StackService {
  StackService(this.auth, {http.Client? client})
    : _client = client ?? http.Client();

  final ProfileAuthService auth;
  final http.Client _client;
  final _rateLimit = RateLimitCoordinator.shared;
  static const _base = AppConstants.baseApiUrlV2;
  static const _my = '/my/stacks';

  StackAccess? get authorization {
    final lease = auth.libraryLease;
    if (lease == null) return null;
    return (lease: lease, generation: auth.stackAuthorizationGeneration);
  }

  void check(StackAccess access, {bool write = false}) {
    if (access != authorization) {
      throw const StackFailure('stack_session_changed');
    }
    if (!auth.canReadStacks || (write && !auth.canWriteStacks)) {
      throw const StackFailure('stack_permission_required');
    }
  }

  Future<StackPage> list(
    StackAccess access,
    StackSection section,
    List<String> ratings, {
    Uri? next,
  }) async {
    final base = ApiClient.uri('$_base$_my${section.path}', {
      'content_rating': ratings,
      'limit': 24,
    });
    final uri = next == null ? base : _pageLink(base, next.toString());
    final json = await _request(access, uri);
    return _parse(() {
      final page = json['pagination'] as StackJson;
      if (!page.containsKey('next')) {
        throw const FormatException('Missing Stack pagination');
      }
      final link = page['next'] as String?;
      final following = link == null ? null : _pageLink(base, link);
      if (following != null &&
          int.parse(following.queryParameters['page']!) <=
              int.parse(uri.queryParameters['page'] ?? '1')) {
        throw const FormatException('Stack pagination did not advance');
      }
      final items = (json['data'] as List)
          .cast<StackJson>()
          .map(StackSummary.fromJson)
          .toList(growable: false);
      if (section == StackSection.created &&
          items.any((item) => item.ownerId != access.lease.owner.id)) {
        throw const FormatException('Invalid Stack owner');
      }
      return (items: items, next: following);
    });
  }

  Uri _pageLink(Uri base, String link) {
    final uri = base.resolve(link);
    final page = int.tryParse(uri.queryParameters['page'] ?? '');
    if (uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != base.path ||
        page == null ||
        page < 1 ||
        page * 24 > 12000) {
      throw const StackFailure('stack_invalid_pagination');
    }
    // The link determines only the next page; retain the requested ratings.
    return base.replace(
      queryParameters: {...base.queryParametersAll, 'page': '$page'},
    );
  }

  Future<StackDetail> detail(
    StackAccess access,
    int id, {
    required bool owned,
  }) async {
    final uri = Uri.parse('$_base${owned ? _my : '/stacks'}/${stackId(id)}');
    final json = await _request(
      access,
      uri,
      authenticated: owned,
      detailRead: true,
    );
    return _detail(json, access, owned: owned, id: id);
  }

  Future<List<OwnedSeriesStack>> forSeries(StackAccess access, int id) async {
    final json = await _request(
      access,
      Uri.parse('$_base/my/series/${stackId(id)}/stacks'),
    );
    return _parse(
      () => (json['data'] as List)
          .cast<StackJson>()
          .map(
            (item) => (
              id: stackId(item['id']),
              title: item['title'] as String,
              canAdd: item['can_add'] as bool,
              contains: (item['rank'] as num?) != null,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Map<int, StackViewer>> statuses(
    StackAccess access,
    Iterable<int> ids,
  ) async {
    final requested = ids.map(stackId).toSet();
    if (requested.isEmpty || requested.length > 50) {
      throw ArgumentError('Request one to 50 Stack statuses');
    }
    final json = await _request(
      access,
      ApiClient.uri('$_base$_my/status', {'id': requested}),
    );
    return _parse(() {
      final result = <int, StackViewer>{};
      for (final row in (json['data'] as List).cast<StackJson>()) {
        final state = StackViewer.fromJson(row);
        if (!requested.contains(state.id) || result.containsKey(state.id)) {
          throw const FormatException('Unexpected Stack status ID');
        }
        result[state.id] = state;
      }
      if (result.length != requested.length) {
        throw const FormatException('Missing Stack status');
      }
      return result;
    });
  }

  Future<StackViewer> relationship(
    StackAccess access,
    int id,
    StackAction action,
  ) async {
    final json = await _request(
      access,
      Uri.parse('$_base$_my/${action.path}/${stackId(id)}'),
      method: action.method,
    );
    return _parse(() {
      final status = StackViewer.fromJson(json['data'] as StackJson);
      if (status.id != id) throw const FormatException('Incorrect Stack ID');
      return status;
    }, write: true);
  }

  Future<StackDetail> create(StackAccess access, String title) async {
    title = title.trim();
    if (title.isEmpty || title.runes.length > 200) {
      throw const StackFailure('stack_title_limit');
    }
    final response = await _request(
      access,
      Uri.parse('$_base$_my'),
      method: 'POST',
      body: {'title': title},
    );
    final detail = _detail(response, access, owned: true, write: true);
    if (detail.summary.visibility != StackVisibility.draft) {
      throw const StackFailure('stack_outcome_uncertain', uncertain: true);
    }
    return detail;
  }

  Future<StackDetail> update(StackAccess access, StackDraft draft) async {
    final error = draft.validationError;
    if (error != null) throw StackFailure(error);
    final base = draft.base;
    _requireEditable(access, base);
    final id = base.summary.id;
    final response = await _request(
      access,
      Uri.parse('$_base$_my/$id'),
      method: 'PUT',
      body: draft.toJson(),
    );
    return _detail(response, access, owned: true, id: id, write: true);
  }

  Future<void> delete(StackAccess access, StackDetail base) async {
    _requireEditable(access, base);
    final id = base.summary.id;
    final latest = await detail(access, id, owned: true);
    if (latest.revision != base.revision) {
      throw const StackFailure('stack_conflict', status: 409);
    }
    await _request(access, Uri.parse('$_base$_my/$id'), method: 'DELETE');
  }

  void _requireEditable(StackAccess access, StackDetail detail) {
    check(access, write: true);
    if (detail.summary.ownerId != access.lease.owner.id ||
        detail.revision == null) {
      throw const StackFailure('stack_owner_required');
    }
  }

  StackDetail _detail(
    StackJson json,
    StackAccess access, {
    required bool owned,
    int? id,
    bool write = false,
  }) => _parse(() {
    final detail = StackDetail.fromJson(
      json['data'] as StackJson,
      owned: owned,
    );
    if ((id != null && detail.summary.id != id) ||
        (owned && detail.summary.ownerId != access.lease.owner.id)) {
      throw const FormatException('Incorrect Stack identity');
    }
    return detail;
  }, write: write);

  Future<StackJson> _request(
    StackAccess access,
    Uri uri, {
    String method = 'GET',
    bool authenticated = true,
    bool detailRead = false,
    StackJson? body,
  }) async {
    final write = method != 'GET';
    check(access, write: write);
    final waited = await _rateLimit.waitForCooldown();
    if (waited) await _rateLimit.waitForRetryAdmission();
    check(access, write: write);
    String? token;
    try {
      if (authenticated) token = await auth.getValidAccessToken();
    } on AppException {
      check(access, write: write);
      rethrow;
    }
    check(access, write: write);

    Future<http.Response> send() {
      check(access, write: write);
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers['User-Agent'] = AppConstants.userAgent;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: AppConstants.networkTimeoutSeconds));
    }

    http.Response response;
    try {
      response = await send();
      check(access, write: write);
      if (!write && response.statusCode == 401 && token != null) {
        token = await auth.recoverAfterUnauthorized(token);
        response = await send();
      }
    } on StackFailure {
      rethrow;
    } on AppException {
      check(access, write: write);
      rethrow;
    } catch (_) {
      check(access, write: write);
      reportApiOutcome(
        ok: false,
        context: 'stacks',
        error: 'transport failure',
      );
      throw StackFailure(
        write ? 'stack_outcome_uncertain' : 'stack_request_failed',
        uncertain: write,
      );
    }
    check(access, write: write);
    final status = response.statusCode;
    reportApiOutcome(ok: status < 500, context: 'stacks', statusCode: status);
    if (status == 429) {
      _rateLimit.updateFromRetryAfter(
        RateLimitCoordinator.retryAfterHeader(response.headers),
      );
    }
    if (status != 200) {
      String? providerCode;
      var verifiedError = false;
      try {
        final error = jsonDecode(response.body) as StackJson;
        if (error['status'] == status && error['message'] is String) {
          providerCode = error['code'] as String?;
          verifiedError = true;
        } else if (status == 404) {
          throw const FormatException('Invalid Stack not-found response');
        }
      } catch (_) {
        if (status == 404) throw const StackFailure('stack_invalid_response');
      }
      throw StackFailure(
        switch (providerCode) {
          'stack_locked' => 'stack_locked',
          'spoiler_locked' => 'stack_spoiler_locked',
          'username_required' => 'stack_username_required',
          'too_few_entries' => 'stack_publication_minimum',
          'series_unavailable' => 'stack_series_unavailable',
          'rating_below_floor' ||
          'rating_below_minimum' => 'stack_rating_limit',
          _ => switch (status) {
            401 || 403 => 'stack_permission_required',
            404 => 'stack_unavailable',
            409 => 'stack_conflict',
            429 => 'stack_rate_limited',
            >= 500 when write => 'stack_outcome_uncertain',
            _ => 'stack_request_failed',
          },
        },
        status: status,
        uncertain: write && status >= 500,
        verifiedDetailDenial:
            detailRead && verifiedError && (status == 403 || status == 404),
      );
    }
    return _parse(() {
      final envelope = jsonDecode(response.body) as StackJson;
      if (envelope['status'] != status) {
        throw const FormatException('Stack response status mismatch');
      }
      return envelope;
    }, write: write);
  }

  T _parse<T>(T Function() parse, {bool write = false}) {
    try {
      return parse();
    } on StackFailure {
      rethrow;
    } catch (_) {
      throw StackFailure(
        write ? 'stack_outcome_uncertain' : 'stack_invalid_response',
        uncertain: write,
      );
    }
  }

  void dispose() => _client.close();
}
