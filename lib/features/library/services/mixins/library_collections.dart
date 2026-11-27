part of 'library_crud_mixin.dart';

class LibraryCollection {
  const LibraryCollection(this.list, this.members, {this.membersStale = false});

  final AccountLibraryList list;

  /// Null means the member snapshot failed validation or could not be loaded.
  final List<LibraryEntry>? members;
  final bool membersStale;
  bool get hasCurrentMembers => members != null && !membersStale;

  LibraryCollection retainMembersFrom(LibraryCollection previous) =>
      members == null && previous.members != null
      ? LibraryCollection(list, previous.members, membersStale: true)
      : this;
}

enum CollectionWriteOutcome { saved, refreshPending, uncertain, rejected }

class CollectionMembershipResult {
  const CollectionMembershipResult(
    this.confirmed,
    this.requested,
    this.outcome,
  );

  /// Entries whose requested membership was acknowledged by the API.
  final int confirmed;
  final int requested;
  final CollectionWriteOutcome outcome;
}

extension LibraryCollections on LibraryCrudMixin {
  static const _key = LibraryCrudMixin._collectionsKey;
  static const _entryPath = '/v2/my/library';
  static const _listsPath = '$_entryPath/lists';
  static const _bulkPath = '$_entryPath/bulk';

  static final _space = RegExp(
    r'[\s\u0085\u00a0\u1680\u2000-\u200a'
    r'\u2028\u2029\u202f\u205f\u3000]+',
    unicode: true,
  );
  static final _invisible = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

  static String normalizeListName(String name) => name
      .replaceAllMapped(
        _space,
        (match) => match[0]!.contains('\u3000') ? '\u3000' : ' ',
      )
      .trim();

  static String listNameKey(String name) =>
      normalizeListName(name).replaceAll('\u3000', ' ').toLowerCase();

  static bool validListName(String name) =>
      name.isNotEmpty && name.runes.length <= 255 && !_invisible.hasMatch(name);

  Uri _collectionUri(String path) =>
      Uri.parse(LibraryConstants.baseUrl).replace(path: path);

  Future<List<LibraryCollection>> fetchCollections(LibraryCacheLease lease) =>
      _enqueue([_key], (lease) async {
        final lists = await _fetchAccountLibraryLists(lease, strict: true);
        final result = <LibraryCollection>[];
        for (final list in lists) {
          try {
            final members = list.seriesCount == 0
                ? const <LibraryEntry>[]
                : await _readCollectionMembers(lease, list);
            result.add(LibraryCollection(list, members));
          } on Exception {
            checkLease(lease);
            result.add(LibraryCollection(list, null));
          }
        }
        checkLease(lease);
        return List.unmodifiable(result);
      }, originalLease: lease);

