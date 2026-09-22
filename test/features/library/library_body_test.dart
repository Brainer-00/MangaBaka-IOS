import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/widgets/library_body.dart';
import 'package:mangabaka_app/features/profile/widgets/login/mb_login_prompt.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';

void main() {
  Widget createWidgetUnderTest({
    required bool loggedIn,
    Stream<List<LibraryEntry>>? entriesStream,
    required TabController tabController,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LibraryBody(
          loggedIn: loggedIn,
          entriesStream: entriesStream,
          query: '',
          filters: SearchFilters(),
          tabController: tabController,
          scrollControllers: {},
          onRefresh: () async {},
          onLogin: () {},
          onItemTap: (_) {},
        ),
      ),
    );
  }

  testWidgets('LibraryBody shows MBLoginPrompt when not logged in', (WidgetTester tester) async {
    final tabController = TabController(length: 7, vsync: const TestVSync());
    
    await tester.pumpWidget(createWidgetUnderTest(
      loggedIn: false,
      tabController: tabController,
    ));

    expect(find.byType(MBLoginPrompt), findsOneWidget);
  });
}
