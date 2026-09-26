import 'dart:math' as math;

import 'realms.dart';

/// High level phase of a run.
enum GamePhase { idle, playing, paused, realmTransition, gameOver }

/// Enemy archetypes that spawn in the realms.
enum EnemyType { basic, shooter, fast, wraith, weaver }

/// Power-up kinds dropped by defeated enemies.
enum DropType { energy, health, rewind }

/// Time powers the player can weave.
enum TimePower { freeze, rewind, fastForward }

/// Cues the engine emits so the UI layer can play sound and haptics without
/// the engine depending on Flutter.
enum GameEventType {
  shot,
  hit,
  enemyDeath,
  wraithDeath,
  playerHit,
  dropPickup,
  powerActivated,
  realmAdvance,
  runComplete,
  gameOver,
  comboUp,
}

class GameEvent {
  const GameEvent(this.type, {this.x, this.y, this.value});

  final GameEventType type;
  final double? x;
  final double? y;
  final int? value;
}

class Bullet {
  Bullet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.fromPlayer,
    required this.color,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  final bool fromPlayer;
  final int color;
  double life = 3;
}

class Enemy {
  Enemy({
    required this.x,
    required this.y,
    required this.type,
    required this.hp,
    required this.radius,
    required this.speed,
    required this.color,
    this.wobbleSeed = 0,
    this.preferredDistance = 0,
    this.strafeSkill = 0.2,
  });

  double x;
  double y;
  final EnemyType type;
  int hp;
  final double radius;
  final double speed;
  final int color;
  double shootTimer = 0;
  double life = 0;

  /// Phase offset that gives each enemy its own weaving approach.
  double wobbleSeed;

  /// How far the enemy tries to stay from the player. 0 means "charge in".
  final double preferredDistance;

  /// 0..1 chance of slipping away from an incoming shot.
  final double strafeSkill;

  /// +1 / -1 side the enemy is currently weaving towards.
  int strafeDir = 1;
  double strafeTimer = 0;

  /// > 0 while the enemy is actively dodging, used for the dodge tell.
  double dodgeFlash = 0;

  /// > 0 while the enemy is winding up a shot, used for the aim tell so the
  /// player can read where the next bullet is coming from.
  double aimFlash = 0;

  /// > 0 while the enemy is arriving on screen, so a new wave is announced
  /// instead of simply appearing.
  double entryFlash = 0.9;

  /// Shots left in the current burst.
  int burstLeft = 0;

  /// Small delay between two shots of the same burst.
  double burstTimer = 0;

  /// Recent positions, drawn as fading echoes.
  final List<double> echoX = <double>[];
  final List<double> echoY = <double>[];
}

/// A short lived marker showing where the next enemy is about to appear, so an
/// arriving wave is never a surprise.
class SpawnMark {
  SpawnMark({required this.x, required this.y, required this.radius});

  double x;
  double y;
  final double radius;
  double life = 0.9;
}

class Drop {
  Drop({required this.x, required this.y, required this.type});

  double x;
  double y;
  final DropType type;
  double timer = 0;
}

class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.size,
    required this.color,
  });

  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  double size;
  final int color;

  double get alpha => (life / maxLife).clamp(0.0, 1.0);
}

