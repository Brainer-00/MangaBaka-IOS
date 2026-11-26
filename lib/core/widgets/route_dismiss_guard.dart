import 'package:flutter/material.dart';

/// Updates barrier and back handling synchronously when a save starts.
/// A rebuild-driven PopScope can leave the first event in that frame unguarded.
mixin RouteDismissGuard<T extends StatefulWidget> on State<T>
    implements PopEntry<Object?> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(true);
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route?.unregisterPopEntry(this);
    _route = route;
    route?.registerPopEntry(this);
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    canPopNotifier.dispose();
    super.dispose();
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  @override
  void onPopInvoked(bool didPop) => onPopInvokedWithResult(didPop, null);
}
