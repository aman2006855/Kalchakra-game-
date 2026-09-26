import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/engine.dart';
import '../game/realms.dart';
import '../game/renderer.dart';

/// Repaint signal driven by the game loop.
class _Repaint extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Live game view: simulation loop, input layer, HUD and overlays.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.engine,
    required this.audio,
    required this.onRunFinished,
    required this.onQuit,
    required this.aimAssist,
    required this.haptics,
  });

  final GameEngine engine;
  final AudioService audio;
  final void Function(GameEngine engine) onRunFinished;
  final VoidCallback onQuit;
  final bool aimAssist;
  final bool haptics;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the simulation (Ticker) and the repaints (ChangeNotifier).
  late final Ticker _ticker;
  final _Repaint _repaint = _Repaint();
  Duration _lastTick = Duration.zero;
  Offset? _stickOrigin;
  Offset? _stickPosition;
  Offset? _pressOrigin;
  int _pointerId = -1;
  bool _finishHandled = false;
  bool _droneStarted = false;
  late GamePhase _lastPhase;

  @override
  void initState() {
    super.initState();
    widget.engine.aimAssist = widget.aimAssist;
    widget.engine.onEvent = _handleEvent;
    _lastPhase = widget.engine.phase;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    widget.engine.onEvent = null;
    widget.engine.releaseAllInput();
    unawaited(widget.audio.stopDrone());
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // The ticker's elapsed time is used (not a Stopwatch) so the simulation
    // also follows the fake clock while widget tests are pumping frames.
    final delta = (_lastTick == Duration.zero)
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    widget.engine.update(delta);

    // The engine changes phase from inside the ticker (realm intro -> play,
    // hit -> game over), so the widget tree has to be told about it.
    if (widget.engine.phase != _lastPhase) {
      _lastPhase = widget.engine.phase;
      if (mounted) setState(() {});
    }

    // Repaint the world, HUD and stick from the live engine state.
    if (mounted) _repaint.tick();

    if (widget.engine.phase == GamePhase.playing && !_droneStarted) {
      _droneStarted = true;
      unawaited(widget.audio.startDrone());
    }

    if (widget.engine.phase == GamePhase.gameOver && !_finishHandled) {
      _finishHandled = true;
      unawaited(widget.audio.stopDrone());
      unawaited(widget.audio.playGameOver());
      widget.onRunFinished(widget.engine);
    }
  }

  Future<void> _handleEvent(GameEvent event) async {
    if (!mounted) return;
    if (widget.haptics) {
      if (event.type == GameEventType.playerHit) {
        await HapticFeedback.heavyImpact();
      } else if (event.type == GameEventType.wraithDeath ||
          event.type == GameEventType.dropPickup) {
        await HapticFeedback.mediumImpact();
      } else if (event.type == GameEventType.enemyDeath ||
          event.type == GameEventType.hit) {
        await HapticFeedback.selectionClick();
      }
    }

    if (event.type == GameEventType.shot) {
      unawaited(widget.audio.playShot());
    } else if (event.type == GameEventType.hit) {
      unawaited(widget.audio.playHit());
    } else if (event.type == GameEventType.enemyDeath) {
      unawaited(widget.audio.playEnemyDeath());
    } else if (event.type == GameEventType.wraithDeath) {
      unawaited(widget.audio.playWraithDeath());
    } else if (event.type == GameEventType.playerHit) {
      unawaited(widget.audio.playPlayerHit());
    } else if (event.type == GameEventType.dropPickup) {
      unawaited(widget.audio.playPickup());
    } else if (event.type == GameEventType.realmAdvance) {
      unawaited(widget.audio.playRealm());
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    // Accept the grab during the realm intro too, otherwise the first drag of a
    // run looks like it is being ignored.
    if (widget.engine.phase != GamePhase.playing &&
        widget.engine.phase != GamePhase.realmTransition) {
      return;
    }
    if (_pointerId != -1) return;
    _pointerId = event.pointer;
    setState(() {
      _stickOrigin = event.localPosition;
      _stickPosition = event.localPosition;
      _pressOrigin = event.localPosition;
    });
    widget.engine.setStick(0, 0);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) return;
    _stickPosition = event.localPosition;
    final origin = _stickOrigin;
    if (origin == null) return;
    final delta = event.localPosition - origin;
    final distance = delta.distance;
    const deadZone = 6.0;
    const maxRadius = 70.0;
    if (distance <= deadZone) {
      widget.engine.setStick(0, 0);
      return;
    }
    final clamped = math.min(distance, maxRadius);
    final dx = delta.dx / distance * (clamped / maxRadius);
    final dy = delta.dy / distance * (clamped / maxRadius);
    widget.engine.setStick(
      _steerX(dx),
      _steerY(dy),
    );
  }

  /// Blends the stick with the movement assist. The assist only helps when the
  /// player is not actively steering, and it fades out in the deeper realms.
  double _steerX(double stick) {
    if (stick.abs() > 0.3) return stick;
    final threat = widget.engine.threatLevel * widget.engine.dodgeAssist;
    if (threat <= 0.01) return stick;
    return stick - widget.engine.threatDx * threat * 0.9;
  }

  double _steerY(double stick) {
    if (stick.abs() > 0.3) return stick;
    final threat = widget.engine.threatLevel * widget.engine.dodgeAssist;
    if (threat <= 0.01) return stick;
    return stick - widget.engine.threatDy * threat * 0.9;
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerId = -1;
    final press = _pressOrigin;
    final end = _stickPosition;

    // A tap (small movement) is an attack towards that spot; a drag is a move.
    if (press != null && end != null && (end - press).distance < 12) {
      widget.engine.fireAt(end.dx, end.dy);
      if (widget.haptics) unawaited(HapticFeedback.selectionClick());
    }

    setState(() {
      _stickOrigin = null;
      _stickPosition = null;
      _pressOrigin = null;
    });
    widget.engine.setStick(0, 0);
  }

  void _onPower(TimePower power) {
    if (widget.engine.activatePower(power)) {
      final name = power == TimePower.rewind
          ? 'rewind'
          : power == TimePower.freeze
              ? 'freeze'
              : 'fast';
      unawaited(widget.audio.playPower(name));
      if (widget.haptics) unawaited(HapticFeedback.mediumImpact());
      setState(() {});
    }
  }

  void _onSkill(bool Function() action, String sound) {
    if (action()) {
      unawaited(widget.audio.playPower(sound));
      if (widget.haptics) unawaited(HapticFeedback.mediumImpact());
      setState(() {});
    }
  }

  void _togglePause() {
    final engine = widget.engine;
    if (engine.phase == GamePhase.playing) {
      engine.pause();
      unawaited(widget.audio.stopDrone());
    } else if (engine.phase == GamePhase.paused) {
      engine.resume();
      unawaited(widget.audio.startDrone());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final accent = Color(engine.realm.color);

    return Scaffold(
      backgroundColor: KalchakraColors.voidBlack,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              // The repaint notifier is the paint source: without this the world
              // would only be painted once and the game would look frozen.
              child: AnimatedBuilder(
                animation: _repaint,
                builder: (context, child) => CustomPaint(
                  painter: GamePainter(
                    engine,
                    pointer: _stickPosition,
                  ),
                ),
              ),
            ),
          ),
          // Joystick visual.
          if (_stickOrigin != null && _stickPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _repaint,
                  builder: (context, child) => CustomPaint(
                    painter: _StickPainter(
                      origin: _stickOrigin!,
                      position: _stickPosition!,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
          // Realm intro sits below the HUD and never swallows input, so the
          // pause button and power buttons stay usable during the intro.
          if (engine.phase == GamePhase.realmTransition)
            Positioned.fill(
              child: IgnorePointer(
                child: _RealmIntro(realm: engine.realm, accent: accent),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedBuilder(
                animation: _repaint,
                builder: (context, child) => _Hud(
                  engine: engine,
                  accent: accent,
                  onPause: _togglePause,
                ),
              ),
            ),
          ),
          // Thumb friendly skill bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: AnimatedBuilder(
                animation: _repaint,
                builder: (context, child) => _SkillBar(
                  engine: engine,
                  accent: accent,
                  onPower: _onPower,
                  onSkill: _onSkill,
                ),
              ),
            ),
          ),
          if (engine.phase == GamePhase.paused)
            _Overlay(
              title: 'TIME FROZEN',
              accent: accent,
              children: <Widget>[
                _OverlayButton(
                  buttonKey: const Key('resume'),
                  label: 'RESUME',
                  onTap: _togglePause,
                ),
                _OverlayButton(
                  buttonKey: const Key('restart'),
                  label: 'RESTART RUN',
                  onTap: () {
                    setState(() => _finishHandled = false);
                    engine.startRun(
                      startRealmIndex: engine.realmIndex,
                      multiplier: engine.scoreMultiplier,
                    );
                    unawaited(widget.audio.startDrone());
                  },
                ),
                _OverlayButton(
                  buttonKey: const Key('quit'),
                  label: 'MAIN MENU',
                  onTap: () {
                    engine.quitToMenu();
                    widget.onQuit();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.engine,
    required this.accent,
    required this.onPause,
  });

  final GameEngine engine;
  final Color accent;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _leftColumn(accent)),
              const SizedBox(width: 8),
              Expanded(child: _rightColumn()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: <Widget>[
              Text(
                '${engine.killsInRealm}/${engine.realmGoal}',
                style: const TextStyle(
                  color: KalchakraColors.parchment,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: engine.killsInRealm / engine.realmGoal,
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                key: const Key('pause-button'),
                onPressed: onPause,
                icon: const Icon(Icons.pause, color: KalchakraColors.parchment),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        _ThreatMeter(engine: engine),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _leftColumn(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Health threads.
        Row(
          children: <Widget>[
            for (var i = 0; i < GameEngine.maxHealth; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _HealthThread(
                  alive: i < engine.health,
                  critical: engine.health == 1,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Temporal energy.
        Row(
          children: <Widget>[
            const Text('⏱', style: TextStyle(fontSize: 12, color: KalchakraColors.energyCyan)),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: engine.energy / GameEngine.maxEnergy,
                  minHeight: 7,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    KalchakraColors.energyCyan,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (engine.shieldActive)
          const Text(
            'SHIELD ACTIVE',
            style: TextStyle(
              color: Color(0xFF80D8FF),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _rightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          engine.score.toString(),
          key: const Key('score'),
          style: const TextStyle(
            color: KalchakraColors.gold,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (engine.scoreMultiplier > 1)
          Text(
            'x${engine.scoreMultiplier.toStringAsFixed(1)} bonus',
            style: const TextStyle(color: KalchakraColors.energyCyan, fontSize: 10),
          ),
        const SizedBox(height: 4),
        // Combo with its remaining window.
        SizedBox(
          height: 26,
          child: engine.combo > 1
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'x${engine.combo}',
                      key: const Key('combo'),
                      style: const TextStyle(
                        color: KalchakraColors.temporalRed,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 34,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: engine.comboProgress,
                          minHeight: 4,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            KalchakraColors.temporalRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _HealthThread extends StatelessWidget {
  const _HealthThread({required this.alive, required this.critical});

  final bool alive;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final color = !alive
        ? Colors.white24
        : critical
            ? KalchakraColors.temporalRed
            : KalchakraColors.gold;
    return Container(
      width: 18,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: alive
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.keyValue,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.active,
    required this.accent,
    required this.onTap,
    this.badge,
    this.progress,
  });

  final Key keyValue;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final String? badge;

  /// 0..1 recharge ring for dash and shield.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: keyValue,
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.35)
                  : KalchakraColors.cosmic.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? accent
                    : enabled
                        ? KalchakraColors.gold.withValues(alpha: 0.5)
                        : Colors.white24,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (progress != null && progress! < 1)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ),
                Icon(
                  icon,
                  size: 20,
                  color: enabled ? KalchakraColors.gold : Colors.white24,
                ),
                if (badge != null)
                  Positioned(
                    right: 4,
                    bottom: 2,
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: KalchakraColors.parchment,
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 0.5,
              color: enabled ? KalchakraColors.parchment : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

/// Real time readout of where incoming fire comes from.
class _ThreatMeter extends StatelessWidget {
  const _ThreatMeter({required this.engine});

  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final level = engine.threatLevel;
    if (level < 0.02) return const SizedBox.shrink();
    final angle = math.atan2(engine.threatDy, engine.threatDx);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 14),
      child: Row(
        children: <Widget>[
          Transform.rotate(
            angle: angle,
            child: const Icon(
              Icons.navigation,
              size: 14,
              color: KalchakraColors.temporalRed,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'INCOMING',
            style: TextStyle(
              color: KalchakraColors.temporalRed,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: level,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  KalchakraColors.temporalRed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar with the time powers and the two newer skills.
class _SkillBar extends StatelessWidget {
  const _SkillBar({
    required this.engine,
    required this.accent,
    required this.onPower,
    required this.onSkill,
  });

  final GameEngine engine;
  final Color accent;
  final void Function(TimePower power) onPower;
  final void Function(bool Function() action, String sound) onSkill;

  @override
  Widget build(BuildContext context) {
    final freezeReady =
        engine.energy >= GameEngine.freezeCost && engine.activePower == null;
    final fastReady =
        engine.energy >= GameEngine.fastCost && engine.activePower == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _PowerButton(
            keyValue: const Key('power-freeze'),
            icon: Icons.ac_unit,
            label: 'FREEZE',
            enabled: freezeReady,
            active: engine.activePower == TimePower.freeze,
            accent: accent,
            onTap: () => onPower(TimePower.freeze),
          ),
          _PowerButton(
            keyValue: const Key('power-rewind'),
            icon: Icons.replay,
            label: 'REWIND',
            enabled: engine.rewindUses > 0,
            active: false,
            accent: accent,
            badge: '${engine.rewindUses}',
            onTap: () => onPower(TimePower.rewind),
          ),
          _PowerButton(
            keyValue: const Key('power-fast'),
            icon: Icons.fast_forward,
            label: 'FAST',
            enabled: fastReady,
            active: engine.activePower == TimePower.fastForward,
            accent: accent,
            onTap: () => onPower(TimePower.fastForward),
          ),
          _PowerButton(
            keyValue: const Key('skill-dash'),
            icon: Icons.bolt,
            label: 'DASH',
            enabled: engine.dashReady,
            active: false,
            accent: accent,
            progress: engine.dashProgress,
            onTap: () => onSkill(engine.activateDash, 'fast'),
          ),
          _PowerButton(
            keyValue: const Key('skill-shield'),
            icon: Icons.shield,
            label: 'SHIELD',
            enabled: engine.shieldReady,
            active: engine.shieldActive,
            accent: const Color(0xFF80D8FF),
            progress: engine.shieldProgress,
            onTap: () => onSkill(engine.activateShield, 'freeze'),
          ),
        ],
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({
    required this.origin,
    required this.position,
    required this.color,
  });

  final Offset origin;
  final Offset position;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(origin, 42, paint);
    canvas.drawCircle(position, 18, paint);
  }

  @override
  bool shouldRepaint(covariant _StickPainter oldDelegate) =>
      oldDelegate.origin != origin || oldDelegate.position != position;
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: KalchakraColors.voidBlack.withValues(alpha: 0.82),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.buttonKey,
    required this.label,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: KalchakraColors.gold,
          side: const BorderSide(color: KalchakraColors.gold),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        ),
        child: Text(label, style: const TextStyle(letterSpacing: 1.5)),
      ),
    );
  }
}

class _RealmIntro extends StatelessWidget {
  const _RealmIntro({required this.realm, required this.accent});

  final Realm realm;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KalchakraColors.voidBlack.withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              realm.name,
              style: TextStyle(
                color: accent,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              realm.subtitle,
              style: const TextStyle(
                color: KalchakraColors.parchment,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: accent.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                realm.threat,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