  Future<List<LibraryEntry>> _readCollectionMembers(
    LibraryCacheLease lease,
    AccountLibraryList list,
  ) async {
    final scope = {'list': '${list.id}'};
    final base = _collectionUri(
      _entryPath,
    ).replace(queryParameters: {...scope, 'limit': '100'});
    final rows = await _collectionPages<LibraryEntry, String>(
      lease,
      base,
      (item) => _parseCollectionMember(item, lease, list.id),
      (entry) => entry.series.id,
      expectedCount: list.seriesCount,
      scope: scope,
    );
    if (rows.map((entry) => entry.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate collection entry ID');
    }
    return rows;
  }

  Future<List<T>> _collectionPages<T, K>(
    LibraryCacheLease lease,
    Uri base,
    T Function(Object?) parse,
    K Function(T) key, {
    bool strict = true,
    int? expectedCount,
    Map<String, String> scope = const {},
  }) async {
    var uri = base;
    final visited = <Uri>{};
    final values = <K, T>{};
    while (visited.length < AppConstants.libraryMaxPages && visited.add(uri)) {
      final response = await _read(lease, uri);
      if (response.statusCode != 200) {
        throw ApiException(
          message: 'Collection read failed',
          statusCode: response.statusCode,
        );
      }
      final envelope = _editorEnvelope(response);
      final data = envelope['data'];
      final pagination = envelope['pagination'];
      if (data is! List ||
          pagination is! Map ||
          !pagination.containsKey('next')) {
        throw const FormatException('Invalid collection page');
      }
      final count = pagination['count'];
      if (strict || count != null) {
        if (count is! int ||
            count < 0 ||
            (expectedCount != null && count != expectedCount)) {
          throw const FormatException('Invalid collection count');
        }
        expectedCount = count;
      }
      for (final item in data) {
        final value = parse(item);
        final id = key(value);
        if (values.containsKey(id)) {
          throw const FormatException('Duplicate collection record');
        }
        values[id] = value;
      }
      final next = pagination['next'];
      if (next == null) {
        if (expectedCount != null && values.length != expectedCount) break;
        return List.unmodifiable(values.values);
      }
      if (next is! String ||
          next.isEmpty ||
          data.isEmpty ||
          (expectedCount != null && values.length >= expectedCount)) {
        throw const FormatException('Invalid collection continuation');
      }
      uri = uri.resolve(next);
      if (uri.scheme != base.scheme ||
          uri.origin != base.origin ||
          uri.path != base.path ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          scope.entries.any((entry) {
            final actual = uri.queryParametersAll[entry.key];
            return actual?.length != 1 || actual!.single != entry.value;
          }) ||
          (scope.isNotEmpty && uri.queryParameters.containsKey('list_not'))) {
        throw const FormatException('Unexpected collection continuation URL');
      }
    }
    throw const FormatException('Incomplete collection pagination');
  }

  AccountLibraryList _parseAccountList(Object? item, {bool strict = false}) {
    if (item is! Map ||
        !_validEditorId(item['id']) ||
        item['name'] is! String ||
        (item['name'] as String).trim().isEmpty ||
        item['is_private'] is! bool) {
      throw const FormatException('Invalid Library list');
    }
    final count = item['series_count'];
    final created = item['created_at'];
    if ((strict && (count == null || !item.containsKey('created_at'))) ||
        (count != null && (count is! int || count < 0)) ||
        (created != null &&
            (created is! String || DateTime.tryParse(created) == null))) {
      throw const FormatException('Invalid Library list metadata');
    }
    return AccountLibraryList(
      id: item['id'] as int,
      name: item['name'] as String,
      isPrivate: item['is_private'] as bool,
      seriesCount: count as int?,
      createdAt: created == null ? null : DateTime.parse(created as String),
    );
  }

  LibraryEntry _parseCollectionMember(
    Object? item,
    LibraryCacheLease lease,
    int listId,
  ) {
    if (item is! Map) throw const FormatException('Invalid collection member');
    final entry = item['entry'];
    final lists = item['lists'];
    final series = item['series'];
    if (entry is! Map<String, dynamic> ||
        entry['user_id'] != lease.owner.id ||
        !_validEditorId(entry['id']) ||
        !_validEditorId(entry['series_id']) ||
        !LibraryEntryDraft.states.contains(entry['state']) ||
        lists is! List ||
        lists.length > 30 ||
        series is! Map<String, dynamic> ||
        series['id'] != entry['series_id']) {
      throw const FormatException('Invalid collection member identity');
    }
    final ids = <int>{};
    for (final item in lists) {
      if (!ids.add(_parseAccountList(item).id)) {
        throw const FormatException('Duplicate collection membership');
      }
    }
    if (!ids.contains(listId)) {
      throw const FormatException('Series does not belong to this list');
    }
    try {
      final parsed = LibraryEntry.fromJson({...entry, 'series': series});
      if (parsed.series.title.isEmpty || series['content_rating'] is! String) {
        throw const FormatException('Incomplete collection series metadata');
      }
      return parsed;
    } on TypeError {
      throw const FormatException('Invalid collection member data');
    }
  }

  Future<CollectionWriteOutcome> saveCollection(
    LibraryCacheLease lease, {
    AccountLibraryList? original,
    required String name,
    required bool isPrivate,
  }) => _enqueue([_key], (lease) async {
    final listId = original?.id;
    final normalized = normalizeListName(name);
    final rename =
        original == null || normalized != normalizeListName(original.name);
    final changePrivacy = original == null || original.isPrivate != isPrivate;
    if (!rename && !changePrivacy) return CollectionWriteOutcome.saved;
    if (rename && !validListName(normalized)) {
      throw ArgumentError('Invalid list name');
    }
    if (listId != null && !_validEditorId(listId)) {
      throw ArgumentError('Invalid list ID');
    }
    final lists = await _fetchAccountLibraryLists(lease, strict: true);
    final latest = lists.where((item) => item.id == listId).firstOrNull;
    if (original != null) {
      if (latest == null) {
        throw ApiException(message: 'List no longer exists', statusCode: 404);
      }
      if ((rename &&
              latest.name != original.name &&
              latest.name != normalized) ||
          (changePrivacy &&
              latest.isPrivate != original.isPrivate &&
              latest.isPrivate != isPrivate)) {
        throw _metadataConflict();
      }
    }
    final sendName = rename && latest?.name != normalized;
    final sendPrivacy = changePrivacy && latest?.isPrivate != isPrivate;
    if (!sendName && !sendPrivacy) {
      collectionsRevision.value++;
      return CollectionWriteOutcome.saved;
    }
    if (sendName &&
        lists.any(
          (item) =>
              item.id != listId &&
              listNameKey(item.name) == listNameKey(normalized),
        )) {
      throw ApiException(
        message: 'List name already exists',
        statusCode: 400,
        code: 'DUPLICATE_LIST_NAME',
      );
    }
    try {
      final response = await _send(
        lease,
        '',
        uri: _collectionUri(
          listId == null ? _listsPath : '$_listsPath/$listId',
        ),
        method: listId == null ? 'POST' : 'PATCH',
        success: {200},
        failureCode: 'COLLECTION_WRITE_FAILED',
        body: {
          if (sendName) 'name': normalized,
          if (sendPrivacy) 'is_private': isPrivate,
        },
      );
      final saved = _parseAccountList(
        _editorEnvelope(response)['data'],
        strict: true,
      );
      if ((listId != null && saved.id != listId) ||
          (listId == null && lists.any((item) => saved.id == item.id)) ||
          (sendName && saved.name != normalized) ||
          (sendPrivacy && saved.isPrivate != isPrivate)) {
        throw const FormatException('Unexpected list write response');
      }
      return CollectionWriteOutcome.saved;
    } on Exception catch (error) {
      checkLease(lease);
      if (!_ambiguousCollectionWrite(error)) rethrow;
      await _readAfterUncertainWrite(lease);
      return CollectionWriteOutcome.uncertain;
    } finally {
      if (identical(currentLease, lease)) collectionsRevision.value++;
    }
  }, originalLease: lease);

  Future<CollectionWriteOutcome> deleteCollection(
    LibraryCacheLease lease,
    AccountLibraryList confirmed,
  ) => _enqueue([_key], (lease) async {
    final listId = confirmed.id;
    if (!_validEditorId(listId)) throw ArgumentError('Invalid list ID');
    final lists = await _fetchAccountLibraryLists(lease, strict: true);
    final latest = lists.where((item) => item.id == listId).firstOrNull;
    if (latest == null ||
        latest.name != confirmed.name ||
        latest.isPrivate != confirmed.isPrivate ||
        latest.seriesCount != confirmed.seriesCount ||
        latest.createdAt != confirmed.createdAt) {
      throw _metadataConflict();
    }
    final resume = pauseSyncForReconciliation(lease);
    try {
      try {
        final response = await _send(
          lease,
          '',
          uri: _collectionUri('$_listsPath/$listId'),
          method: 'DELETE',
          success: {200},
          failureCode: 'COLLECTION_DELETE_FAILED',
        );
        _editorEnvelope(response, requiresData: false);
      } on Exception catch (error) {
        checkLease(lease);
        if (!_ambiguousCollectionWrite(error)) rethrow;
        final lists = await _readAfterUncertainWrite(lease);
        if (lists == null || lists.any((item) => item.id == listId)) {
          return CollectionWriteOutcome.uncertain;
        }
      }
      try {
        await owned.updateListMembership(
          lease,
          listId,
          add: false,
          beforeCommit: () => checkLease(lease),
        );
      } on Exception {
        checkLease(lease);
        return CollectionWriteOutcome.refreshPending;
      }
      return CollectionWriteOutcome.saved;
    } finally {
      resume();
      if (identical(currentLease, lease)) collectionsRevision.value++;
    }
  }, originalLease: lease);

  ApiException _metadataConflict() => ApiException(
    message: 'List metadata changed',
    statusCode: 409,
    code: 'COLLECTION_METADATA_CONFLICT',
  );

  Future<CollectionMembershipResult> changeCollectionMembership(
    LibraryCacheLease lease, {
    required int listId,
    required Iterable<String> seriesIds,
    required bool add,
  }) {
    if (!_validEditorId(listId)) throw ArgumentError('Invalid list ID');
    final ids = seriesIds.map(_seriesNumber).toSet().toList()..sort();
    if (ids.isEmpty) throw ArgumentError('No selected series');
    return _enqueue([_key, ...ids.map((id) => '$id')], (lease) async {
      var confirmed = 0;
      var outcome = CollectionWriteOutcome.saved;
      final resume = pauseSyncForReconciliation(lease);
      try {
        for (
          var index = 0;
          index < ids.length;
          index += LibraryCrudMixin.batchLimit
        ) {
          checkLease(lease);
          final batch = ids
              .skip(index)
              .take(LibraryCrudMixin.batchLimit)
              .toList();
          try {
            final response = await _send(
              lease,
              '',
              uri: _collectionUri(_bulkPath),
              method: 'POST',
              success: {200},
              failureCode: 'COLLECTION_MEMBERSHIP_FAILED',
              body: {
                'target': {'series_ids': batch},
                'change': {
                  'action': 'update_lists',
                  'add': add ? [listId] : const <int>[],
                  'remove': add ? const <int>[] : [listId],
                },
              },
            );
            final data = _editorEnvelope(response)['data'];
            if (data is! Map ||
                [
                  data['updated'],
                  data['skipped'],
                  data['added'],
                  data['removed'],
                ].any((value) => value is! int || value < 0) ||
                data['updated'] + data['skipped'] != batch.length ||
                data[add ? 'added' : 'removed'] != data['updated'] ||
                data[add ? 'removed' : 'added'] != 0) {
              throw const FormatException('Unexpected bulk membership result');
            }
          } on Exception catch (error) {
            checkLease(lease);
            outcome = !_ambiguousCollectionWrite(error)
                ? CollectionWriteOutcome.rejected
                : await _checkUncertainBatch(lease, listId, batch, add);
            if (outcome != CollectionWriteOutcome.saved) break;
          }
          confirmed += batch.length;
          try {
            await owned.updateListMembership(
              lease,
              listId,
              add: add,
              seriesIds: batch.map((id) => '$id').toSet(),
              beforeCommit: () => checkLease(lease),
            );
          } on Exception {
            checkLease(lease);
            outcome = CollectionWriteOutcome.refreshPending;
            break;
          }
        }
        checkLease(lease);
        return CollectionMembershipResult(confirmed, ids.length, outcome);
      } finally {
        resume();
        if (identical(currentLease, lease)) collectionsRevision.value++;
      }
    }, originalLease: lease);
  }

  Future<CollectionWriteOutcome> _checkUncertainBatch(
    LibraryCacheLease lease,
    int listId,
    List<int> batch,
    bool add,
  ) async {
    final lists = await _readAfterUncertainWrite(lease);
    final target = lists?.where((item) => item.id == listId).firstOrNull;
    if (target != null && target.seriesCount! > 0) {
      try {
        // An active-only listing cannot prove an ambiguous removal of
        // an entry that became inactive.
        final members = await _readCollectionMembers(lease, target);
        final present = members.map((entry) => entry.series.id).toSet();
        if (add && batch.every((id) => present.contains('$id'))) {
          return CollectionWriteOutcome.saved;
        }
      } on Exception {
        checkLease(lease);
      }
    }
    return CollectionWriteOutcome.uncertain;
  }

  bool _ambiguousCollectionWrite(Exception error) =>
      error is NetworkException ||
      error is FormatException ||
      (error is ApiException && error.statusCode >= 500);

  Future<List<AccountLibraryList>?> _readAfterUncertainWrite(
    LibraryCacheLease lease,
  ) async {
    try {
      return await _fetchAccountLibraryLists(lease, strict: true);
    } on Exception {
      checkLease(lease);
      return null;
    }
  }
}
