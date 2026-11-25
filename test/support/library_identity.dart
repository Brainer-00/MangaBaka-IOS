import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';

/// For presentation tests that supply tracking streams without a database.
late LibraryCacheLease testLibraryLease;

Future<void> prepareWidgetLibraryIdentity() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  try {
    testLibraryLease = await db.ownedLibraryDao.activate(
      VerifiedLibraryOwner.fromVerifiedAccountId('widget-fixture'),
    );
  } finally {
    await db.close();
  }
}

mixin WidgetLibraryIdentity implements ProfileAuthService {
  @override
  LibraryCacheLease? get libraryLease => isLoggedIn ? testLibraryLease : null;

  @override
  int get sessionGeneration => isLoggedIn ? 1 : 0;
}

class SignedInWidgetAuth extends Fake with WidgetLibraryIdentity {
  @override
  bool get isLoggedIn => true;
  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
}
