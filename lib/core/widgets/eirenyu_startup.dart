import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';

/// A single launch cover above an already mounted app and navigator.
class EirenYuStartup extends StatefulWidget {
  const EirenYuStartup({
    super.key,
    required this.resolveColor,
    required this.onDismissed,
    required this.child,
  });

  final Color Function() resolveColor;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<EirenYuStartup> createState() => _EirenYuStartupState();
}

class _EirenYuStartupState extends State<EirenYuStartup>
    with SingleTickerProviderStateMixin {
  // Leave headroom for a one-second cold asset load. Only the neutral frame
  // holds the engine's first frame; the reveal layers can finish behind it.
  static const _prepareBudget = Duration(milliseconds: 1250);
  static const _duration = Duration(milliseconds: 1320);
  static const _playBudget = Duration(milliseconds: 1650);
  static const _fillEnd = 0.86;

  final _binding = WidgetsBinding.instance;
  late final AnimationController _motion;
  late final Animation<double> _opacity;
  late final ImageProvider _neutral;
  AppLifecycleListener? _lifecycle;
  Timer? _deadline;
  bool _started = false;
  bool _holdingFirstFrame = false;
  bool _visible = true;
  bool _neutralReady = false;
  Color? _launchColor;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dismiss();
      });
    _opacity = _motion.drive(
      Tween(begin: 1.0, end: 0.0).chain(
        CurveTween(curve: const Interval(_fillEnd, 1, curve: Curves.easeOut)),
      ),
    );
    _lifecycle = AppLifecycleListener(onHide: _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_visible) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _dismiss();
      return;
    }
    if (_started) return;
    _started = true;

    // Match the native rendition's decode size without loading the full master
    // into memory on lower-density displays.
    final pixels = (_nativeCanvasSize * MediaQuery.devicePixelRatioOf(context))
        .floor()
        .clamp(1, 1254);
    _neutral = ResizeImage.resizeIfNeeded(
      pixels,
      pixels,
      EirenYuLaunchArtwork.neutralImage,
    );
    _binding.deferFirstFrame();
    _holdingFirstFrame = true;
    _deadline = Timer(
      _prepareBudget,
      () => _skip(TimeoutException('Preparing launch artwork')),
    );
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final neutralReady = _precache(_neutral);
      final masksReady = Future.wait([
        _precache(EirenYuMark.symbolImage),
        _precache(EirenYuMark.dotImage),
      ]);
      await neutralReady;
      if (!mounted || !_visible) return;

      setState(() => _neutralReady = true);
      _releaseFirstFrame();
      // Submit the neutral frame and finish decoding both masks before
      // starting the animation clock.
      await Future.wait([_binding.endOfFrame, masksReady]);
      if (!mounted || !_visible) return;
      _deadline?.cancel();
      _deadline = Timer(_playBudget, _dismiss);
      setState(() => _launchColor = widget.resolveColor());
      _motion.forward();
    } catch (error) {
      _skip(error);
    }
  }

  Future<void> _precache(ImageProvider image) =>
      precacheImage(image, context, onError: (error, _) => _skip(error));

  void _skip(Object error) {
    if (!mounted || !_visible) return;
    LoggingService.logger.warning(
      'Startup artwork skipped (${error.runtimeType})',
    );
    _dismiss();
  }

  void _releaseFirstFrame() {
    if (!_holdingFirstFrame) return;
    _holdingFirstFrame = false;
    _binding.allowFirstFrame();
  }

  void _dismiss() {
    if (!mounted || !_visible) return;
    _deadline?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    _motion.stop();
    setState(() => _visible = false);
    _releaseFirstFrame();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _lifecycle?.dispose();
    _motion.dispose();
    _releaseFirstFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: _visible,
          child: ExcludeSemantics(excluding: _visible, child: widget.child),
        ),
        if (_visible)
          AbsorbPointer(
            child: ExcludeSemantics(
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppTheme.systemOverlay,
                child: FadeTransition(
                  opacity: _opacity,
                  child: ColoredBox(
                    color: EirenYuPalette.obsidian,
                    child: Center(
                      child: _neutralReady
                          ? RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _motion,
                                builder: (context, child) =>
                                    EirenYuLaunchArtwork(
                                      neutral: _neutral,
                                      color: _launchColor,
                                      progress: const Interval(
                                        0,
                                        _fillEnd,
                                        curve: Curves.easeInOutSine,
                                      ).transform(_motion.value),
                                    ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// The native generator centers an 895 px artwork canvas in a 1254 px PNG,
// which flutter_native_splash exports at one quarter of that logical size.
const _nativeCanvasSize = 313.5;
const _markCanvasSize = 223.75;

/// Renders a particular fill level, separate from the launch clock.
class EirenYuLaunchArtwork extends StatelessWidget {
  const EirenYuLaunchArtwork({
    super.key,
    required this.progress,
    required this.color,
    this.neutral = neutralImage,
  });

  static const neutralImage = AssetImage(
    'assets/branding/eirenyu/launch_splash.png',
  );

  final double progress;
  final Color? color;
  final ImageProvider neutral;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _nativeCanvasSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (progress < 1)
            Image(
              image: neutral,
              width: _nativeCanvasSize,
              fit: BoxFit.contain,
            ),
          if (progress > 0)
            ClipPath(
              clipper: progress < 1 ? _LiquidClipper(progress) : null,
              child: EirenYuMark(size: _markCanvasSize, color: color),
            ),
        ],
      ),
    );
  }
}

class _LiquidClipper extends CustomClipper<Path> {
  const _LiquidClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    // The visible emblem runs from about 13% to 85% of the shared mask canvas.
    final level = size.height * (0.85 - 0.72 * progress);
    final amplitude = size.height * 0.012 * math.sin(math.pi * progress);
    final phase = 2 * math.pi * progress;
    const steps = 24;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i <= steps; i++) {
      final fraction = i / steps;
      path.lineTo(
        fraction * size.width,
        level + amplitude * math.sin(2 * math.pi * fraction - phase),
      );
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_LiquidClipper oldClipper) =>
      progress != oldClipper.progress;
}
