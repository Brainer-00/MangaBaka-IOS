import 'package:flutter/foundation.dart';

import '../../core/database/database.dart' show LibraryCacheLease;
import 'stack_models.dart';
import 'stack_service.dart';

enum StackWriteResult { confirmed, rejected, cancelled, uncertain, invalidated }

final class StackSectionState {
  List<StackSummary> items = const [];
  Uri? next;
  bool loaded = false;
  bool loading = false;
  bool stale = false;
  String? error;
  int _read = 0;
}

final class StackController extends ChangeNotifier {
  StackController(this.service) : _authorization = service.authorization {
    service.auth.addListener(_accountChanged);
  }

  final StackService service;
  StackAccess? _authorization;
  StackAccess? get authorization =>
      !_disposed && _authorization == service.authorization
      ? _authorization
      : null;
  LibraryCacheLease? get lease => service.auth.libraryLease;
  bool get canRead => authorization != null && service.auth.canReadStacks;
  bool get canWrite => canRead && service.auth.canWriteStacks;
  bool get signedIn => service.auth.isLoggedIn;

  final _sections = <StackSection, StackSectionState>{
    for (final section in StackSection.values) section: StackSectionState(),
  };
  final _summaries = <int, StackSummary>{};
  final _listCoverRatings = Expando<String>();
  final _details = <int, StackDetail>{};
  final _status = <int, StackViewer>{};
  final _statusVersion = <int, int>{};
  final _detailVersion = <int, int>{};
  final _busy = <int>{};
  final _uncertain = <int>{};
  final _staleDetails = <int>{};
  final _unavailableDetails = <int>{};
  final _detailAccessVersion = <int, int>{};
  final _deleted = <int>{};
  final _writeErrors = <int, String>{};
  int _sequence = 0;
  bool _disposed = false;
  bool _creating = false;
  bool _createUncertain = false;

  StackSectionState section(StackSection section) => _sections[section]!;
  bool hasVerifiedCovers(StackSummary stack, List<String> ratings) =>
      _listCoverRatings[stack] == ratings.join(',');
  StackViewer? viewer(int id) => canRead ? _status[id] : null;
  StackDetail? detail(int id) => canRead ? _details[id] : null;
  bool busy(int id) => _busy.contains(id);
  bool uncertain(int id) => _uncertain.contains(id);
  bool isDetailStale(int id) => _staleDetails.contains(id);
  bool isDetailUnavailable(int id) => _unavailableDetails.contains(id);
  int detailAccessVersion(int id) => _detailAccessVersion[id] ?? 0;
  bool wasDeleted(int id) => _deleted.contains(id);
  String? writeError(int id) => _writeErrors[id];
  bool get createUncertain => _createUncertain;

  bool live(LibraryCacheLease? owner) =>
      !_disposed && owner != null && identical(owner, lease);

  bool liveAccess(StackAccess? access) =>
      access != null && authorization == access;

  void _accountChanged() {
    final current = service.authorization;
    if (current != _authorization) {
      _authorization = current;
      _sections.updateAll((_, _) => StackSectionState());
      _summaries.clear();
      _details.clear();
      _status.clear();
      _statusVersion.clear();
      _detailVersion.clear();
      _busy.clear();
      _uncertain.clear();
      _staleDetails.clear();
      _unavailableDetails.clear();
      _detailAccessVersion.clear();
      _deleted.clear();
      _creating = false;
      _createUncertain = false;
      _writeErrors.clear();
    }
    notifyListeners();
  }

  Future<void> refresh(StackAccess access, List<String> ratings) async {
    await Future.wait([
      for (final section in StackSection.values)
        loadSection(access, section, ratings),
    ]);
  }

