import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Welcome splash — plays the SDolve intro animation in full while the app
/// loads in the background, then calls [onFinished]. Tap anywhere to skip.
///
/// Waits for the animation to actually finish playing (the logo brackets,
/// the "S", and the slogan text all animate in over its ~3.8s length) rather
/// than cutting away after a fixed timer disconnected from that length, then
/// holds on the completed frame briefly so the slogan is actually readable
/// rather than just flashed on screen. Dependency loading (`AppDependencies.
/// standard()`) already runs in parallel and typically finishes in well
/// under a second, so it's never the bottleneck. A fallback timer guards
/// against the animation asset failing to load, so the splash can never
/// hang forever.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _maxWaitDuration = Duration(seconds: 5);
  // Pause on the completed logo + slogan before handing off. Only applies
  // when the animation finishes naturally — skipped on tap-to-skip and on
  // the fallback timer, both of which mean "get me out of here now".
  static const Duration _holdAfterCompletion = Duration(milliseconds: 500);

  late final AnimationController _controller;
  Timer? _fallbackTimer;
  Timer? _holdTimer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _holdTimer = Timer(_holdAfterCompletion, _finish);
        }
      });
    _fallbackTimer = Timer(_maxWaitDuration, _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _fallbackTimer?.cancel();
    _holdTimer?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: Center(
            child: Lottie.asset(
              'assets/animations/sdolve_welcome.json',
              controller: _controller,
              onLoaded: (composition) {
                _controller
                  ..duration = composition.duration
                  ..forward();
              },
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
