import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';

void main() {
  group('MbProfile', () {
    test('fromMeResponse should parse correctly', () {
      final json = {
        'data': {
          'id': '123',
          'role': 'admin',
          'scopes': ['read', 'write'],
          'nickname': 'AdminBaka',
          'preferred_username': 'admin_baka',
        }
      };

      final profile = MbProfile.fromMeResponse(json);

      expect(profile.id, '123');
      expect(profile.role, 'admin');
      expect(profile.scopes, ['read', 'write']);
      expect(profile.nickname, 'AdminBaka');
      expect(profile.preferredUsername, 'admin_baka');
    });

    test('fromUserInfo should parse correctly', () {
      final json = {
        'sub': '456',
        'scope': 'openid profile email',
        'nickname': 'UserBaka',
        'preferred_username': 'user_baka',
      };

      final profile = MbProfile.fromUserInfo(json);

      expect(profile.id, '456');
      expect(profile.role, 'user');
      expect(profile.scopes, ['openid', 'profile', 'email']);
      expect(profile.nickname, 'UserBaka');
      expect(profile.preferredUsername, 'user_baka');
    });

    test('toJson and fromJson should be symmetrical', () {
      final profile = MbProfile(
        id: '789',
        role: 'user',
        scopes: ['read'],
        nickname: 'SyncBaka',
        preferredUsername: 'sync_baka',
      );

      final json = profile.toJson();
      final fromJson = MbProfile.fromJson(json);

      expect(fromJson.id, profile.id);
      expect(fromJson.role, profile.role);
      expect(fromJson.scopes, profile.scopes);
      expect(fromJson.nickname, profile.nickname);
      expect(fromJson.preferredUsername, profile.preferredUsername);
    });

    test('fromMeResponse with empty data should handle it gracefully', () {
      final json = {'data': null};
      final profile = MbProfile.fromMeResponse(json as Map<String, dynamic>);

      expect(profile.id, '');
      expect(profile.role, '');
      expect(profile.scopes, isEmpty);
      expect(profile.nickname, isNull);
    });
  });
}
