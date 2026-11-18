import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mangabaka_app/core/theme/ios_icon_variants.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';

class IosHomeIconScope extends InheritedWidget {
  const IosHomeIconScope({super.key, required this.icon, required super.child});
  final IosHomeIcon icon;

  static void request(BuildContext context) {
    context.getInheritedWidgetOfExactType<IosHomeIconScope>()?.icon.request();
  }

  @override
  bool updateShouldNotify(IosHomeIconScope oldWidget) => icon != oldWidget.icon;
}

class IosHomeIcon with WidgetsBindingObserver {
  IosHomeIcon(this.theme, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('eirenyu/home_icon');

  final ThemeController theme;
  final MethodChannel _channel;
  bool _active = true;
  bool _disposed = false;
  bool _started = false;
  bool _working = false;
  bool _pending = false;
  int _revision = 0;
  String? _desired;
  String? _lastSuccessfulName;
  bool _hasSuccessfulSet = false;

  void start() {
    if (_started || defaultTargetPlatform != TargetPlatform.iOS) return;
    _started = true;
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reconcile());
  }

  void request() {
    if (!_started || _disposed) return;
    _desired = iosIconForColor(theme.currentLogoColor.toARGB32());
    _pending = true;
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
    var observedRevision = _revision;
    try {
      if (await _channel.invokeMethod<bool>('supported') != true) {
        _pending = false;
        return;
      }
      while (_active && !_disposed) {
        observedRevision = _revision;
        final actual = await _channel.invokeMethod<String>('current');
        if (!_active || _disposed) break;
        if (observedRevision != _revision) continue;
        if (!_pending) break;
        if (_hasSuccessfulSet && actual == _lastSuccessfulName) {
          _hasSuccessfulSet = false;
        }
        final effective = _hasSuccessfulSet ? _lastSuccessfulName : actual;
        if (effective == _desired) {
          _pending = false;
          break;
        }
        final desired = _desired;
        // Consume this request before awaiting UIKit. A newer request remains
        // pending even if the app becomes inactive while the dialog is open.
        _pending = false;
        await _channel.invokeMethod<void>('set', desired);
        _lastSuccessfulName = desired;
        _hasSuccessfulSet = true;
      }
    } on PlatformException catch (error) {
      if (_revision == observedRevision) _pending = false;
      debugPrint('Home icon change failed: $error');
    } on MissingPluginException {
      _pending = false;
    } finally {
      _working = false;
      if (_active && !_disposed && _pending && _revision != observedRevision) {
        unawaited(_reconcile());
      }
    }
  }

  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
