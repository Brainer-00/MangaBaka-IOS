import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/network/api_client.dart';
import 'package:mangabaka_app/core/network/api_envelope.dart';
import 'package:mangabaka_app/features/collections/models/edition.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';

/// One page of a paginated list, with whether another follows.
///
/// These endpoints report `pagination.next` rather than a total, so "is there
/// more" is the only thing a caller can know.
class PagedList<T> {
  final List<T> items;
  final bool hasNext;

  const PagedList(this.items, {required this.hasNext});
}

/// Reads the collection and edition endpoints.
///
/// A *collection* is one publisher's run of a series in one edition (its
/// volumes, format and medium); its *works* are the individual releases. An
/// *edition* is the label the collection carries ("Omnibus Edition").
class CollectionService {
  static const String _base = AppConstants.baseApiUrl;

  final ApiClient _api;

  CollectionService({http.Client? client, ApiClient? api})
    : _api = api ?? ApiClient(healthContext: 'collections', client: client);

  static bool _hasNext(dynamic json) {
    final pagination = json is Map ? json['pagination'] : null;
    return pagination is Map && pagination['next'] != null;
  }

  /// Every edition. There are few dozen, so all pages are read up front.
  Future<List<Edition>> fetchEditions() async {
    final all = <Edition>[];
    for (var page = 1; page <= 5; page++) {
      final result = await _api.getJson(
        ApiClient.uri('$_base/editions/all', {'page': page, 'limit': 50}),
        operation: 'fetch editions',
        parse: (json) => PagedList(
          parseDataList(json, Edition.fromJson),
          hasNext: _hasNext(json),
        ),
      );
      all.addAll(result.items);
      if (!result.hasNext) break;
    }
    return all;
  }

  /// A publisher's collections, [page] at a time.
  Future<PagedList<SeriesCollection>> fetchPublisherCollections(
    String publisherId, {
    int page = 1,
    int limit = 25,
  }) {
    return _api.getJson(
      ApiClient.uri('$_base/publishers/$publisherId/collections', {
        'page': page,
        'limit': limit,
      }),
      operation: 'fetch publisher collections',
      parse: (json) => PagedList(
        parseDataList(json, SeriesCollection.fromJson),
        hasNext: _hasNext(json),
      ),
    );
  }

  /// The releases (volumes, boxed sets, extras) in a collection.
  Future<PagedList<SeriesWork>> fetchCollectionWorks(
    String collectionId, {
    int page = 1,
    int limit = 30,
  }) {
    return _api.getJson(
      ApiClient.uri('$_base/collections/$collectionId/works', {
        'page': page,
        'limit': limit,
      }),
      operation: 'fetch collection works',
      parse: (json) => PagedList(
        parseDataList(json, SeriesWork.fromJson),
        hasNext: _hasNext(json),
      ),
    );
  }

  void dispose() => _api.close();
}
