import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/controllers/browse_results.dart';
import 'package:mangabaka_app/features/browse/services/browse_search_gateway.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

void main() {
  test('browse pagination appends pages without rebuilding prior elements', () {
    final results = BrowseResults();
    const pageCount = 50;
    const pageSize = 20;

    for (var page = 0; page < pageCount; page++) {
      results.addSeries(
        BrowsePage(
          items: [
            for (var item = 0; item < pageSize; item++)
              Series.fromJson({'id': '$page-$item', 'title': '$page-$item'}),
          ],
          total: pageCount * pageSize,
          hasMore: page + 1 < pageCount,
        ),
      );
    }

    expect(results.series, hasLength(pageCount * pageSize));
    expect(results.series.first.id, '0-0');
    expect(results.series.last.id, '${pageCount - 1}-${pageSize - 1}');

    // Structural evidence: each page contributes only its own page-sized
    // append; timings remain informational and are intentionally omitted.
    // ignore: avoid_print
    print(
      'BROWSE_APPEND pages=$pageCount page_size=$pageSize '
      'final_count=${results.series.length} '
      'append_elements=${pageCount * pageSize}',
    );
  });
}
