import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kaal_chakra_game/game/engine.dart';
import 'package:kaal_chakra_game/game/realms.dart';
import 'package:kaal_chakra_game/game/storage.dart';

/// Runs the engine past the realm intro so it is in the playing phase, then
/// clears the world and lets the fire cooldown expire.
void _skipIntro(GameEngine engine) {
  for (var i = 0; i < 80; i++) {
    engine.update(0.05);
  }
  engine.enemies.clear();
  engine.bullets.clear();
  for (var i = 0; i < 6; i++) {
    engine.update(0.05);
  }
  engine.enemies.clear();
  engine.bullets.clear();
  engine.spawnTimer = 0;
  engine.setStick(0, 0);
}

Enemy _enemyAt(GameEngine engine, double x, double y, {int hp = 1}) {
  final enemy = Enemy(
    x: x,
    y: y,
    type: EnemyType.basic,
    hp: hp,
    radius: 10,
    speed: 0,
    color: 0xFF00FFCC,
  );
  engine.enemies.add(enemy);
  return enemy;
}

void main() {
  group('run flow', () {
    test('starts in the first realm and becomes playable after the intro', () {
      final engine = GameEngine(random: math.Random(1));
      engine.startRun();

      expect(engine.phase, GamePhase.realmTransition);
      expect(engine.realmIndex, 0);
      expect(engine.realm.name, 'SATYA LOKA');
      expect(kRealms.length, 7);

      _skipIntro(engine);
      expect(engine.phase, GamePhase.playing);
      expect(engine.health, GameEngine.maxHealth);
      expect(engine.rewindUses, GameEngine.startingRewindUses);
    });

    test('quitting resets the phase back to idle', () {
      final engine = GameEngine(random: math.Random(2));
      engine.startRun();
      _skipIntro(engine);
      engine.quitToMenu();
      expect(engine.phase, GamePhase.idle);
    });

    test('resuming a paused run keeps the score', () {
      final engine = GameEngine(random: math.Random(3));
      engine.startRun();
      _skipIntro(engine);
      engine.score = 500;
      engine.pause();
      expect(engine.phase, GamePhase.paused);
      engine.update(0.05);
      expect(engine.score, 500, reason: 'paused runs must not simulate');
      engine.resume();
      expect(engine.phase, GamePhase.playing);
    });
  });

  group('combat', () {
    test('firing spawns a bullet aimed at the target', () {
      final engine = GameEngine(random: math.Random(4));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      engine.aimAssist = false;
      engine.setAim(340, 560);
      engine.setFireHeld(true);
      engine.update(0.05);

      expect(engine.bullets, hasLength(1));
      expect(engine.bullets.first.fromPlayer, isTrue);
    });

    test('bullets that hit an enemy score and build combo', () {
      final engine = GameEngine(random: math.Random(5));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      final enemy = _enemyAt(engine, 100, 100);
      engine.bullets.add(
        Bullet(
          x: 100,
          y: 100,
          vx: 0,
          vy: 0,
          radius: 5,
          fromPlayer: true,
          color: 0xFFFFD700,
        ),
      );

      engine.update(0.05);

      expect(engine.enemies.contains(enemy), isFalse);
      expect(engine.kills, 1);
      expect(engine.combo, 2);
      expect(engine.score, greaterThan(0));
    });

    test('wraiths are worth more than basic enemies', () {
      final engine = GameEngine(random: math.Random(6));
      engine.startRun();
      _skipIntro(engine);

      final wraith = Enemy(
        x: 10,
        y: 10,
        type: EnemyType.wraith,
        hp: 1,
        radius: 10,
        speed: 0,
        color: 0xFF00FFCC,
      );
      engine
          ..enemies
          .clear()
          ..enemies.add(wraith)
          ..bullets.add(
            Bullet(
              x: 10,
              y: 10,
              vx: 0,
              vy: 0,
              radius: 5,
              fromPlayer: true,
              color: 0xFFFFD700,
            ),
          )
          ..update(0.05);

      expect(engine.enemies.contains(wraith), isFalse);
      expect(engine.score, greaterThanOrEqualTo(450));
    });

    test('player damage grants brief invulnerability', () {
      final engine = GameEngine(random: math.Random(7));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      final before = engine.health;
      _enemyAt(engine, engine.playerX, engine.playerY);
      engine.update(0.05);
      expect(engine.health, before - 1);
      expect(engine.invincible, isTrue);

      // A second overlapping hit during i-frames must be ignored.
      _enemyAt(engine, engine.playerX, engine.playerY);
      engine.update(0.05);
      expect(engine.health, before - 1);
    });

    test('running out of health ends the run', () {
      final engine = GameEngine(random: math.Random(8));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      for (var i = 0; i < GameEngine.maxHealth; i++) {
        engine
          ..invincible = false
          ..enemies.clear()
          ..enemies.add(
            Enemy(
              x: engine.playerX,
              y: engine.playerY,
              type: EnemyType.basic,
              hp: 99,
              radius: 10,
              speed: 0,
              color: 0xFF00FFCC,
            ),
          )
          ..update(0.05);
      }

      expect(engine.health, 0);
      expect(engine.phase, GamePhase.gameOver);
    });
  });

  group('time powers', () {
    test('freeze costs energy and slows the world', () {
      final engine = GameEngine(random: math.Random(9));
      engine.startRun();
      _skipIntro(engine);
      engine.energy = 100;

      expect(engine.activatePower(TimePower.freeze), isTrue);
      expect(engine.energy, 100 - GameEngine.freezeCost);
      expect(engine.worldMultiplier, 0.3);
    });

    test('powers are refused without energy', () {
      final engine = GameEngine(random: math.Random(10));
      engine.startRun();
      _skipIntro(engine);
      engine.energy = 5;

      expect(engine.activatePower(TimePower.freeze), isFalse);
      expect(engine.activatePower(TimePower.fastForward), isFalse);
    });

    test('fast forward expires on its own', () {
      final engine = GameEngine(random: math.Random(11));
      engine.startRun();
      _skipIntro(engine);
      engine.energy = 100;

      expect(engine.activatePower(TimePower.fastForward), isTrue);
      expect(engine.worldMultiplier, 1.25);
      for (var i = 0; i < 80; i++) {
        engine.update(0.05);
      }
      expect(engine.activePower, isNull);
      expect(engine.worldMultiplier, 1);
    });

    test('rewind consumes a use and restores invulnerability', () {
      final engine = GameEngine(random: math.Random(12));
      engine.startRun();
      _skipIntro(engine);

      expect(engine.activatePower(TimePower.rewind), isTrue);
      expect(engine.rewindUses, GameEngine.startingRewindUses - 1);
      expect(engine.invincible, isTrue);
    });
  });

  group('progression', () {
    test('clearing a realm goal advances to the next realm', () {
      final engine = GameEngine(random: math.Random(13));
      engine.startRun();
      _skipIntro(engine);

      engine
        ..killsInRealm = engine.realmGoal
        ..enemies.clear();
      engine.update(0.05);

      expect(engine.realmIndex, 1);
      expect(engine.realm.name, kRealms[1].name);
      expect(engine.score, greaterThanOrEqualTo(10000));
      expect(engine.phase, GamePhase.realmTransition);
    });

    test('clearing the final realm completes the run', () {
      final engine = GameEngine(random: math.Random(14));
      engine.startRun(startRealmIndex: kRealms.length - 1);
      _skipIntro(engine);

      engine
        ..killsInRealm = engine.realmGoal
        ..enemies.clear();
      engine.update(0.05);

      expect(engine.completedRun, isTrue);
      expect(engine.phase, GamePhase.gameOver);
    });

    test('realm goals get harder deeper in', () {
      expect(kRealms.length, 7);
      final engine = GameEngine(random: math.Random(15));
      engine.startRun();
      final first = engine.realmGoal;
      engine.realmIndex = 5;
      expect(engine.realmGoal, greaterThan(first));
    });
  });

  group('housekeeping', () {
    test('enemies far off screen are recycled', () {
      final engine = GameEngine(random: math.Random(16));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      final stray = _enemyAt(engine, 5000, 5000);
      for (var i = 0; i < 60; i++) {
        engine.update(0.05);
      }
      expect(engine.enemies.contains(stray), isFalse);
    });

    test('combo decays when kills stop coming', () {
      final engine = GameEngine(random: math.Random(17));
      engine.startRun();
      _skipIntro(engine);
      // No auto fire here, otherwise the run would keep scoring new kills.
      engine.aimAssist = false;

      _enemyAt(engine, 100, 100);
      engine.bullets.add(
        Bullet(
          x: 100,
          y: 100,
          vx: 0,
          vy: 0,
          radius: 5,
          fromPlayer: true,
          color: 0xFFFFD700,
        ),
      );
      engine.update(0.05);
      expect(engine.combo, 2);

      for (var i = 0; i < 400; i++) {
        engine.update(0.05);
      }
      expect(engine.combo, 1);
    });

    test('particle count stays capped', () {
      final engine = GameEngine(random: math.Random(18));
      engine.startRun();
      _skipIntro(engine);

      for (var i = 0; i < 40; i++) {
        _enemyAt(engine, 50, 50);
        engine.bullets.add(
          Bullet(
            x: 50,
            y: 50,
            vx: 0,
            vy: 0,
            radius: 5,
            fromPlayer: true,
            color: 0xFFFFD700,
          ),
        );
        engine.update(0.05);
      }
      expect(engine.particles.length, lessThanOrEqualTo(GameEngine.maxParticles));
    });

    test('a huge frame delta cannot break the simulation', () {
      final engine = GameEngine(random: math.Random(19));
      engine.startRun();
      _skipIntro(engine);

      engine.update(12);
      expect(engine.score.isFinite, isTrue);
      expect(engine.playerX.isFinite, isTrue);
      expect(engine.playerY.isFinite, isTrue);
    });
  });

  group('save data', () {
    test('recordRun keeps the top scores and unlocks realms', () {
      var save = const SaveData();
      save = recordRun(
        save,
        score: 1200,
        maxCombo: 5,
        realmReached: 2,
        kills: 40,
        completed: false,
      );
      save = recordRun(
        save,
        score: 300,
        maxCombo: 2,
        realmReached: 1,
        kills: 10,
        completed: false,
      );

      expect(save.highScores.first, 1200);
      expect(save.bestScore, 1200);
      expect(save.bestCombo, 5);
      expect(save.unlockedRealm, 2);
      expect(save.totalRuns, 2);
      expect(save.totalKills, 50);
    });

    test('recordRun never lowers the unlocked realm', () {
      var save = const SaveData();
      save = recordRun(
        save,
        score: 10,
        maxCombo: 1,
        realmReached: 5,
        kills: 5,
        completed: false,
      );
      save = recordRun(
        save,
        score: 1,
        maxCombo: 1,
        realmReached: 0,
        kills: 1,
        completed: false,
      );
      expect(save.unlockedRealm, 5);
    });
  });
}
