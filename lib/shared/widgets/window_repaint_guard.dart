import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the desktop window's picture in step with its size.
///
/// Toggling fullscreen (F11) resizes the native window in several steps inside
/// one call — maximise, change the frame style, move to the monitor's bounds.
/// The engine can present a frame made for one of those intermediate sizes and,
/// with nothing animating, never replace it: the framework has laid out for the
/// final size (a click lands on what *should* be under the pointer) while the
/// screen still shows the old picture until something else causes a repaint.
///
/// So after every change of window metrics this waits for the resizing to
/// settle and then forces a couple of frames. Cheap, and idle otherwise.
class WindowRepaintGuard extends StatefulWidget {
  final Widget child;

  const WindowRepaintGuard({super.key, required this.child});

  /// Toggles fullscreen and makes sure the result is drawn.
  static Future<void> toggleFullscreen() async {
    if (!_isDesktop) return;
    final isFull = await windowManager.isFullScreen();
    if (isFull) {
      if (Platform.isWindows) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
      await windowManager.setFullScreen(false);
      if (Platform.isWindows) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
    } else {
      await windowManager.setFullScreen(true);
    }
    // The metrics observer below normally covers this; going through it again
    // here costs one extra frame and removes any dependence on the engine
    // having reported the change at all.
    forceFrames();
  }

  /// Forces a frame now and again after the delays in [_settleDelays].
  static void forceFrames() {
    SchedulerBinding.instance.scheduleForcedFrame();
    for (final delay in _settleDelays) {
      Timer(delay, SchedulerBinding.instance.scheduleForcedFrame);
    }
  }

  /// Frames after the first, at intervals long enough to land after the last
  /// native resize step of a fullscreen transition.
  static const List<Duration> _settleDelays = [
    Duration(milliseconds: 120),
    Duration(milliseconds: 400),
  ];

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  State<WindowRepaintGuard> createState() => _WindowRepaintGuardState();
}

class _WindowRepaintGuardState extends State<WindowRepaintGuard>
    with WidgetsBindingObserver {
  /// Metrics change on every step of a drag-resize; only the last matters.
  static const Duration _debounce = Duration(milliseconds: 80);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!WindowRepaintGuard._isDesktop) return;
    _timer?.cancel();
    _timer = Timer(_debounce, WindowRepaintGuard.forceFrames);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