/// Pure Dart simulation of Kalchakra.
///
/// The engine owns no widgets and no Flutter types, which keeps the whole game
/// balance unit testable and lets the renderer stay a thin drawing layer.
class GameEngine {
  GameEngine({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  // ---------------------------------------------------------------- world
  double _width = 420;
  double _height = 840;

  /// Uniform scale so the game feels identical on every phone size.
  double get scale =>
      math.max(0.2, math.min(_width, _height) / 420.0).toDouble();

  // ---------------------------------------------------------------- state
  GamePhase phase = GamePhase.idle;
  double elapsed = 0;
  bool completedRun = false;
  double _transitionLeft = 0;

  // player
  double playerX = 0;
  double playerY = 0;
  double _velX = 0;
  double _velY = 0;
  int health = 5;
  double energy = 100;
  bool invincible = false;
  double _invincibleLeft = 0;

  static const int maxHealth = 5;
  static const double maxEnergy = 100;
  static const int startingRewindUses = 3;
  static const int maxRewindUses = 5;

  int rewindUses = startingRewindUses;

  // Dash + shield
  static const double dashCooldown = 2.4;
  static const double dashDuration = 0.18;
  static const double dashSpeed = 900;
  static const double shieldCost = 25;
  static const double shieldRecharge = 11;

  double _dashLeft = 0;
  double _dashCooldownLeft = 0;
  double _dashX = 0;
  double _dashY = 0;
  double _shieldTimer = 0;
  double _shieldRechargeLeft = 0;

  // Aim lock set by tapping a target.
  double? _aimLockX;
  double? _aimLockY;
  double _aimLockLeft = 0;

  // Real time threat measurement: where incoming fire comes from.
  double _threatX = 0;
  double _threatY = 0;
  double _threatLevel = 0;

  // time power
  TimePower? activePower;
  double _powerLeft = 0;
  double _powerDuration = 0;

  // run stats
  int score = 0;
  int combo = 1;
  int maxCombo = 1;
  int kills = 0;
  int killsInRealm = 0;
  int realmIndex = 0;
  double scoreMultiplier = 1;

  // entities
  final List<Enemy> enemies = <Enemy>[];
  final List<Bullet> bullets = <Bullet>[];
  final List<Drop> drops = <Drop>[];
  final List<SpawnMark> spawnMarks = <SpawnMark>[];
  final List<Particle> particles = <Particle>[];

  /// Seconds accumulated towards the next enemy spawn.
  double spawnTimer = 0;
  double _comboLeft = 0;
  double _fireCooldown = 0;
  double _lastFireX = 0;
  double _lastFireY = -1;

  /// Monotonic frame counter, used to spread the expensive scans out over time
  /// instead of running them all on the same frame.
  int _frame = 0;

  /// How many frames between enemy dodge reads.
  static const int _dodgeScanInterval = 5;

  /// Hard ceiling on live bullets so a busy realm can never spiral.
  static const int maxBullets = 90;
  double _shake = 0;
  double _shakeX = 0;
  double _shakeY = 0;
  final List<double> _historyX = <double>[];
  final List<double> _historyY = <double>[];
  final List<double> _historyTime = <double>[];
  double _historyTimer = 0;

  // input
  double _stickX = 0;
  double _stickY = 0;
  bool _fireHeld = false;
  double? _aimX;
  double? _aimY;
  bool aimAssist = true;

  /// Optional sink for sound / haptic cues.
  void Function(GameEvent event)? onEvent;

  // ---------------------------------------------------------------- tuning
  static const double comboWindow = 3.5;
  static const double fireInterval = 0.2;
  static const double freezeCost = 30;
  static const double fastCost = 20;
  static const double freezeDuration = 3;
  static const double fastDuration = 2.5;
  static const double rewindLookback = 2.2;
  static const int maxParticles = 180;

  int get realmGoal => 20 + 5 * realmIndex;
  Realm get realm => kRealms[realmIndex];
  int get realmNumber => realmIndex + 1;
  double get playerRadius => 20 * scale;
  double get shakeX => _shakeX;
  double get shakeY => _shakeY;

  /// Current world speed multiplier produced by the active time power.
  double get worldMultiplier {
    if (activePower == TimePower.freeze) return 0.3;
    if (activePower == TimePower.fastForward) return 1.25;
    return 1;
  }

  /// 0..1 progress of the active power, for HUD rings.
  double get powerProgress =>
      _powerDuration <= 0 ? 0 : (_powerLeft / _powerDuration).clamp(0.0, 1.0);

  bool get isFlashing => invincible && (_invincibleLeft * 12).floor().isEven;

  /// Unit vector pointing towards the incoming enemy fire (screen space).
  double get threatDx => _threatX;

  double get threatDy => _threatY;

  /// 0..1 — how dangerous the current incoming fire is.
  double get threatLevel => _threatLevel;

  bool get shieldActive => _shieldTimer > 0;

  double get shieldProgress =>
      _shieldRechargeLeft <= 0 ? 1 : (1 - _shieldRechargeLeft / shieldRecharge).clamp(0.0, 1.0);

  double get dashProgress =>
      _dashCooldownLeft <= 0 ? 1 : (1 - _dashCooldownLeft / dashCooldown).clamp(0.0, 1.0);

  bool get dashReady => _dashCooldownLeft <= 0;

  bool get shieldReady => _shieldRechargeLeft <= 0 && energy >= shieldCost;

  /// How strongly the movement assist nudges the player away from fire.
  /// Deeper realms get less help, so difficulty still scales.
  double get dodgeAssist {
    final depth = realmIndex / (kRealms.length - 1);
    return (1 - 0.65 * depth).clamp(0.25, 1.0);
  }

  /// Kills needed to clear the current realm.
  void resize(double width, double height) {
    if (_width == width && _height == height) return;
    _width = width;
    _height = height;
    if (phase == GamePhase.idle) {
      playerX = width / 2;
      playerY = height / 2;
    } else {
      playerX = playerX.clamp(playerRadius, width - playerRadius).toDouble();
      playerY = playerY.clamp(
        playerRadius + 48 * scale,
        height - playerRadius,
      ).toDouble();
    }
  }

  double get width => _width;
  double get height => _height;

  // ---------------------------------------------------------------- flow
  void startRun({int startRealmIndex = 0, double multiplier = 1}) {
    realmIndex = startRealmIndex.clamp(0, kRealms.length - 1).toInt();
    scoreMultiplier = multiplier;
    resetRun();
    phase = GamePhase.playing;
    _beginRealmIntro();
  }

  void resetRun() {
    score = 0;
    combo = 1;
    maxCombo = 1;
    kills = 0;
    killsInRealm = 0;
    elapsed = 0;
    completedRun = false;
    rewindUses = startingRewindUses;
    health = maxHealth;
    energy = maxEnergy;
    invincible = false;
    _invincibleLeft = 0;
    activePower = null;
    _powerLeft = 0;
    _powerDuration = 0;
    playerX = _width / 2;
    playerY = _height / 2;
    _velX = 0;
    _velY = 0;
    enemies.clear();
    bullets.clear();
    drops.clear();
    particles.clear();
    _historyX.clear();
    _historyY.clear();
    _historyTime.clear();
    spawnTimer = 0;
    _comboLeft = 0;
    _fireCooldown = 0;
    _shake = 0;
  }

  void _beginRealmIntro() {
    phase = GamePhase.realmTransition;
    _transitionLeft = 2.4;
    _emitEvent(GameEvent(GameEventType.realmAdvance, value: realmNumber));
  }

  void pause() {
    // Pausing must also work during the realm intro, otherwise the pause
    // button looks broken for the first seconds of a run.
    if (phase == GamePhase.playing || phase == GamePhase.realmTransition) {
      phase = GamePhase.paused;
    }
  }

  void resume() {
    if (phase == GamePhase.paused) phase = GamePhase.playing;
  }

  void quitToMenu() {
    phase = GamePhase.idle;
    _stickX = 0;
    _stickY = 0;
    _fireHeld = false;
    _aimX = null;
    _aimY = null;
  }

  // ---------------------------------------------------------------- input
  // This is a phone game: every action is driven by touch. The stick is the
  // floating joystick from a drag, a tap is an attack and the skill bar covers
  // the rest.

  void setStick(double dx, double dy) {
    _stickX = dx;
    _stickY = dy;
  }

  void setFireHeld(bool held) {
    _fireHeld = held;
  }

  void setAim(double? x, double? y) {
    _aimX = x;
    _aimY = y;
  }

  void releaseAllInput() {
    _stickX = 0;
    _stickY = 0;
    _fireHeld = false;
    _aimX = null;
    _aimY = null;
  }

  // ---------------------------------------------------------------- powers
  bool activatePower(TimePower power) {
    if (phase != GamePhase.playing) return false;

    switch (power) {
      case TimePower.freeze:
        if (energy < freezeCost || activePower != null) return false;
        energy -= freezeCost;
        _startPower(TimePower.freeze, freezeDuration);
        break;
      case TimePower.fastForward:
        if (energy < fastCost || activePower != null) return false;
        energy -= fastCost;
        _startPower(TimePower.fastForward, fastDuration);
        break;
      case TimePower.rewind:
        if (rewindUses <= 0) return false;
        rewindUses--;
        _doRewind();
        break;
    }
    _emitEvent(GameEvent(GameEventType.powerActivated, value: power.index));
    return true;
  }

  void _startPower(TimePower power, double duration) {
    activePower = power;
    _powerDuration = duration;
    _powerLeft = duration;
  }

  // ---------------------------------------------------------------- skills
  /// Fires at a point immediately and locks the aim there for a moment, which
  /// is what a tap on the screen does.
  bool fireAt(double x, double y) {
    if (phase != GamePhase.playing) return false;
    _aimLockX = x;
    _aimLockY = y;
    _aimLockLeft = 1.6;
    return _fire(x, y);
  }

  /// Quick burst of movement with a sliver of invulnerability.
  bool activateDash() {
    if (phase != GamePhase.playing || _dashCooldownLeft > 0) return false;
    var dx = _stickX;
    var dy = _stickY;
    if (math.sqrt(dx * dx + dy * dy) < 0.1) {
      // No input: dash away from the incoming fire, otherwise forward.
      final length = math.sqrt(_threatX * _threatX + _threatY * _threatY);
      if (length > 0.05) {
        dx = -_threatX / length;
        dy = -_threatY / length;
      } else {
        dx = 0;
        dy = 1;
      }
    }
    final length = math.sqrt(dx * dx + dy * dy);
    if (length > 0.001) {
      _dashX = dx / length;
      _dashY = dy / length;
    } else {
      _dashX = 0;
      _dashY = 0;
    }
    _dashLeft = dashDuration;
    _dashCooldownLeft = dashCooldown;
    invincible = true;
    _invincibleLeft = math.max(_invincibleLeft, 0.3);
    _emitEvent(const GameEvent(GameEventType.powerActivated, value: 3));
    return true;
  }

  /// Absorbs incoming hits for a few seconds, then recharges.
  bool activateShield() {
    if (phase != GamePhase.playing) return false;
    if (_shieldRechargeLeft > 0 || energy < shieldCost) return false;
    energy -= shieldCost;
    _shieldTimer = 2.6;
    _shieldRechargeLeft = shieldRecharge;
    _emitEvent(const GameEvent(GameEventType.powerActivated, value: 4));
    return true;
  }

  void _doRewind() {
    double? targetX;
    double? targetY;
    for (var i = 0; i < _historyTime.length; i++) {
      if (elapsed - _historyTime[i] >= rewindLookback) {
        targetX = _historyX[i];
        targetY = _historyY[i];
        break;
      }
    }
    targetX ??= _historyX.isEmpty ? null : _historyX.first;
    targetY ??= _historyY.isEmpty ? null : _historyY.first;
    if (targetX != null && targetY != null) {
      playerX = targetX;
      playerY = targetY;
      _velX = 0;
      _velY = 0;
    }
    invincible = true;
    _invincibleLeft = 1.2;
    energy = math.min(maxEnergy, energy + 12);
    _burst(playerX, playerY, 0xFF00FFCC, 30);
  }

  // ---------------------------------------------------------------- update
  void update(double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.05).toDouble();
    if (dt <= 0) return;

    if (phase == GamePhase.realmTransition) {
      _transitionLeft -= dt;
      _updateParticles(dt);
      if (_transitionLeft <= 0) phase = GamePhase.playing;
      return;
    }
    if (phase != GamePhase.playing) return;

    elapsed += dt;
    _frame++;
    _updatePower(dt);
    _updateCooldowns(dt);
    _updatePlayer(dt);
    _updateSpawning(dt);
    _updateEnemies(dt);
    _updateBullets(dt);
    _updateThreat();
    _updateDrops(dt);
    _updateCombo(dt);
    _updateSpawnMarks(dt);
    _updateParticles(dt);
    _updateShake(dt);
    _checkRealmProgress();
  }

  void _updateCooldowns(double dt) {
    if (_dashLeft > 0) {
      _dashLeft -= dt;
      if (_dashLeft <= 0) _dashLeft = 0;
    }
    if (_dashCooldownLeft > 0) {
      _dashCooldownLeft = math.max(0, _dashCooldownLeft - dt);
    }
    if (_shieldTimer > 0) {
      _shieldTimer = math.max(0, _shieldTimer - dt);
    }
    if (_shieldRechargeLeft > 0) {
      _shieldRechargeLeft = math.max(0, _shieldRechargeLeft - dt);
    }
    if (_aimLockLeft > 0) {
      _aimLockLeft = math.max(0, _aimLockLeft - dt);
      if (_aimLockLeft == 0) {
        _aimLockX = null;
        _aimLockY = null;
      }
    }
  }

  /// Measures where the incoming enemy fire comes from, so the movement assist
  /// (and the HUD indicator) know which side is dangerous right now.
  void _updateThreat() {
    final radius = 150.0 * scale;
    var sumX = 0.0;
    var sumY = 0.0;
    var total = 0.0;
    for (final bullet in bullets) {
      if (bullet.fromPlayer) continue;
      final dx = bullet.x - playerX;
      final dy = bullet.y - playerY;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radius || distance < 0.001) continue;
      // Only count fire that is actually closing in on the player.
      final toward = (bullet.vx * -dx + bullet.vy * -dy) / (distance * (bullet.vx.abs() + bullet.vy.abs()).clamp(0.001, double.infinity));
      if (toward <= 0) continue;
      final weight = (1 - distance / radius) * toward;
      sumX += dx / distance * weight;
      sumY += dy / distance * weight;
      total += weight;
    }
    if (total <= 0.001) {
      _threatX = 0;
      _threatY = 0;
      _threatLevel = 0;
      return;
    }
    final length = math.sqrt(sumX * sumX + sumY * sumY);
    if (length <= 0.001) {
      _threatX = 0;
      _threatY = 0;
      _threatLevel = 0;
      return;
    }
    _threatX = sumX / length;
    _threatY = sumY / length;
    _threatLevel = total.clamp(0.0, 1.0);
  }

