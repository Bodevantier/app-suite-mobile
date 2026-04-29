import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Welcome splash that plays the SDolve intro Lottie once, then calls
/// [onFinished]. Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _postAnimationDelay = Duration(seconds: 3);

  late final AnimationController _controller;
  Timer? _holdTimer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _holdTimer?.cancel();
    widget.onFinished();
  }

  void _onAnimationComplete() {
    if (_done) return;
    _holdTimer?.cancel();
    _holdTimer = Timer(_postAnimationDelay, _finish);
  }

  @override
  void dispose() {
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
                  ..forward().whenComplete(_onAnimationComplete);
              },
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
