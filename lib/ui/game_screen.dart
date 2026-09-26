import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/engine.dart';
import '../game/realms.dart';
import '../game/renderer.dart';

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
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Offset? _stickOrigin;
  Offset? _stickPosition;
  int _pointerId = -1;
  bool _finishHandled = false;
  bool _droneStarted = false;

  @override
  void initState() {
    super.initState();
    widget.engine.aimAssist = widget.aimAssist;
    widget.engine.onEvent = _handleEvent;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.engine.onEvent = null;
    widget.engine.releaseAllInput();
    unawaited(widget.audio.stopDrone());
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = (_lastTick == Duration.zero)
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    widget.engine.update(delta);

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
    if (widget.engine.phase != GamePhase.playing) return;
    if (_pointerId != -1) return;
    _pointerId = event.pointer;
    _stickOrigin = event.localPosition;
    _stickPosition = event.localPosition;
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
    widget.engine.setStick(
      delta.dx / distance * (clamped / maxRadius),
      delta.dy / distance * (clamped / maxRadius),
    );
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerId = -1;
    _stickOrigin = null;
    _stickPosition = null;
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
              child: CustomPaint(
                painter: GamePainter(
                  engine,
                  pointer: _stickPosition,
                ),
              ),
            ),
          ),
          // Joystick visual.
          if (_stickOrigin != null && _stickPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StickPainter(
                    origin: _stickOrigin!,
                    position: _stickPosition!,
                    color: accent,
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
              child: _Hud(
                engine: engine,
                accent: accent,
                onPower: _onPower,
                onPause: _togglePause,
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
    required this.onPower,
    required this.onPause,
  });

  final GameEngine engine;
  final Color accent;
  final void Function(TimePower power) onPower;
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
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _leftColumn(Color accent) {
    final freezeReady = engine.energy >= GameEngine.freezeCost &&
        engine.activePower == null;
    final fastReady = engine.energy >= GameEngine.fastCost &&
        engine.activePower == null;
    final rewindReady = engine.rewindUses > 0;

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
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _PowerButton(
              keyValue: const Key('power-freeze'),
              icon: Icons.ac_unit,
              enabled: freezeReady,
              active: engine.activePower == TimePower.freeze,
              accent: accent,
              onTap: () => onPower(TimePower.freeze),
            ),
            const SizedBox(width: 6),
            _PowerButton(
              keyValue: const Key('power-rewind'),
              icon: Icons.replay,
              enabled: rewindReady,
              active: false,
              accent: accent,
              badge: '${engine.rewindUses}',
              onTap: () => onPower(TimePower.rewind),
            ),
            const SizedBox(width: 6),
            _PowerButton(
              keyValue: const Key('power-fast'),
              icon: Icons.fast_forward,
              enabled: fastReady,
              active: engine.activePower == TimePower.fastForward,
              accent: accent,
              onTap: () => onPower(TimePower.fastForward),
            ),
          ],
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
    required this.enabled,
    required this.active,
    required this.accent,
    required this.onTap,
    this.badge,
  });

  final Key keyValue;
  final IconData icon;
  final bool enabled;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: keyValue,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.35)
              : KalchakraColors.cosmic.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
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
            Icon(
              icon,
              size: 18,
              color: enabled ? KalchakraColors.gold : Colors.white24,
            ),
            if (badge != null)
              Positioned(
                right: 3,
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
          ],
        ),
      ),
    );
  }
}
