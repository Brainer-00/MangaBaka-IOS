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
        },
      };

      final profile = MbProfile.fromMeResponse(json);

      expect(profile.id, '123');
      expect(profile.role, 'admin');
      expect(profile.scopes, ['read', 'write']);
      expect(profile.nickname, 'AdminBaka');
      expect(profile.preferredUsername, 'admin_baka');
    });

    test('accepts external HTTPS avatars and trims whitespace', () {
      final profile = MbProfile.fromMeResponse({
        'avatar_url': '  https://cdn.example.com/avatar.png?size=250  ',
      });

      expect(profile.avatarUrl, 'https://cdn.example.com/avatar.png?size=250');
    });

    test('normalizes protocol-relative and MangaBaka-relative avatars', () {
      expect(
        MbProfile.fromMeResponse({
          'avatar': '//cdn.example.com/avatar.png',
        }).avatarUrl,
        'https://cdn.example.com/avatar.png',
      );
      expect(
        MbProfile.fromUserInfo({'picture': '/avatars/user.png'}).avatarUrl,
        'https://mangabaka.org/avatars/user.png',
      );
      expect(
        MbProfile.fromMeResponse({'avatar': 'avatars/user.png'}).avatarUrl,
        'https://mangabaka.org/avatars/user.png',
      );
    });

    test('rejects cleartext, unsafe, and unsupported avatar schemes', () {
      for (final url in [
        'http://cdn.example.com/avatar.png',
        'file:///private/avatar.png',
        'data:image/png;base64,AAAA',
        'javascript:alert(1)',
        'ftp://cdn.example.com/avatar.png',
        'custom://avatar/123',
      ]) {
        expect(
          MbProfile.fromMeResponse({'avatar_url': url}).avatarUrl,
          isNull,
          reason: url,
        );
      }
    });

    test('rejects malformed HTTPS avatars without a usable host', () {
      for (final url in ['https:///avatar.png', 'https://?avatar=user']) {
        expect(
          MbProfile.fromMeResponse({'avatar_url': url}).avatarUrl,
          isNull,
          reason: url,
        );
      }
    });

    test(
      'continues to a valid avatar after rejecting an earlier candidate',
      () {
        expect(
          MbProfile.fromMeResponse({
            'avatar': 'http://insecure.example/avatar.png',
            'picture': 'https://cdn.example.com/valid.png',
          }).avatarUrl,
          'https://cdn.example.com/valid.png',
        );
        expect(
          MbProfile.fromMeResponse({
            'avatar': 'javascript:alert(1)',
            'profile': {'picture': 'https://cdn.example.com/nested.png'},
          }).avatarUrl,
          'https://cdn.example.com/nested.png',
        );
      },
    );

    test('continues through avatar map values until one is valid', () {
      final profile = MbProfile.fromMeResponse({
        'avatar': {
          'url': 'http://insecure.example/old.png',
          'raw': 'https://cdn.example.com/new.png',
        },
      });

      expect(profile.avatarUrl, 'https://cdn.example.com/new.png');
    });

    test('continues through avatar list values until one is valid', () {
      final profile = MbProfile.fromMeResponse({
        'avatar': [
          'http://insecure.example/old.png',
          'https://cdn.example.com/new.png',
        ],
      });

      expect(profile.avatarUrl, 'https://cdn.example.com/new.png');
    });

    test('fromJson applies the same avatar normalization policy', () {
      final profile = MbProfile.fromJson({
        'id': 'cached-user',
        'role': 'user',
        'scopes': <String>[],
        'avatar_url': '//cache-cdn.example.com/cached.png',
      });

      expect(profile.avatarUrl, 'https://cache-cdn.example.com/cached.png');
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
