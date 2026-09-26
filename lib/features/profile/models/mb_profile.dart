class MbProfile {
  final String id;
  final String role;
  final List<String> scopes;
  final String? nickname;
  final String? preferredUsername;
  final String? avatarUrl;

  MbProfile({
    required this.id,
    required this.role,
    required this.scopes,
    this.nickname,
    this.preferredUsername,
    this.avatarUrl,
  });

  // For /v1/my/profile or /v1/me response
  factory MbProfile.fromMeResponse(Map<String, dynamic> json) {
    final data = (json['data'] as Map<String, dynamic>?) ?? json;
    return MbProfile(
      id: data['id']?.toString() ?? data['sub']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      scopes: (data['scopes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      nickname: data['nickname']?.toString() ?? data['name']?.toString(),
      preferredUsername:
          data['preferred_username']?.toString() ??
          data['username']?.toString() ??
          data['handle']?.toString(),
      avatarUrl: _parseAvatar(data),
    );
  }

  // For OIDC userinfo response
  factory MbProfile.fromUserInfo(Map<String, dynamic> json) {
    final data = (json['data'] as Map<String, dynamic>?) ?? json;
    return MbProfile(
      id: data['sub']?.toString() ?? data['id']?.toString() ?? '',
      role: data['role']?.toString() ?? 'user',
      scopes: (data['scope'] is String)
          ? (data['scope'] as String).split(' ')
          : (data['scopes'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[],
      nickname: data['nickname']?.toString() ?? data['name']?.toString(),
      preferredUsername:
          data['preferred_username']?.toString() ??
          data['username']?.toString(),
      avatarUrl: _parseAvatar(data),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'scopes': scopes,
      'nickname': nickname,
      'preferred_username': preferredUsername,
      'avatar_url': avatarUrl,
    };
  }

  factory MbProfile.fromJson(Map<String, dynamic> json) {
    return MbProfile(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      scopes:
          (json['scopes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      nickname: json['nickname']?.toString(),
      preferredUsername: json['preferred_username']?.toString(),
      avatarUrl: _parseAvatar(json),
    );
  }

  MbProfile copyWith({
    String? id,
    String? role,
    List<String>? scopes,
    String? nickname,
    String? preferredUsername,
    String? avatarUrl,
  }) {
    return MbProfile(
      id: id ?? this.id,
      role: role ?? this.role,
      scopes: scopes ?? this.scopes,
      nickname: nickname ?? this.nickname,
      preferredUsername: preferredUsername ?? this.preferredUsername,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  static String? _parseAvatar(Map<String, dynamic> data) {
    for (final key in [
      'avatar',
      'avatar_url',
      'picture',
      'picture_url',
      'image',
      'image_url',
      'icon',
      'icon_url',
      'profile_picture',
      'profile_picture_url',
      'pfp',
      'photo',
      'cover',
    ]) {
      if (data.containsKey(key)) {
        final normalized = _extractImageUrl(data[key]);
        if (normalized != null) return normalized;
      }
    }
    for (final userKey in ['user', 'profile', 'attributes']) {
      if (data[userKey] is Map<String, dynamic>) {
        final nested = _parseAvatar(data[userKey] as Map<String, dynamic>);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static String? _extractImageUrl(dynamic val) {
    if (val == null) return null;
    if (val is String) {
      return _normalizeUrl(val);
    }
    if (val is Map) {
      final map = val.cast<String, dynamic>();
      for (final key in [
        'url',
        'raw',
        'x250',
        'medium',
        'large',
        'original',
        'href',
        'x1',
      ]) {
        final normalized = _extractImageUrl(map[key]);
        if (normalized != null) return normalized;
      }
      if (map['image'] is Map) {
        final image = map['image'] as Map;
        for (final key in ['x250', 'raw']) {
          final normalized = _extractImageUrl(image[key]);
          if (normalized != null) return normalized;
        }
      }
    }
    if (val is List) {
      for (final candidate in val) {
        final normalized = _extractImageUrl(candidate);
        if (normalized != null) return normalized;
      }
    }
    return null;
  }

  static String? _normalizeUrl(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) return null;

    if (value.startsWith('//')) {
      final normalized = Uri.tryParse('https:$value');
      return normalized != null && normalized.host.isNotEmpty
          ? normalized.toString()
          : null;
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    if (parsed.hasScheme) {
      return parsed.scheme.toLowerCase() == 'https' && parsed.host.isNotEmpty
          ? value
          : null;
    }

    return Uri.parse('https://mangabaka.org/').resolveUri(parsed).toString();
  }
}
