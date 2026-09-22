import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';

class MockProfileAuthService extends ProfileAuthService {
  bool _mockLoggedIn = false;

  @override
  bool get isLoggedIn => _mockLoggedIn;

  @override
  Future<void> logout() async {
    _mockLoggedIn = false;
  }
}

void main() {
  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
  });

  group('ProfileAuthService', () {
    test('initial state is logged out', () {
      final auth = MockProfileAuthService();
      expect(auth.isLoggedIn, isFalse);
    });

    test('logout clears state', () async {
      final auth = MockProfileAuthService();
      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
    });
  });
}
