import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';

class AnimatedSplashOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const AnimatedSplashOverlay({super.key, required this.onComplete});

  @override
  State<AnimatedSplashOverlay> createState() => _AnimatedSplashOverlayState();
}

class _AnimatedSplashOverlayState extends State<AnimatedSplashOverlay> {
  static final _logger = LoggingService.logger;

  @override
  void initState() {
    super.initState();
    // Remove native splash as soon as we start our Flutter animation
    _logger.fine('Removing native splash, starting animated overlay');
    FlutterNativeSplash.remove();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child:
          Container(
                color: AppConstants.primaryBackground,
                child: Center(
                  child: Image.asset(
                    'assets/mangabaka_splash.png',
                    width: 313,
                    height: 313,
                    fit: BoxFit.contain,
                  ),
                ),
              )
              .animate(
                onComplete: (controller) {
                  _logger.fine('Splash animation completed');
                  widget.onComplete();
                },
              )
              .then(delay: 800.ms)
              .fadeOut(duration: 600.ms, curve: Curves.easeInOut),
    );
  }
}