  Future<void> loadSection(
    StackAccess access,
    StackSection kind,
    List<String> ratings, {
    bool more = false,
  }) async {
    if (!liveAccess(access) || !canRead) return;
    final section = _sections[kind]!;
    if (more && (section.next == null || section.loading || section.stale)) {
      return;
    }
    final request = ++_sequence;
    section._read = request;
    section.loading = true;
    section.error = null;
    notifyListeners();
    bool current() =>
        liveAccess(access) &&
        canRead &&
        section._read == request &&
        identical(_sections[kind], section);
    try {
      final page = await service.list(
        access,
        kind,
        ratings,
        next: more ? section.next : null,
      );
      if (!current()) return;
      for (final item in page.items) {
        _listCoverRatings[item] = ratings.join(',');
      }
      final rows = {
        if (more)
          for (final item in section.items) item.id: item,
        for (final item in page.items) item.id: item,
        // A write that settled while the page was in flight takes precedence
        // over a list that may have been captured before that write.
        for (final item in section.items)
          if ((_statusVersion[item.id] ?? 0) > request ||
              (_detailVersion[item.id] ?? 0) > request ||
              busy(item.id))
            item.id: item,
      };
      for (final item in rows.values) {
        if (!_deleted.contains(item.id) &&
            (_detailVersion[item.id] ?? 0) <= request) {
          _summaries[item.id] = item;
        }
      }
      section.items = List.unmodifiable(
        rows.values
            .where((item) {
              if (_deleted.contains(item.id)) return false;
              final state = _status[item.id];
              if (state == null ||
                  ((_statusVersion[item.id] ?? 0) <= request &&
                      !busy(item.id))) {
                return true;
              }
              return _belongs(kind, state);
            })
            .map((item) => _summaries[item.id] ?? item),
      );
      section.next = page.next;
      section.loaded = true;
      section.stale = false;
      if (kind == StackSection.created && !more) _createUncertain = false;
      notifyListeners();
      if (page.items.isNotEmpty) {
        final states = await service.statuses(
          access,
          page.items.map((item) => item.id),
        );
        if (!current()) return;
        for (final state in states.values) {
          if (!busy(state.id)) _applyStatus(state, request, insert: false);
        }
      }
    } catch (error) {
      if (!current()) return;
      section.error = error is StackFailure
          ? error.code
          : 'stack_request_failed';
      section.stale = section.loaded && !more;
    } finally {
      if (current()) {
        section.loading = false;
        notifyListeners();
      }
    }
  }

  bool _belongs(StackSection section, StackViewer state) => switch (section) {
    StackSection.created => true,
    StackSection.saved => state.saved,
    StackSection.following => state.followed,
  };

  void _applyStatus(StackViewer state, int ticket, {required bool insert}) {
    final id = state.id;
    if (_deleted.contains(id) ||
        isDetailUnavailable(id) ||
        (_statusVersion[id] ?? 0) > ticket) {
      return;
    }
    _statusVersion[id] = ticket;
    _status[id] = state;
    _uncertain.remove(id);
    for (final kind in [StackSection.saved, StackSection.following]) {
      final section = _sections[kind]!;
      final exists = section.items.any((item) => item.id == id);
      if (exists && !_belongs(kind, state)) {
        section.items = List.unmodifiable(
          section.items.where((item) => item.id != id),
        );
      } else if (insert && !exists && _belongs(kind, state)) {
        final summary = _summaries[id];
        if (summary != null) {
          section.items = List.unmodifiable([summary, ...section.items]);
        }
      }
    }
  }

  Future<StackViewer?> refreshStatus(StackAccess access, int id) async {
    if (!liveAccess(access)) return null;
    if (busy(id) || isDetailUnavailable(id)) return viewer(id);
    final request = ++_sequence;
    final StackViewer status;
    try {
      status = (await service.statuses(access, [id]))[id]!;
    } catch (_) {
      if (!liveAccess(access)) return null;
      rethrow;
    }
    if (!liveAccess(access) || !canRead) return null;
    if (!busy(id)) {
      _applyStatus(status, request, insert: true);
      notifyListeners();
    }
    return viewer(id);
  }

  Future<StackDetail?> readDetail(
    StackAccess access,
    int id, {
    required bool owned,
  }) async {
    if (!liveAccess(access)) return null;
    if (busy(id)) return detail(id);
    final request = ++_sequence;
    final accessVersion = detailAccessVersion(id);
    try {
      final fresh = await service.detail(access, id, owned: owned);
      if (!liveAccess(access) || !canRead) return null;
      if (!busy(id) && detailAccessVersion(id) == accessVersion) {
        _applyDetail(fresh, request);
        notifyListeners();
      }
      return detail(id);
    } catch (error) {
      if (!liveAccess(access)) return null;
      if (!busy(id) || _verifiedDetailDenial(error)) {
        _recordDetailFailure(id, error, request);
        notifyListeners();
      }
      rethrow;
    }
  }

