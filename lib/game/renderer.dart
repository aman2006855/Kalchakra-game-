import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'realms.dart';

/// Palette shared by the whole game.
class KalchakraColors {
  const KalchakraColors._();

  static const Color gold = Color(0xFFFFD700);
  static const Color voidBlack = Color(0xFF0D0015);
  static const Color cosmic = Color(0xFF1A0A2E);
  static const Color temporalRed = Color(0xFFFF3366);
  static const Color energyCyan = Color(0xFF00FFCC);
  static const Color parchment = Color(0xFFE8D5B7);
}

/// Draws the game world. All state comes from [engine]; the painter is
/// stateless so it can be repainted every frame cheaply.
class GamePainter extends CustomPainter {
  GamePainter(this.engine, {required this.pointer});

  final GameEngine engine;

  /// Live pointer position used to draw the movement tether, if any.
  final Offset? pointer;

  @override
  void paint(Canvas canvas, Size size) {
    final realm = engine.realm;
    final accent = Color(realm.color);
    final background = Color(realm.background);

    canvas.save();
    if (engine.shakeX != 0 || engine.shakeY != 0) {
      canvas.translate(engine.shakeX, engine.shakeY);
    }

    _drawBackground(canvas, size, background, accent);
    _drawTimeOverlay(canvas, size);
    _drawGrid(canvas, size, accent);
    _drawDrops(canvas, accent);
    _drawEnemies(canvas);
    _drawBullets(canvas);
    _drawPlayer(canvas, accent);
    _drawParticles(canvas);
    _drawThreatArrow(canvas, size);
    _drawPointerTether(canvas);

    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size, Color background, Color accent) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.35),
        radius: 1.1,
        colors: <Color>[
          Color.lerp(background, accent, 0.10) ?? background,
          background,
          KalchakraColors.voidBlack,
        ],
        stops: const <double>[0, 0.55, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _drawTimeOverlay(Canvas canvas, Size size) {
    Color? tint;
    switch (engine.activePower) {
      case TimePower.freeze:
        tint = KalchakraColors.energyCyan;
      case TimePower.fastForward:
        tint = const Color(0xFFFF6432);
      case TimePower.rewind:
      case null:
        tint = null;
    }
    if (tint == null) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = tint.withValues(alpha: 0.10),
    );
  }

  void _drawGrid(Canvas canvas, Size size, Color accent) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const step = 56.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDrops(Canvas canvas, Color accent) {
    for (final drop in engine.drops) {
      final Color color;
      final IconData icon;
      switch (drop.type) {
        case DropType.energy:
          color = KalchakraColors.energyCyan;
          icon = Icons.bolt;
        case DropType.health:
          color = KalchakraColors.temporalRed;
          icon = Icons.favorite;
        case DropType.rewind:
          color = KalchakraColors.gold;
          icon = Icons.replay;
      }

      final center = Offset(drop.x, drop.y);
      final pulse = 1 + math.sin(drop.timer * 4) * 0.12;
      final radius = 15 * engine.scale * pulse;

      canvas.drawCircle(
        center,
        radius * 2.1,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 2.1)),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 14 * engine.scale,
            color: color,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    }
  }

  void _drawEnemies(Canvas canvas) {
    for (final enemy in engine.enemies) {
      // Echoes of where the enemy has been.
      for (var i = 0; i < enemy.echoX.length; i++) {
        final fade = (i + 1) / (enemy.echoX.length + 1);
        canvas.drawCircle(
          Offset(enemy.echoX[i], enemy.echoY[i]),
          enemy.radius * 0.32,
          Paint()..color = Color(enemy.color).withValues(alpha: 0.20 * fade),
        );
      }

      final center = Offset(enemy.x, enemy.y);
      final color = Color(enemy.color);
      final isWraith = enemy.type == EnemyType.wraith;

      // Glow (radial gradient keeps this cheap on Impeller).
      final glowRadius = enemy.radius * 2.4;
      canvas.drawCircle(
        center,
        glowRadius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
      );

      canvas.drawCircle(center, enemy.radius, Paint()..color = KalchakraColors.cosmic);
      canvas.drawCircle(
        center,
        enemy.radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isWraith ? 4 : 3,
      );

      // Eyes.
      final eyeOffset = enemy.radius * 0.35;
      final eyeRadius = enemy.radius * 0.17;
      canvas.drawCircle(
        center.translate(-eyeOffset, -eyeRadius * 0.9),
        eyeRadius,
        Paint()..color = color,
      );
      canvas.drawCircle(
        center.translate(eyeOffset, -eyeRadius * 0.9),
        eyeRadius,
        Paint()..color = color,
      );

      if (enemy.dodgeFlash > 0) {
        // Cyan streak showing the enemy just slipped away from a shot.
        canvas.drawCircle(
          center,
          enemy.radius * 1.7,
          Paint()
            ..color = KalchakraColors.energyCyan
                .withValues(alpha: 0.35 * enemy.dodgeFlash / 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      if (enemy.aimFlash > 0) {
        // Aim tell: the ring closes as the shot lines up on the player.
        final t = 1 - enemy.aimFlash / 0.3;
        canvas.drawCircle(
          center,
          enemy.radius * (2.6 - 1.4 * t),
          Paint()
            ..color = KalchakraColors.temporalRed
                .withValues(alpha: 0.85 * (1 - t) + 0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final toPlayer = Offset(engine.playerX, engine.playerY) - center;
        final length = toPlayer.distance;
        if (length > 0.001) {
          final dir = toPlayer / length;
          canvas.drawLine(
            center + dir * (enemy.radius + 6),
            center + dir * (enemy.radius + 18),
            Paint()
              ..color = KalchakraColors.temporalRed
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
        }
      }

      if (isWraith) {
        // Armour ring shows remaining health.
        final healthRatio = (enemy.hp / 6).clamp(0.0, 1.0);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: enemy.radius + 6),
          -math.pi / 2,
          2 * math.pi * healthRatio,
          false,
          Paint()
            ..color = KalchakraColors.parchment
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      } else if (enemy.type == EnemyType.shooter ||
          enemy.type == EnemyType.weaver) {
        final marker = Path()
          ..moveTo(center.dx, center.dy - enemy.radius - 11)
          ..lineTo(center.dx - 6, center.dy - enemy.radius - 4)
          ..lineTo(center.dx + 6, center.dy - enemy.radius - 4)
          ..close();
        canvas.drawPath(marker, Paint()..color = KalchakraColors.temporalRed);
      }
    }
  }

  void _drawBullets(Canvas canvas) {
    for (final bullet in engine.bullets) {
      final center = Offset(bullet.x, bullet.y);
      final color = Color(bullet.color);
      // Motion trail.
      canvas.drawCircle(
        center - Offset(bullet.vx, bullet.vy) * 0.02,
        bullet.radius * 0.7,
        Paint()..color = color.withValues(alpha: 0.45),
      );
      canvas.drawCircle(
        center,
        bullet.radius * 2.2,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[color.withValues(alpha: 0.4), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: bullet.radius * 2.2)),
      );
      canvas.drawCircle(center, bullet.radius, Paint()..color = color);
    }
  }

  void _drawPlayer(Canvas canvas, Color accent) {
    final center = Offset(engine.playerX, engine.playerY);
    final radius = engine.playerRadius;
    const gold = KalchakraColors.gold;

    // Aura.
    canvas.drawCircle(
      center,
      radius * 2.6,
      Paint()
        ..shader = ui.Gradient.radial(center, radius * 2.6, <Color>[
          gold.withValues(alpha: 0.30),
          gold.withValues(alpha: 0),
        ]),
    );

    if (engine.isFlashing) {
      canvas.drawCircle(
        center,
        radius + 4,
        Paint()..color = Colors.white.withValues(alpha: 0.25),
      );
    }

    canvas.drawCircle(center, radius, Paint()..color = KalchakraColors.cosmic);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Inner gold gradient.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, <Color>[
          gold.withValues(alpha: 0.28),
          gold.withValues(alpha: 0),
        ]),
    );

    final eyeRadius = radius * 0.22;
    canvas.drawCircle(center.translate(-radius * 0.3, -radius * 0.1), eyeRadius, Paint()..color = gold);
    canvas.drawCircle(center.translate(radius * 0.3, -radius * 0.1), eyeRadius, Paint()..color = gold);

    if (engine.shieldActive) {
      canvas.drawCircle(
        center,
        radius + 7,
        Paint()
          ..color = const Color(0xFF80D8FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        center,
        radius + 7,
        Paint()
          ..shader = ui.Gradient.radial(center, radius + 12, <Color>[
            const Color(0xFF80D8FF).withValues(alpha: 0.30),
            const Color(0xFF80D8FF).withValues(alpha: 0),
          ]),
      );
    }

    // Time power rings.
    switch (engine.activePower) {
      case TimePower.freeze:
        canvas.drawCircle(
          center,
          radius + 10,
          Paint()
            ..color = KalchakraColors.energyCyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      case TimePower.fastForward:
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            center,
            radius + 10 + i * 8,
            Paint()
              ..color = const Color(0xFFFF6432).withValues(alpha: 0.8 - i * 0.2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      case TimePower.rewind:
      case null:
        break;
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final particle in engine.particles) {
      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        Paint()
          ..color = Color(particle.color).withValues(alpha: particle.alpha),
      );
    }
  }

  void _drawThreatArrow(Canvas canvas, Size size) {
    final level = engine.threatLevel;
    if (level < 0.03) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;
    final point = Offset(
      center.dx + engine.threatDx * radius,
      center.dy + engine.threatDy * radius,
    );
    final paint = Paint()
      ..color = KalchakraColors.temporalRed.withValues(alpha: 0.35 + 0.5 * level)
      ..style = PaintingStyle.fill;
    final angle = math.atan2(engine.threatDy, engine.threatDx);
    final tip = point + Offset(math.cos(angle), math.sin(angle)) * 10;
    final left = point + Offset(
          math.cos(angle + 2.6),
          math.sin(angle + 2.6),
        ) *
        12;
    final right = point + Offset(
          math.cos(angle - 2.6),
          math.sin(angle - 2.6),
        ) *
        12;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawPointerTether(Canvas canvas) {
    final target = pointer;
    if (target == null) return;
    final start = Offset(engine.playerX, engine.playerY);
    final paint = Paint()
      ..color = KalchakraColors.energyCyan.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, target, paint);
    canvas.drawCircle(target, 14, paint);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}

/// Small helper so screens can share realm colouring.
Color realmColor(Realm realm) => Color(realm.color);