  void _updatePower(double dt) {
    if (activePower == null) return;
    _powerLeft -= dt;
    if (_powerLeft <= 0) {
      _powerLeft = 0;
      activePower = null;
      _powerDuration = 0;
    }
  }

  void _updatePlayer(double dt) {
    var mx = _stickX;
    var my = _stickY;
    final length = math.sqrt(mx * mx + my * my);
    if (length > 1) {
      mx /= length;
      my /= length;
    }

    final speed = 250 * scale * (activePower == TimePower.fastForward ? 1.6 : 1);
    final smoothing = math.min(1.0, dt * 12);
    _velX += (mx * speed - _velX) * smoothing;
    _velY += (my * speed - _velY) * smoothing;

    if (_dashLeft > 0) {
      playerX += _dashX * dashSpeed * scale * dt;
      playerY += _dashY * dashSpeed * scale * dt;
    } else {
      playerX += _velX * dt;
      playerY += _velY * dt;
    }

    final r = playerRadius;
    playerX = playerX.clamp(r, _width - r).toDouble();
    final topLimit = r + 48 * scale;
    playerY = playerY.clamp(topLimit, _height - r).toDouble();

    if (invincible) {
      _invincibleLeft -= dt;
      if (_invincibleLeft <= 0) invincible = false;
    }

    if (energy < maxEnergy) energy = math.min(maxEnergy, energy + 3.5 * dt);

    // Trail while moving.
    if (length > 0.05 && _random.nextDouble() < 0.5) {
      _emit(playerX, playerY, 0xFFFFD700, 1,
          speed: 0.4, life: 0.35, size: 2.2 * scale);
    }

    // Position history for the rewind power.
    _historyTimer += dt;
    if (_historyTimer >= 0.08) {
      _historyTimer = 0;
      _historyX.add(playerX);
      _historyY.add(playerY);
      _historyTime.add(elapsed);
      if (_historyX.length > 45) {
        _historyX.removeAt(0);
        _historyY.removeAt(0);
        _historyTime.removeAt(0);
      }
    }

    _updateFiring(dt);
  }

