import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/renderer.dart';

/// Animated title screen with the rotating Kalchakra wheel.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: <Color>[
              KalchakraColors.cosmic,
              KalchakraColors.voidBlack,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => CustomPaint(
                    painter: _ChakraPainter(progress: _controller.value),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'KALCHAKRA',
                style: TextStyle(
                  color: KalchakraColors.gold,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "The Time Weaver's Paradox",
                style: TextStyle(
                  color: KalchakraColors.parchment,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: FilledButton(
                  key: const Key('weave-time'),
                  onPressed: widget.onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: KalchakraColors.gold,
                    foregroundColor: KalchakraColors.voidBlack,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 42,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'WEAVE TIME',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChakraPainter extends CustomPainter {
  _ChakraPainter({required this.progress});

  /// 0..1 loop position of the animation.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KalchakraColors.gold.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KalchakraColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center,
      radius * 0.62,
      Paint()
        ..color = KalchakraColors.gold.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Rotating spokes.
    const int spokes = 12;
    final spin = progress * 2 * math.pi;
    final spokePaint = Paint()
      ..color = KalchakraColors.gold.withValues(alpha: 0.75)
      ..strokeWidth = 2;
    for (var i = 0; i < spokes; i++) {
      final angle = spin + i * 2 * math.pi / spokes;
      final from = center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.18);
      final to = center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.98);
      canvas.drawLine(from, to, spokePaint);
    }

    // Orbiting motes.
    final dotPaint = Paint()..color = KalchakraColors.energyCyan;
    for (var i = 0; i < 6; i++) {
      final angle = -spin * 1.5 + i * math.pi / 3;
      final r = radius * 0.8;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * r,
        3.5,
        dotPaint,
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.16,
      Paint()..color = KalchakraColors.gold,
    );
  }

  @override
  bool shouldRepaint(covariant _ChakraPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