  bool _verifiedDetailDenial(Object error) =>
      error is StackFailure && error.verifiedDetailDenial;

  void _recordDetailFailure(int id, Object error, int ticket) {
    if (_deleted.contains(id) || (_detailVersion[id] ?? 0) > ticket) return;
    _detailVersion[id] = ticket;
    if (_verifiedDetailDenial(error)) {
      _unavailableDetails.add(id);
      _details.remove(id);
      _staleDetails.remove(id);
      _status.remove(id);
      _detailAccessVersion[id] = ticket;
      _statusVersion[id] = ++_sequence;
    } else if (_details.containsKey(id)) {
      _staleDetails.add(id);
    }
  }

  void _applyDetail(StackDetail detail, int ticket, {bool created = false}) {
    final summary = detail.summary;
    final id = summary.id;
    if (_deleted.contains(id) || (_detailVersion[id] ?? 0) > ticket) return;
    _detailVersion[id] = ticket;
    _details[id] = detail;
    _summaries[id] = summary;
    _staleDetails.remove(id);
    _unavailableDetails.remove(id);
    for (final section in _sections.values) {
      section.items = List.unmodifiable(
        section.items.map((item) => item.id == id ? summary : item),
      );
    }
    final owned = _sections[StackSection.created]!;
    if (created && !owned.items.any((item) => item.id == id)) {
      owned.items = List.unmodifiable([summary, ...owned.items]);
    }
  }

  Future<StackWriteResult> changeRelationship(
    StackAccess access,
    StackSummary stack,
    StackViewer expected,
    StackAction action, {
    Future<bool> Function()? confirmCoupledRemoval,
  }) async {
    if (!liveAccess(access)) return StackWriteResult.invalidated;
    final id = stack.id;
    // A control may have been waiting for a confirmation dialog when a
    // different route updated the same Stack.
    final current = viewer(id);
    if (current == null ||
        current.relationship != expected.relationship ||
        current.voted != expected.voted ||
        action.matches(current) ||
        !canWrite ||
        uncertain(id) ||
        isDetailStale(id) ||
        isDetailUnavailable(id) ||
        !_busy.add(id)) {
      return StackWriteResult.rejected;
    }
    _summaries.putIfAbsent(id, () => stack);
    _writeErrors.remove(id);
    notifyListeners();
    try {
      if (action == StackAction.unsave) {
        for (var check = 0; check < (expected.followed ? 2 : 1); check++) {
          final status = (await service.statuses(access, [id]))[id]!;
          if (!liveAccess(access)) return StackWriteResult.invalidated;
          if (isDetailUnavailable(id) || isDetailStale(id)) {
            return StackWriteResult.rejected;
          }
          _applyStatus(status, ++_sequence, insert: true);
          if (status.relationship != expected.relationship) {
            _writeErrors[id] = 'stack_relationship_changed';
            return StackWriteResult.rejected;
          }
          if (check == 0 && status.followed) {
            notifyListeners();
            final approved = await confirmCoupledRemoval?.call() ?? false;
            if (!liveAccess(access)) return StackWriteResult.invalidated;
            if (!approved) return StackWriteResult.cancelled;
          }
        }
      }
      final status = await service.relationship(access, id, action);
      if (!liveAccess(access) || !canRead) return StackWriteResult.invalidated;
      _applyStatus(status, ++_sequence, insert: true);
      return action.matches(status)
          ? StackWriteResult.confirmed
          : StackWriteResult.rejected;
    } on StackFailure catch (error) {
      if (!liveAccess(access)) return StackWriteResult.invalidated;
      _writeErrors[id] = error.code;
      if (!error.uncertain) return StackWriteResult.rejected;
      _uncertain.add(id);
      try {
        final status = (await service.statuses(access, [id]))[id]!;
        if (!liveAccess(access) || !canRead) {
          return StackWriteResult.invalidated;
        }
        _applyStatus(status, ++_sequence, insert: true);
        if (action.matches(status)) return StackWriteResult.confirmed;
      } catch (_) {
        // Keep writes disabled until a later status read verifies both flags.
      }
      return liveAccess(access)
          ? StackWriteResult.uncertain
          : StackWriteResult.invalidated;
    } catch (_) {
      if (!liveAccess(access)) return StackWriteResult.invalidated;
      _writeErrors[id] = 'stack_request_failed';
      return StackWriteResult.rejected;
    } finally {
      if (liveAccess(access)) {
        _busy.remove(id);
        notifyListeners();
      }
    }
  }