  void _updateFiring(double dt) {
    _fireCooldown -= dt;
    final wantsFire = aimAssist || _fireHeld;
    if (!wantsFire) return;

    double? targetX = _aimLockLeft > 0 ? _aimLockX : _aimX;
    double? targetY = _aimLockLeft > 0 ? _aimLockY : _aimY;

    if (aimAssist && targetX == null) {
      final enemy = _nearestEnemy();
      if (enemy != null) {
        targetX = enemy.x;
        targetY = enemy.y;
      }
    }
    if (targetX == null || targetY == null) return;
    _fire(targetX, targetY);
  }

  /// Spawns one player bullet towards [targetX], [targetY].
  bool _fire(double targetX, double targetY) {
    if (_fireCooldown > 0) return false;
    var dx = targetX - playerX;
    var dy = targetY - playerY;
    var distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1) {
      // Tapped right on top of the weaver: keep firing the way we were already
      // aiming instead of swallowing the shot.
      dx = _lastFireX;
      dy = _lastFireY;
      distance = 1;
    }

    _fireCooldown = fireInterval;
    _lastFireX = dx / distance;
    _lastFireY = dy / distance;
    final speed = 640 * scale;
    _addBullet(
      Bullet(
        x: playerX,
        y: playerY,
        vx: _lastFireX * speed,
        vy: _lastFireY * speed,
        radius: 8 * scale,
        fromPlayer: true,
        color: 0xFFFFD700,
      ),
    );
    _emitEvent(GameEvent(GameEventType.shot, x: playerX, y: playerY));
    return true;
  }

  /// Adds a bullet, dropping the oldest one if the world is already saturated.
  void _addBullet(Bullet bullet) {
    if (bullets.length >= maxBullets) {
      bullets.removeAt(0);
    }
    bullets.add(bullet);
  }

  Enemy? _nearestEnemy() {
    Enemy? best;
    var bestDistance = double.infinity;
    for (final enemy in enemies) {
      final dx = enemy.x - playerX;
      final dy = enemy.y - playerY;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = enemy;
      }
    }
    return best;
  }

  /// Spawns arrive in small readable waves rather than as one wall.
  ///
  /// Every realm opens with a small number of enemies, and both the size of the
  /// wave and the number allowed on screen creep up as the realm gets cleared,
  /// so the pressure builds gradually instead of landing all at once.
  void _updateSpawning(double dt) {
    spawnTimer += dt;
    // A negative timer is the quiet beat between two waves.
    if (spawnTimer < 0) return;
    if (spawnTimer < spawnInterval) return;

    final cap = liveEnemyCap;
    var spawned = 0;
    final wave = spawnWaveSize;
    for (var i = 0; i < wave; i++) {
      if (enemies.length >= cap) break;
      spawnEnemy();
      spawned++;
    }
    // Always reset, even if the cap blocked the wave, otherwise a full screen
    // would stall the spawner until the player killed something.
    spawnTimer = spawned > 0 ? -_quietBeat : 0;
  }

  /// Seconds between waves. Starts relaxed in the first realm and tightens.
  double get spawnInterval => math.max(0.9, 2.4 - 0.18 * realmIndex);

  /// How many enemies arrive in a single wave. One at the very start, a couple
  /// mid realm, a small group once the player is clearing the realm out.
  int get spawnWaveSize {
    if (realmProgress < 0.25) return 1;
    if (realmProgress < 0.65) return 2;
    return 3;
  }

  /// The pause after a wave so the player can see it coming and react.
  double get _quietBeat => math.max(0.35, 0.9 - 0.06 * realmIndex);

  /// How many enemies may be on screen *right now*. The ceiling for the realm
  /// opens up gradually with progress, so the very first seconds of a realm are
  /// always calm no matter how deep the player is.
  int get liveEnemyCap {
    final ceiling = maxEnemies;
    // Every realm opens with only a handful on screen, even the deepest one, so
    // the first seconds of a realm are never a wall of enemies.
    final start = (3 + realmIndex ~/ 3).toDouble();
    final ramp = start + (ceiling - start) * realmProgress;
    return ramp.round().clamp(start.round(), ceiling);
  }

  /// The most enemies this realm will ever allow at once.
  int get maxEnemies => math.min(24, 7 + 2 * realmIndex).toInt();

  /// Enemy abilities unlock one realm at a time instead of all landing on the
  /// player at once:
  ///
  /// * realm 0 — close in and ram, nothing else
  /// * realm 1 — shooters appear and open fire
  /// * realm 2 — enemies start dodging the player's shots
  /// * realm 3 — weavers appear and fan out bursts
  bool get _canFire => realmIndex >= 1;

  bool get _canDodge => realmIndex >= 2;

  bool get _canWeaveHard => realmIndex >= 3;

  /// 0..1 — how far through the current realm the player is. Enemies speed up
  /// slightly as a realm gets cleared so the last few kills still bite.
  double get realmProgress =>
      realmGoal <= 0 ? 0 : (killsInRealm / realmGoal).clamp(0.0, 1.0);

  /// The single difficulty scalar used for enemy speed.
  double get difficulty =>
      1 + 0.12 * realmIndex + 0.2 * realmProgress;

  /// Spawns one enemy on a random screen edge. Public so tests can drive it.
  void spawnEnemy({EnemyType? forcedType}) {
    final type = forcedType ?? _rollEnemyType();
    final side = _random.nextInt(4);
    double x;
    double y;
    switch (side) {
      case 0:
        x = _random.nextDouble() * _width;
        y = -40 * scale;
      case 1:
        x = _width + 40 * scale;
        y = _random.nextDouble() * _height;
      case 2:
        x = _random.nextDouble() * _width;
        y = _height + 40 * scale;
      default:
        x = -40 * scale;
        y = _random.nextDouble() * _height;
    }

    final difficulty = this.difficulty;
    final int hp;
    final double radius;
    final double speed;
    final double preferred;
    final double strafe;
    switch (type) {
      case EnemyType.wraith:
        hp = 6;
        radius = 26 * scale;
        speed = 70 * scale * difficulty;
        preferred = 20 * scale;
        strafe = 0.10;
      case EnemyType.shooter:
        hp = 2;
        radius = 17 * scale;
        speed = 95 * scale * difficulty;
        preferred = 250 * scale;
        strafe = 0.34;
      case EnemyType.fast:
        hp = 1;
        radius = 14 * scale;
        speed = 175 * scale * difficulty;
        preferred = 90 * scale;
        strafe = 0.42;
      case EnemyType.basic:
        hp = 1;
        radius = 17 * scale;
        speed = 105 * scale * difficulty;
        // Basic enemies close in and trade: they ram and shoot.
        preferred = 0;
        strafe = 0.24;
      case EnemyType.weaver:
        hp = 4;
        radius = 21 * scale;
        speed = 110 * scale * difficulty;
        // Held at mid range, constantly sliding sideways.
        preferred = 210 * scale;
        strafe = 0.55;
    }

    spawnMarks.add(SpawnMark(x: x, y: y, radius: radius));
    if (spawnMarks.length > 24) spawnMarks.removeAt(0);

    enemies.add(
      Enemy(
        x: x,
        y: y,
        type: type,
        hp: hp,
        radius: radius,
        speed: speed,
        color: realm.color,
        wobbleSeed: _random.nextDouble() * math.pi * 2,
        preferredDistance: preferred,
        strafeSkill: (strafe + 0.05 * realmIndex).clamp(0.0, 0.85),
      ),
    );
  }

  EnemyType _rollEnemyType() {
    final roll = _random.nextDouble();
    // Deeper realms mix in more shooters and weavers, so the incoming fire
    // gets denser and less predictable. The first realm is deliberately plain
    // so a new player is never hit with every archetype at once.
    final wraithChance = realmIndex >= 4 ? 0.06 + 0.03 * (realmIndex - 4) : 0.0;
    final shooterChance =
        realmIndex >= 1 ? (0.20 + 0.035 * (realmIndex - 1)).clamp(0.0, 0.42) : 0.0;
    final weaverChance = realmIndex >= 3 ? 0.06 + 0.03 * (realmIndex - 3) : 0.0;
    if (roll < wraithChance) return EnemyType.wraith;
    if (roll < wraithChance + weaverChance) return EnemyType.weaver;
    if (roll < wraithChance + weaverChance + shooterChance) {
      return EnemyType.shooter;
    }
    // The fast rusher is the one archetype the very first realm is allowed.
    if (roll < wraithChance + weaverChance + shooterChance + 0.28) {
      return EnemyType.fast;
    }
    return EnemyType.basic;
  }

  void _updateEnemies(double dt) {
    final mult = worldMultiplier;
    final margin = 90.0 * scale;
    // Dodging only unlocks from the third realm, and gets likelier after that.
    final dodgeSkill =
        _canDodge ? (0.14 + 0.11 * (realmIndex - 2)).clamp(0.0, 0.8) : 0.0;
    // Weaving is the one movement trick available from the start, but it stays
    // shallow until the deeper realms.
    final weaveScale = _canWeaveHard ? 0.4 + 0.08 * realmIndex : 0.3;
    // Scanning every bullet for every enemy is the most expensive thing the
    // simulation can do, so the dodge read runs on a fixed cadence instead of
    // once per enemy per frame. 12 reads a second is still far faster than a
    // human can react to.
    final scanDodge = dodgeSkill > 0 && _frame % _dodgeScanInterval == 0;

    for (var i = enemies.length - 1; i >= 0; i--) {
      final enemy = enemies[i];
      enemy.life += dt;
      if (enemy.dodgeFlash > 0) {
        enemy.dodgeFlash = math.max(0, enemy.dodgeFlash - dt);
      }
      if (enemy.aimFlash > 0) {
        enemy.aimFlash = math.max(0, enemy.aimFlash - dt);
      }
      if (enemy.entryFlash > 0) {
        enemy.entryFlash = math.max(0, enemy.entryFlash - dt);
      }

      // Echo trail, a few samples per second.
      if (_random.nextDouble() < dt * 4) {
        enemy.echoX.add(enemy.x);
        enemy.echoY.add(enemy.y);
        if (enemy.echoX.length > 10) {
          enemy.echoX.removeAt(0);
          enemy.echoY.removeAt(0);
        }
      }

      var dx = playerX - enemy.x;
      var dy = playerY - enemy.y;
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance > 0.001) {
        // Steer towards the ring the enemy wants to sit on.
        final radial = distance <= enemy.preferredDistance
            ? -0.35
            : (distance - enemy.preferredDistance) / distance;
        // Weave sideways so they do not queue up in a straight line.
        enemy.strafeTimer -= dt;
        if (enemy.strafeTimer <= 0) {
          enemy.strafeTimer = 0.7 + _random.nextDouble() * 1.6;
          enemy.strafeDir = _random.nextDouble() < 0.5 ? -1 : 1;
        }
        final wobble = math.sin(elapsed * 2 + enemy.wobbleSeed) * 0.25;
        final weave = (0.35 + enemy.strafeSkill) * weaveScale + wobble;

        var dirX = dx / distance * radial + (-dy / distance) * enemy.strafeDir * weave;
        var dirY = dy / distance * radial + (dx / distance) * enemy.strafeDir * weave;

        // Slip away from a shot that is about to land on them.
        final incoming = scanDodge ? _incomingShot(enemy) : null;
        if (incoming != null && _random.nextDouble() < dodgeSkill * 3 * dt) {
          final length = math.sqrt(incoming.vx * incoming.vx + incoming.vy * incoming.vy);
          if (length > 0.001) {
            final perpX = -incoming.vy / length;
            final perpY = incoming.vx / length;
            final side = (incoming.x - enemy.x) * perpX +
                    (incoming.y - enemy.y) * perpY >=
                0
                ? 1.0
                : -1.0;
            dirX += perpX * side * 2.2;
            dirY += perpY * side * 2.2;
            enemy.dodgeFlash = 0.18;
          }
        }

        final dirLength = math.sqrt(dirX * dirX + dirY * dirY);
        if (dirLength > 0.001) {
          final boost = enemy.dodgeFlash > 0 ? 1.9 : 1.0;
          enemy.x += dirX / dirLength * enemy.speed * mult * dt * boost;
          enemy.y += dirY / dirLength * enemy.speed * mult * dt * boost;
        }
      }

      _updateEnemyFire(enemy, dt, distance);

      // Contact damage.
      if (!invincible && distance < playerRadius + enemy.radius) {
        _hurtPlayer(enemy.x, enemy.y);
        // Shove the player away so they are not glued to the enemy.
        if (distance > 0.001) {
          playerX += dx / distance * 6 * scale;
          playerY += dy / distance * 6 * scale;
        }
      }

      final offScreen = enemy.x < -margin ||
          enemy.x > _width + margin ||
          enemy.y < -margin ||
          enemy.y > _height + margin;
      if ((offScreen && enemy.life > 2) || enemy.life > 40) {
        enemies.removeAt(i);
      }
    }
  }

  /// The player bullet closest to [enemy] that is currently heading at it.
  Bullet? _incomingShot(Enemy enemy) {
    Bullet? best;
    var bestTime = double.infinity;
    for (final bullet in bullets) {
      // Enemy fire can never dodge the player, so skip it without branching on
      // the rest of the list.
      if (!bullet.fromPlayer) continue;
      final dx = enemy.x - bullet.x;
      final dy = enemy.y - bullet.y;
      final speed = math.sqrt(bullet.vx * bullet.vx + bullet.vy * bullet.vy);
      if (speed <= 0.001) continue;
      // Time until the bullet reaches the enemy's current position.
      final closing = (dx * bullet.vx + dy * bullet.vy) / (speed * speed);
      if (closing <= 0) continue;
      final missX = dx - bullet.vx * closing;
      final missY = dy - bullet.vy * closing;
      final miss = math.sqrt(missX * missX + missY * missY);
      if (miss > enemy.radius * 3) continue;
      if (closing < bestTime) {
        bestTime = closing;
        best = bullet;
      }
    }
    return best;
  }

  /// Every archetype can shoot. A short wind-up ([Enemy.aimFlash]) telegraphs
  /// the shot so the player can read the direction, and the cadence, burst size
  /// and accuracy all scale with the realm depth.
  void _updateEnemyFire(Enemy enemy, double dt, double distance) {
    if (!_canFire || distance > 560 * scale || distance < 0.001) {
      enemy.shootTimer = 0;
      enemy.burstLeft = 0;
      return;
    }

    // Burst shots keep their own short timer so the follow ups stay tight.
    if (enemy.burstLeft > 0) {
      enemy.burstTimer -= dt;
      if (enemy.burstTimer <= 0) {
        enemy.burstLeft--;
        enemy.burstTimer = 0.14;
        _enemyShoot(enemy, distance);
      }
      return;
    }

    enemy.shootTimer += dt;
    if (enemy.shootTimer < _shotInterval(enemy)) return;
    enemy.shootTimer = 0;

    final burst = _burstSize(enemy);
    enemy.burstLeft = burst - 1;
    enemy.burstTimer = 0.14;
    _enemyShoot(enemy, distance);
  }

  double _shotInterval(Enemy enemy) {
    final depth = realmIndex;
    switch (enemy.type) {
      case EnemyType.weaver:
        return math.max(0.55, 1.7 - 0.12 * depth);
      case EnemyType.shooter:
        return math.max(0.75, 2.1 - 0.14 * depth);
      case EnemyType.fast:
        return math.max(1.6, 3.2 - 0.16 * depth);
      case EnemyType.basic:
        return math.max(2.0, 3.6 - 0.18 * depth);
      case EnemyType.wraith:
        return math.max(1.2, 2.4 - 0.14 * depth);
    }
  }

  int _burstSize(Enemy enemy) {
    if (enemy.type != EnemyType.weaver) return 1;
    // Weavers open up with two or three round bursts once the realm gets deep.
    final extra = (realmIndex - 2).clamp(0, 1).toInt();
    return 2 + extra;
  }

  void _enemyShoot(Enemy enemy, double distance) {
    if (distance < 0.001) return;
    // Telegraph the shot so the threat arrow has something honest to point at.
    enemy.aimFlash = 0.3;
    // Lead the shot slightly so the player cannot just stand still forever.
    final lead = (0.18 + 0.05 * realmIndex).clamp(0.0, 0.6);
    final dx = playerX - enemy.x;
    final dy = playerY - enemy.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.001) return;
    final speed = 320 * scale * (1 + 0.06 * realmIndex);
    final baseX = (dx + _velX * lead) / d * speed;
    final baseY = (dy + _velY * lead) / d * speed;

    // Weavers fan their burst out sideways so a single sidestep is not enough.
    final spread = enemy.type == EnemyType.weaver ? 0.20 : 0.0;
    if (spread <= 0) {
      _addBullet(
        Bullet(
          x: enemy.x,
          y: enemy.y,
          vx: baseX,
          vy: baseY,
          radius: 6 * scale,
          fromPlayer: false,
          color: 0xFFFF3366,
        ),
      );
      return;
    }
    final fan = (elapsed * 2).floor().isEven ? 1.0 : -1.0;
    for (var i = -1; i <= 1; i++) {
      final angle = i * spread * fan;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      _addBullet(
        Bullet(
          x: enemy.x,
          y: enemy.y,
          vx: baseX * cosA - baseY * sinA,
          vy: baseX * sinA + baseY * cosA,
          radius: 6 * scale,
          fromPlayer: false,
          color: 0xFFFF3366,
        ),
      );
    }
  }

  void _updateBullets(double dt) {
    final mult = worldMultiplier;
    final margin = 60.0 * scale;

    for (var i = bullets.length - 1; i >= 0; i--) {
      final bullet = bullets[i];
      bullet.x += bullet.vx * mult * dt;
      bullet.y += bullet.vy * mult * dt;
      bullet.life -= dt;

      if (bullet.life <= 0 ||
          bullet.x < -margin ||
          bullet.x > _width + margin ||
          bullet.y < -margin ||
          bullet.y > _height + margin) {
        bullets.removeAt(i);
        continue;
      }

      if (bullet.fromPlayer) {
        var consumed = false;
        for (var j = enemies.length - 1; j >= 0; j--) {
          final enemy = enemies[j];
          final dx = bullet.x - enemy.x;
          final dy = bullet.y - enemy.y;
          final radius = enemy.radius + bullet.radius;
          if (dx * dx + dy * dy <= radius * radius) {
            enemy.hp--;
            _burst(bullet.x, bullet.y, 0xFFFFD700, 8);
            _emitEvent(GameEvent(GameEventType.hit, x: bullet.x, y: bullet.y));
            if (enemy.hp <= 0) {
              _onEnemyDefeated(enemy);
              enemies.removeAt(j);
            }
            consumed = true;
            break;
          }
        }
        if (consumed) bullets.removeAt(i);
      } else if (!invincible) {
        final dx = bullet.x - playerX;
        final dy = bullet.y - playerY;
        final radius = playerRadius + bullet.radius;
        if (dx * dx + dy * dy <= radius * radius) {
          _hurtPlayer(bullet.x, bullet.y);
          bullets.removeAt(i);
        }
      }
    }
  }

  void _onEnemyDefeated(Enemy enemy) {
    kills++;
    killsInRealm++;
    final wraith = enemy.type == EnemyType.wraith;
    final base = wraith ? 450 : 100;
    score += (base * combo * scoreMultiplier).round();
    combo = math.min(combo + 1, 10);
    maxCombo = math.max(maxCombo, combo);
    _comboLeft = comboWindow;
    _burst(enemy.x, enemy.y, enemy.color, wraith ? 30 : 15);
    _emitEvent(
      GameEvent(
        wraith ? GameEventType.wraithDeath : GameEventType.enemyDeath,
        x: enemy.x,
        y: enemy.y,
        value: combo,
      ),
    );
    if (combo > 1) {
      _emitEvent(GameEvent(GameEventType.comboUp, value: combo));
    }
    _maybeDrop(enemy.x, enemy.y);
  }

  void _maybeDrop(double x, double y) {
    if (_random.nextDouble() > 0.12) return;
    final roll = _random.nextDouble();
    DropType type;
    if (health < maxHealth && roll < 0.4) {
      type = DropType.health;
    } else if (rewindUses < maxRewindUses && roll < 0.65) {
      type = DropType.rewind;
    } else {
      type = DropType.energy;
    }
    drops.add(Drop(x: x, y: y, type: type));
  }

  void _updateDrops(double dt) {
    for (var i = drops.length - 1; i >= 0; i--) {
      final drop = drops[i];
      drop.timer += dt;

      // Drift gently toward the player so pickups feel alive.
      final dx = playerX - drop.x;
      final dy = playerY - drop.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > 1) {
        final pull = math.min(1.0, dt * 1.2) * 40 * scale;
        drop.x += dx / distance * pull;
        drop.y += dy / distance * pull;
      }

      final radius = playerRadius + 16 * scale;
      if (distance <= radius) {
        _applyDrop(drop);
        drops.removeAt(i);
        continue;
      }
      if (drop.timer > 10) drops.removeAt(i);
    }
  }

  void _applyDrop(Drop drop) {
    switch (drop.type) {
      case DropType.energy:
        energy = math.min(maxEnergy, energy + 30);
        break;
      case DropType.health:
        health = math.min(maxHealth, health + 1);
        break;
      case DropType.rewind:
        rewindUses = math.min(maxRewindUses, rewindUses + 1);
        break;
    }
    _burst(drop.x, drop.y, 0xFF00FFCC, 14);
    _emitEvent(
      const GameEvent(GameEventType.dropPickup, value: 0),
    );
  }

  void _hurtPlayer(double fromX, double fromY) {
    if (invincible || phase != GamePhase.playing) return;
    if (_shieldTimer > 0) {
      // The weave shield eats the hit entirely.
      _shieldTimer = 0;
      _burst(playerX, playerY, 0xFF80D8FF, 24);
      _emitEvent(GameEvent(GameEventType.playerHit, value: health));
      return;
    }
    health--;
    invincible = true;
    _invincibleLeft = 1;
    combo = 1;
    _comboLeft = 0;
    _shake = math.max(_shake, 18 * scale);
    _burst(playerX, playerY, 0xFFFF3366, 20);
    _emitEvent(
      GameEvent(GameEventType.playerHit, x: fromX, y: fromY, value: health),
    );
    if (health <= 0) {
      health = 0;
      _gameOver();
    }
  }

  void _updateCombo(double dt) {
    if (combo <= 1) return;
    _comboLeft -= dt;
    if (_comboLeft > 0) return;
    combo--;
    _comboLeft = combo > 1 ? 1 : 0;
  }

  /// 0..1 remaining combo window, for the HUD bar.
  double get comboProgress =>
      combo <= 1 ? 0 : (_comboLeft / comboWindow).clamp(0.0, 1.0);

  void _checkRealmProgress() {
    if (killsInRealm < realmGoal) return;
    if (enemies.isNotEmpty) return;

    if (realmIndex >= kRealms.length - 1) {
      score += (50000 * scoreMultiplier).round();
      completedRun = true;
      _gameOver();
      return;
    }

    realmIndex++;
    killsInRealm = 0;
    score += (10000 * scoreMultiplier).round();
    _beginRealmIntro();
  }

  void _gameOver() {
    if (phase == GamePhase.gameOver) return;
    phase = GamePhase.gameOver;
    _emitEvent(GameEvent(GameEventType.gameOver, value: score));
  }

  // ------------------------------------------------------------ particles
  void _emit(
    double x,
    double y,
    int color,
    int count, {
    double speed = 2,
    double life = 1,
    double size = 3,
  }) {
    for (var i = 0; i < count; i++) {
      if (particles.length >= maxParticles) break;
      final angle = _random.nextDouble() * math.pi * 2;
      final magnitude = speed * (0.5 + _random.nextDouble() * 0.5) * 60 * scale;
      final lifeSpan = life * (0.6 + _random.nextDouble() * 0.4);
      particles.add(
        Particle(
          x: x,
          y: y,
          vx: math.cos(angle) * magnitude,
          vy: math.sin(angle) * magnitude,
          life: lifeSpan,
          maxLife: lifeSpan,
          size: size * scale * (0.5 + _random.nextDouble() * 0.5),
          color: color,
        ),
      );
    }
  }

  void _burst(double x, double y, int color, int count) {
    _emit(x, y, color, count, speed: 5, life: 0.7, size: 4);
  }

  void _updateSpawnMarks(double dt) {
    for (var i = spawnMarks.length - 1; i >= 0; i--) {
      final mark = spawnMarks[i];
      mark.life -= dt;
      if (mark.life <= 0) spawnMarks.removeAt(i);
    }
  }

  void _updateParticles(double dt) {
    // The drag factor is the same for every particle, so it is computed once
    // per frame rather than once per particle.
    final drag = math.pow(0.12, dt).toDouble();
    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= drag;
      p.vy *= drag;
      p.life -= dt;
      if (p.life <= 0) particles.removeAt(i);
    }
  }

  void _updateShake(double dt) {
    if (_shake <= 0.05) {
      _shake = 0;
      _shakeX = 0;
      _shakeY = 0;
      return;
    }
    _shakeX = (_random.nextDouble() - 0.5) * _shake;
    _shakeY = (_random.nextDouble() - 0.5) * _shake;
    _shake = math.max(0, _shake - 60 * scale * dt);
  }

  void _emitEvent(GameEvent event) => onEvent?.call(event);
}
