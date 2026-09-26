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

  /// Soft glow paints are built once and reused for the rest of the run.
  ///
  /// Building a [RadialGradient] shader for every enemy, bullet and particle on
  /// every frame is what used to make the game stutter once the screen filled
  /// up, so the shaders are cached per (colour, alpha) and drawn through a
  /// canvas transform instead of being rebuilt per entity.
  static final Map<String, Paint> _glowCache = <String, Paint>{};

  /// Above this many entities the purely decorative passes are skipped so the
  /// simulation keeps a steady frame rate on mid range phones.
  static const int _crowdedThreshold = 26;

  /// Only once the screen is genuinely saturated do the glows go, because they
  /// carry the readability of where the fire is coming from.
  static const int _saturatedThreshold = 55;

  /// Shared paints for the hot paths so the frame does not allocate.
  static final Paint _temporalLine = Paint()
    ..color = KalchakraColors.temporalRed
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  static final Paint _temporalFill = Paint()..color = KalchakraColors.temporalRed;

  /// Backdrop shader cached per (background, accent) pair. Rebuilding the
  /// full-screen radial gradient on every frame was pure allocation for zero
  /// visual change within a realm.
  static final Map<String, Shader> _backdropCache = <String, Shader>{};

  /// Drop icon glyphs are laid out once per (icon, fontSize) and reused, the
  /// same way the glow shaders are. A fresh TextPainter + layout per drop per
  /// frame is the single most expensive thing left in the frame.
  static final Map<String, TextPainter> _dropIconCache = <String, TextPainter>{};

  /// Unit-radius player sheen and shield sheen, drawn through canvas
  /// transforms instead of rebuilding a shader per frame.
  static final Paint _playerSheen = Paint()
    ..shader = ui.Gradient.radial(
      Offset.zero,
      1,
      <Color>[
        KalchakraColors.gold.withValues(alpha: 0.28),
        KalchakraColors.gold.withValues(alpha: 0),
      ],
    );
  static final Paint _shieldSheen = Paint()
    ..shader = ui.Gradient.radial(
      Offset.zero,
      1,
      <Color>[
        const Color(0xFF80D8FF).withValues(alpha: 0.30),
        const Color(0xFF80D8FF).withValues(alpha: 0),
      ],
    );

  static final Paint _shieldRing = Paint()
    ..color = const Color(0xFF80D8FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  /// Tint overlays for the active time power, hoisted out of the frame.
  static const Color _freezeTint = KalchakraColors.energyCyan;
  static const Color _fastTint = Color(0xFFFF6432);

  bool get _crowded =>
      engine.enemies.length + engine.bullets.length > _crowdedThreshold;

  bool get _saturated =>
      engine.enemies.length + engine.bullets.length > _saturatedThreshold;

  /// A unit-radius glow paint, cached per colour and alpha.
  static Paint _glow(Color color, double alpha) {
    final key = '${color.toARGB32()}@${(alpha * 100).round()}';
    return _glowCache.putIfAbsent(key, () {
      final c = color.withValues(alpha: alpha);
      return Paint()
        ..shader = ui.Gradient.radial(
          const Offset(0, 0),
          1,
          <Color>[c, c.withValues(alpha: 0)],
        );
    });
  }

  /// Draws a cached glow centred on [center]. The cached shader is built around
  /// the origin, so the canvas is shifted into place instead of rebuilding the
  /// shader for every entity.
  void _glowAt(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    if (radius <= 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawCircle(Offset.zero, radius, _glow(color, alpha));
    canvas.restore();
  }

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
    if (!_crowded) _drawGrid(canvas, size, accent);
    _drawDrops(canvas, accent);
    _drawSpawnMarks(canvas);
    _drawEnemies(canvas);
    _drawBullets(canvas);
    _drawPlayer(canvas, accent);
    if (_crowded) {
      _drawParticlesCheap(canvas);
    } else {
      _drawParticles(canvas);
    }
    _drawThreatArrow(canvas, size);
    _drawPointerTether(canvas);

    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size, Color background, Color accent) {
    final rect = Offset.zero & size;
    // The gradient only changes when the realm changes, so the shader is
    // cached per realm pair and the paint object itself is static.
    final key = '${background.toARGB32()}-${accent.toARGB32()}';
    final paint = Paint()
      ..shader = _backdropCache.putIfAbsent(key, () {
        return RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.1,
          colors: <Color>[
            Color.lerp(background, accent, 0.10) ?? background,
            background,
            KalchakraColors.voidBlack,
          ],
          stops: const <double>[0, 0.55, 1],
        ).createShader(rect);
      });
    canvas.drawRect(rect, paint);
  }

  void _drawTimeOverlay(Canvas canvas, Size size) {
    Color? tint;
    switch (engine.activePower) {
      case TimePower.freeze:
        tint = _freezeTint;
      case TimePower.fastForward:
        tint = _fastTint;
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
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

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

      if (!_saturated) _glowAt(canvas, center, radius * 2.1, color, 0.35);
      fill.color = color.withValues(alpha: 0.35);
      canvas.drawCircle(center, radius, fill);
      stroke.color = color;
      canvas.drawCircle(center, radius, stroke);

      // The icon painter is laid out once per (icon, fontSize) and cached;
      // building a TextPainter + layout for every drop every frame was a
      // measurable source of jank.
      final fontSize = 14 * engine.scale;
      final key = '${icon.codePoint}-${fontSize.toStringAsFixed(1)}';
      final painter = _dropIconCache.putIfAbsent(key, () {
        return TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
      painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    }
  }

  /// Warning marks at the screen edge where the next wave is tearing through.
  void _drawSpawnMarks(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final mark in engine.spawnMarks) {
      final t = 1 - mark.life / 0.9;
      paint
        ..color = KalchakraColors.temporalRed.withValues(alpha: 0.5 * (1 - t))
        ..strokeWidth = 2;
      canvas.drawCircle(
        Offset(mark.x, mark.y),
        mark.radius * (0.5 + 1.6 * t),
        paint,
      );
    }
  }

  void _drawEnemies(Canvas canvas) {
    // One paint is reused for every flat circle; only the glows need a shader.
    final flat = Paint();
    final echoPaint = Paint();
    final strokePaint = Paint()..style = PaintingStyle.stroke;
    final crowded = _crowded;
    final saturated = _saturated;

    for (final enemy in engine.enemies) {
      final color = Color(enemy.color);

      // Echoes of where the enemy has been. Purely decorative, so they are the
      // first thing dropped when the screen gets busy.
      if (!crowded) {
        for (var i = 0; i < enemy.echoX.length; i++) {
          final fade = (i + 1) / (enemy.echoX.length + 1);
          echoPaint.color = color.withValues(alpha: 0.20 * fade);
          canvas.drawCircle(
            Offset(enemy.echoX[i], enemy.echoY[i]),
            enemy.radius * 0.32,
            echoPaint,
          );
        }
      }

      final center = Offset(enemy.x, enemy.y);
      final isWraith = enemy.type == EnemyType.wraith;

      if (!saturated) _glowAt(canvas, center, enemy.radius * 2.4, color, 0.35);

      canvas.drawCircle(center, enemy.radius, flat..color = KalchakraColors.cosmic);
      strokePaint
        ..color = color
        ..strokeWidth = isWraith ? 4.0 : 3.0;
      canvas.drawCircle(center, enemy.radius, strokePaint);

      // Eyes.
      final eyeOffset = enemy.radius * 0.35;
      final eyeRadius = enemy.radius * 0.17;
      flat.color = color;
      canvas.drawCircle(
        center.translate(-eyeOffset, -eyeRadius * 0.9),
        eyeRadius,
        flat,
      );
      canvas.drawCircle(
        center.translate(eyeOffset, -eyeRadius * 0.9),
        eyeRadius,
        flat,
      );

      if (enemy.entryFlash > 0) {
        // A closing ring announces the arrival so a wave never just appears.
        final t = 1 - enemy.entryFlash / 0.9;
        strokePaint
          ..color = color.withValues(alpha: 0.8 * (1 - t))
          ..strokeWidth = 2.5;
        canvas.drawCircle(
          center,
          enemy.radius * (3.2 - 1.4 * t),
          strokePaint,
        );
      }

      if (enemy.dodgeFlash > 0) {
        // Cyan streak showing the enemy just slipped away from a shot.
        strokePaint
          ..color = KalchakraColors.energyCyan
              .withValues(alpha: 0.35 * enemy.dodgeFlash / 0.18)
          ..strokeWidth = 2;
        canvas.drawCircle(center, enemy.radius * 1.7, strokePaint);
      }

      if (enemy.aimFlash > 0) {
        // Aim tell: the ring closes as the shot lines up on the player.
        final t = 1 - enemy.aimFlash / 0.3;
        strokePaint
          ..color = KalchakraColors.temporalRed
              .withValues(alpha: 0.85 * (1 - t) + 0.15)
          ..strokeWidth = 2;
        canvas.drawCircle(center, enemy.radius * (2.6 - 1.4 * t), strokePaint);
        final toPlayer = Offset(engine.playerX, engine.playerY) - center;
        final length = toPlayer.distance;
        if (length > 0.001) {
          final dir = toPlayer / length;
          canvas.drawLine(
            center + dir * (enemy.radius + 6),
            center + dir * (enemy.radius + 18),
            _temporalLine,
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
        canvas.drawPath(marker, _temporalFill);
      }
    }
  }

  void _drawBullets(Canvas canvas) {
    final flat = Paint();
    final saturated = _saturated;
    for (final bullet in engine.bullets) {
      final center = Offset(bullet.x, bullet.y);
      final color = Color(bullet.color);
      // Motion trail.
      canvas.drawCircle(
        center - Offset(bullet.vx, bullet.vy) * 0.02,
        bullet.radius * 0.7,
        Paint()..color = color.withValues(alpha: 0.45),
      );
      if (!saturated) _glowAt(canvas, center, bullet.radius * 2.2, color, 0.4);
      canvas.drawCircle(center, bullet.radius, flat..color = color);
    }
  }

  void _drawPlayer(Canvas canvas, Color accent) {
    final center = Offset(engine.playerX, engine.playerY);
    final radius = engine.playerRadius;
    const gold = KalchakraColors.gold;
    final shieldR = radius + 12.0;

    // Aura.
    _glowAt(canvas, center, radius * 2.6, gold, 0.30);

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

    // Inner gold gradient: a cached unit shader drawn through a canvas
    // transform, so no shader is rebuilt per frame.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius, radius);
    canvas.drawCircle(Offset.zero, 1, _playerSheen);
    canvas.restore();

    final eyeRadius = radius * 0.22;
    canvas.drawCircle(center.translate(-radius * 0.3, -radius * 0.1), eyeRadius, Paint()..color = gold);
    canvas.drawCircle(center.translate(radius * 0.3, -radius * 0.1), eyeRadius, Paint()..color = gold);

    if (engine.shieldActive) {
      canvas.drawCircle(center, radius + 7, _shieldRing);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(shieldR, shieldR);
      canvas.drawCircle(Offset.zero, 1, _shieldSheen);
      canvas.restore();
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

  /// Particles are plain dots, so a single reused paint is enough and we skip
  /// the whole pass once the screen is saturated.
  void _drawParticlesCheap(Canvas canvas) {
    final paint = Paint();
    for (final particle in engine.particles) {
      paint.color = Color(particle.color).withValues(alpha: particle.alpha);
      canvas.drawCircle(Offset(particle.x, particle.y), particle.size, paint);
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
