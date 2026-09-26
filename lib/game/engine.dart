import 'dart:math' as math;

import 'realms.dart';

/// High level phase of a run.
enum GamePhase { idle, playing, paused, realmTransition, gameOver }

/// Enemy archetypes that spawn in the realms.
enum EnemyType { basic, shooter, fast, wraith }

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

  /// Recent positions, drawn as fading echoes.
  final List<double> echoX = <double>[];
  final List<double> echoY = <double>[];
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
  final List<Particle> particles = <Particle>[];

  /// Seconds accumulated towards the next enemy spawn.
  double spawnTimer = 0;
  double _comboLeft = 0;
  double _fireCooldown = 0;
  double _shake = 0;
  double _shakeX = 0;
  double _shakeY = 0;
  final List<double> _historyX = <double>[];
  final List<double> _historyY = <double>[];
  final List<double> _historyTime = <double>[];
  double _historyTimer = 0;

  // input
  double _keyX = 0;
  double _keyY = 0;
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
  static const int maxParticles = 220;

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
    _keyX = 0;
    _keyY = 0;
    _fireHeld = false;
    _aimX = null;
    _aimY = null;
  }

  // ---------------------------------------------------------------- input
  void setKeyboard(double dx, double dy) {
    _keyX = dx;
    _keyY = dy;
  }

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
    _keyX = 0;
    _keyY = 0;
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
    _updatePower(dt);
    _updatePlayer(dt);
    _updateSpawning(dt);
    _updateEnemies(dt);
    _updateBullets(dt);
    _updateDrops(dt);
    _updateCombo(dt);
    _updateParticles(dt);
    _updateShake(dt);
    _checkRealmProgress();
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
    var mx = _keyX + _stickX;
    var my = _keyY + _stickY;
    final length = math.sqrt(mx * mx + my * my);
    if (length > 1) {
      mx /= length;
      my /= length;
    }

    final speed = 250 * scale * (activePower == TimePower.fastForward ? 1.6 : 1);
    final smoothing = math.min(1.0, dt * 12);
    _velX += (mx * speed - _velX) * smoothing;
    _velY += (my * speed - _velY) * smoothing;
    playerX += _velX * dt;
    playerY += _velY * dt;

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

    double? targetX = _aimX;
    double? targetY = _aimY;

    if (aimAssist && targetX == null) {
      final enemy = _nearestEnemy();
      if (enemy != null) {
        targetX = enemy.x;
        targetY = enemy.y;
      }
    }
    if (targetX == null || targetY == null) return;
    if (_fireCooldown > 0) return;

    final dx = targetX - playerX;
    final dy = targetY - playerY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1) return;

    _fireCooldown = fireInterval;
    final speed = 640 * scale;
    bullets.add(
      Bullet(
        x: playerX,
        y: playerY,
        vx: dx / distance * speed,
        vy: dy / distance * speed,
        radius: 8 * scale,
        fromPlayer: true,
        color: 0xFFFFD700,
      ),
    );
    _emitEvent(GameEvent(GameEventType.shot, x: playerX, y: playerY));
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

  void _updateSpawning(double dt) {
    spawnTimer += dt;
    final interval = math.max(0.55, 1.9 - 0.15 * realmIndex);
    if (spawnTimer < interval) return;
    spawnTimer = 0;
    if (enemies.length >= math.min(30, 10 + 3 * realmIndex)) return;
    spawnEnemy();
  }

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

    final difficulty = 1 + 0.16 * realmIndex;
    final int hp;
    final double radius;
    final double speed;
    switch (type) {
      case EnemyType.wraith:
        hp = 6;
        radius = 26 * scale;
        speed = 70 * scale * difficulty;
      case EnemyType.shooter:
        hp = 2;
        radius = 17 * scale;
        speed = 85 * scale * difficulty;
      case EnemyType.fast:
        hp = 1;
        radius = 14 * scale;
        speed = 175 * scale * difficulty;
      case EnemyType.basic:
        hp = 1;
        radius = 17 * scale;
        speed = 105 * scale * difficulty;
    }

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
      ),
    );
  }

  EnemyType _rollEnemyType() {
    final roll = _random.nextDouble();
    final wraithChance = realmIndex >= 2 ? 0.08 + 0.035 * realmIndex : 0.0;
    if (roll < wraithChance) return EnemyType.wraith;
    if (roll < wraithChance + 0.30) return EnemyType.shooter;
    if (roll < wraithChance + 0.55) return EnemyType.fast;
    return EnemyType.basic;
  }

  void _updateEnemies(double dt) {
    final mult = worldMultiplier;
    final margin = 90.0 * scale;

    for (var i = enemies.length - 1; i >= 0; i--) {
      final enemy = enemies[i];
      enemy.life += dt;

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
        final wobble = math.sin(elapsed * 2 + enemy.wobbleSeed) * 0.35;
        final angle = math.atan2(dy, dx) + wobble;
        enemy.x += math.cos(angle) * enemy.speed * mult * dt;
        enemy.y += math.sin(angle) * enemy.speed * mult * dt;
      }

      if (enemy.type == EnemyType.shooter) {
        enemy.shootTimer += dt;
        final interval = math.max(0.9, 2.2 - 0.15 * realmIndex);
        if (enemy.shootTimer >= interval) {
          enemy.shootTimer = 0;
          _enemyShoot(enemy, distance);
        }
      }

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

  void _enemyShoot(Enemy enemy, double distance) {
    if (distance < 0.001) return;
    final dx = playerX - enemy.x;
    final dy = playerY - enemy.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.001) return;
    final speed = 320 * scale;
    bullets.add(
      Bullet(
        x: enemy.x,
        y: enemy.y,
        vx: dx / d * speed,
        vy: dy / d * speed,
        radius: 6 * scale,
        fromPlayer: false,
        color: 0xFFFF3366,
      ),
    );
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

  void _updateParticles(double dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      final drag = math.pow(0.12, dt).toDouble();
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