  Future<StackDetail?> create(StackAccess access, String title) async {
    if (!liveAccess(access) || !canWrite || _creating || _createUncertain) {
      return null;
    }
    _creating = true;
    try {
      final draft = await service.create(access, title);
      if (!liveAccess(access) || !canRead) return null;
      _applyDetail(draft, ++_sequence, created: true);
      return draft;
    } on StackFailure catch (error) {
      if (!liveAccess(access)) return null;
      _createUncertain = error.uncertain;
      rethrow;
    } finally {
      if (liveAccess(access)) {
        _creating = false;
        notifyListeners();
      }
    }
  }

  Future<StackDetail?> update(StackAccess access, StackDraft draft) async {
    final base = draft.base;
    final id = base.summary.id;
    final accessVersion = detailAccessVersion(id);
    _beginDetailWrite(access, base);
    try {
      final saved = await service.update(access, draft);
      if (!liveAccess(access) ||
          !canRead ||
          detailAccessVersion(id) != accessVersion) {
        return null;
      }
      _applyDetail(saved, ++_sequence);
      return saved;
    } on StackFailure catch (error) {
      if (!liveAccess(access)) return null;
      final fresh = await _reconcileDetailFailure(access, id, error);
      if (!liveAccess(access)) return null;
      if (error.uncertain && fresh != null && draft.matches(fresh)) {
        return fresh;
      }
      rethrow;
    } finally {
      if (liveAccess(access)) {
        _busy.remove(id);
        notifyListeners();
      }
    }
  }

  void _beginDetailWrite(StackAccess access, StackDetail base) {
    final id = base.summary.id;
    if (!liveAccess(access) ||
        !canWrite ||
        isDetailStale(id) ||
        detail(id)?.revision != base.revision ||
        !_busy.add(id)) {
      throw const StackFailure('stack_refresh_required');
    }
    notifyListeners();
  }

  Future<StackDetail?> _reconcileDetailFailure(
    StackAccess access,
    int id,
    StackFailure error,
  ) async {
    if (error.verifiedDetailDenial) {
      _recordDetailFailure(id, error, ++_sequence);
      return null;
    }
    if (!error.uncertain && error.status != 409) return null;
    if (!isDetailUnavailable(id)) _staleDetails.add(id);
    final request = ++_sequence;
    final accessVersion = detailAccessVersion(id);
    try {
      final fresh = await service.detail(access, id, owned: true);
      if (liveAccess(access) &&
          canRead &&
          detailAccessVersion(id) == accessVersion) {
        _applyDetail(fresh, request);
        return fresh;
      }
    } catch (readback) {
      if (liveAccess(access)) _recordDetailFailure(id, readback, request);
    }
    return null;
  }

  Future<bool> delete(StackAccess access, StackDetail base) async {
    final id = base.summary.id;
    _beginDetailWrite(access, base);
    try {
      await service.delete(access, base);
      if (!liveAccess(access)) return false;
      _removeDeleted(id);
      return true;
    } on StackFailure catch (error) {
      if (!liveAccess(access)) return false;
      // A missing Stack after an uncertain DELETE could also be an access loss.
      await _reconcileDetailFailure(access, id, error);
      if (!liveAccess(access)) return false;
      rethrow;
    } finally {
      if (liveAccess(access)) {
        _busy.remove(id);
        notifyListeners();
      }
    }
  }

  void _removeDeleted(int id) {
    _deleted.add(id);
    _detailAccessVersion[id] = ++_sequence;
    _details.remove(id);
    _staleDetails.remove(id);
    _unavailableDetails.remove(id);
    _summaries.remove(id);
    _status.remove(id);
    for (final section in _sections.values) {
      section.items = List.unmodifiable(
        section.items.where((item) => item.id != id),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    service.auth.removeListener(_accountChanged);
    service.dispose();
    super.dispose();
  }
}
