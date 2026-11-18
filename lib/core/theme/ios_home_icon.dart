import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mangabaka_app/core/theme/ios_icon_variants.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';

class IosHomeIcon with WidgetsBindingObserver {
  IosHomeIcon(this.theme, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('eirenyu/home_icon');

  final ThemeController theme;
  final MethodChannel _channel;
  bool _active = true;
  bool _disposed = false;
  bool _working = false;
  int _revision = 0;
  String? _desired;
  String? _lastSuccessfulName;
  bool _hasSuccessfulSet = false;

  void start() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    WidgetsBinding.instance.addObserver(this);
    theme.addListener(_changed);
    _changed();
  }

  void _changed() {
    _desired = iosIconForColor(theme.currentLogoColor.toARGB32());
    _revision++;
    if (_active) unawaited(_reconcile());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_reconcile());
  }

  Future<void> _reconcile() async {
    if (_working || !_active || _disposed) return;
    _working = true;
    try {
      if (await _channel.invokeMethod<bool>('supported') != true) return;
      while (_active && !_disposed) {
        final revision = _revision;
        final actual = await _channel.invokeMethod<String>('current');
        if (!_active || _disposed) break;
        if (revision != _revision) continue;
        if (actual == _desired) {
          _hasSuccessfulSet = false;
          break;
        }
        // UIKit may report the previous icon briefly after a successful
        // completion. That completion is authoritative for this selection.
        if (_hasSuccessfulSet && _lastSuccessfulName == _desired) break;
        final desired = _desired;
        await _channel.invokeMethod<void>('set', desired);
        _lastSuccessfulName = desired;
        _hasSuccessfulSet = true;
        // The confirmation dialog can suspend the app. Recheck on resume.
        if (!_active || _disposed) break;
      }
    } on PlatformException catch (error) {
      debugPrint('Home icon change failed: $error');
    } on MissingPluginException {
      // An older native host can run the new Dart code during development.
    } finally {
      _working = false;
    }
  }

  void dispose() {
    _disposed = true;
    theme.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
  }
}
