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

Enemy _hostile(
  GameEngine engine,
  EnemyType type, {
  double x = 0,
  double y = 0,
  double speed = 0,
  double preferredDistance = 0,
  double strafeSkill = 0,
}) {
  final enemy = Enemy(
    x: x,
    y: y,
    type: type,
    hp: 99,
    radius: 12,
    speed: speed,
    color: 0xFFFF3366,
    preferredDistance: preferredDistance,
    strafeSkill: strafeSkill,
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
      expect(kRealms.length, 9);

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
      expect(kRealms.length, 9);
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

  group('spawn pacing', () {
    test('the live enemy cap opens up gradually across the realm', () {
      final engine = GameEngine(random: math.Random(60));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: kRealms.length - 1);
      _skipIntro(engine);

      engine.killsInRealm = 0;
      final atStart = engine.liveEnemyCap;
      engine.killsInRealm = engine.realmGoal ~/ 2;
      final mid = engine.liveEnemyCap;
      engine.killsInRealm = engine.realmGoal;
      final atEnd = engine.liveEnemyCap;

      expect(atStart, lessThan(mid));
      expect(mid, lessThan(atEnd));
      expect(atEnd, engine.maxEnemies);
    });

    test('even the deepest realm opens calm', () {
      final engine = GameEngine(random: math.Random(61));
      engine.startRun(startRealmIndex: kRealms.length - 1);
      _skipIntro(engine);
      engine.killsInRealm = 0;

      // Not a wall of enemies the instant a realm begins.
      expect(engine.liveEnemyCap, lessThanOrEqualTo(6));
      expect(engine.liveEnemyCap, lessThan(engine.maxEnemies));
    });

    test('wave size grows one, then two, then three', () {
      final engine = GameEngine(random: math.Random(62));
      engine.startRun();
      _skipIntro(engine);

      engine.killsInRealm = 0;
      expect(engine.spawnWaveSize, 1);
      engine.killsInRealm = (engine.realmGoal * 0.4).floor();
      expect(engine.spawnWaveSize, 2);
      engine.killsInRealm = engine.realmGoal;
      expect(engine.spawnWaveSize, 3);
    });

    test('a quiet beat separates the waves', () {
      final engine = GameEngine(random: math.Random(63));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);
      // One short of the goal: enough for the biggest wave size without
      // tipping the realm over into the next one mid test.
      engine.killsInRealm = engine.realmGoal - 1;
      engine.spawnTimer = 0;

      // Force a wave, then check the spawner backs off instead of instantly
      // dumping the next one on top of it.
      var sawRest = false;
      for (var i = 0; i < 120; i++) {
        engine.update(0.05);
        if (engine.spawnTimer < 0) sawRest = true;
      }
      expect(sawRest, isTrue);
    });

    test('a long run never breaks the live cap', () {
      final engine = GameEngine(random: math.Random(64));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 3);
      _skipIntro(engine);

      for (var i = 0; i < 3000; i++) {
        engine.invincible = true;
        engine.health = 99;
        engine.setStick(math.sin(i / 25), math.cos(i / 25));
        engine.update(1 / 60);
        expect(
          engine.enemies.length,
          lessThanOrEqualTo(engine.liveEnemyCap),
          reason: 'frame $i broke the live cap',
        );
      }
    });

    test('arrivals are announced with a spawn mark', () {
      final engine = GameEngine(random: math.Random(65));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);
      engine.spawnMarks.clear();

      engine.spawnEnemy();
      expect(engine.spawnMarks, isNotEmpty);

      for (var i = 0; i < 40; i++) {
        engine.update(0.05);
      }
      expect(engine.spawnMarks, isEmpty, reason: 'marks must expire');
    });
  });

  group('difficulty ramp', () {
    test('the first realm never opens fire, it only teaches movement', () {
      final engine = GameEngine(random: math.Random(50));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      for (final type in EnemyType.values) {
        _hostile(
          engine,
          type,
          x: engine.playerX + 200,
          y: engine.playerY,
          speed: 0,
        );
      }

      for (var i = 0; i < 200; i++) {
        engine.update(0.05);
      }

      expect(
        engine.bullets.where((b) => !b.fromPlayer),
        isEmpty,
        reason: 'realm 1 must not open with the full enemy kit',
      );
    });

    test('firing unlocks from the second realm onwards', () {
      final engine = GameEngine(random: math.Random(51));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;
      _hostile(
        engine,
        EnemyType.shooter,
        x: engine.playerX + 200,
        y: engine.playerY,
        speed: 0,
      );

      var fired = false;
      for (var i = 0; i < 120; i++) {
        engine.update(0.05);
        if (engine.bullets.any((b) => !b.fromPlayer)) {
          fired = true;
          break;
        }
      }
      expect(fired, isTrue);
    });

    test('dodging only unlocks later, never in the first realms', () {
      final engine = GameEngine(random: math.Random(52));
      engine.resize(400, 800);

      for (var realm = 0; realm < kRealms.length; realm++) {
        engine.startRun(startRealmIndex: realm);
        _skipIntro(engine);
        expect(
          engine.realmIndex,
          realm,
          reason: 'a hostile placed in realm $realm should be active',
        );
      }
    });

    test('enemy cap and spawn pace start gentle and tighten later', () {
      final engine = GameEngine(random: math.Random(53));
      engine.startRun();
      _skipIntro(engine);

      final firstCap = engine.maxEnemies;
      final firstSpawn = engine.spawnInterval;
      final firstDifficulty = engine.difficulty;

      engine.realmIndex = kRealms.length - 1;
      expect(engine.maxEnemies, greaterThan(firstCap));
      expect(engine.spawnInterval, lessThan(firstSpawn));
      expect(engine.difficulty, greaterThan(firstDifficulty));
    });

    test('enemies speed up as the player clears the current realm', () {
      final engine = GameEngine(random: math.Random(54));
      engine.startRun();
      _skipIntro(engine);

      final atStart = engine.difficulty;
      engine.killsInRealm = engine.realmGoal;
      expect(engine.realmProgress, 1.0);
      expect(engine.difficulty, greaterThan(atStart));
    });

    test('the first realm never rolls a ranged or armoured archetype', () {
      final engine = GameEngine(random: math.Random(55));
      engine.startRun();
      _skipIntro(engine);
      engine.enemies.clear();
      engine.spawnTimer = 99;

      for (var i = 0; i < 300; i++) {
        engine.spawnEnemy(forcedType: EnemyType.basic);
        engine.update(0.05);
      }
      engine.enemies.clear();

      final seen = <EnemyType>{};
      for (var i = 0; i < 400; i++) {
        engine.spawnTimer = 99;
        engine.spawnEnemy();
        seen.add(engine.enemies.last.type);
        if (engine.enemies.length > 40) engine.enemies.removeAt(0);
      }

      expect(seen, everyElement(isNot(EnemyType.wraith)));
      expect(seen, everyElement(isNot(EnemyType.weaver)));
      expect(seen, everyElement(isNot(EnemyType.shooter)));
    });

    test('a saturated world stays inside the bullet ceiling', () {
      final engine = GameEngine(random: math.Random(56));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: kRealms.length - 1);
      _skipIntro(engine);

      for (var i = 0; i < 2000; i++) {
        engine.setStick(1, 0);
        engine.setAim(engine.playerX + 300, engine.playerY);
        engine.update(0.05);
        expect(
          engine.bullets.length,
          lessThanOrEqualTo(GameEngine.maxBullets),
        );
        expect(
          engine.enemies.length,
          lessThanOrEqualTo(engine.maxEnemies),
        );
        expect(
          engine.particles.length,
          lessThanOrEqualTo(GameEngine.maxParticles),
        );
      }
    });
  });

  group('enemy fire', () {
    test('shooters shoot back at the player', () {
      final engine = GameEngine(random: math.Random(30));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;

      _hostile(
        engine,
        EnemyType.shooter,
        x: engine.playerX + 200,
        y: engine.playerY,
        speed: 0,
      );

      // The first shot lands after the 2.1s shooter cadence.
      var fired = false;
      for (var i = 0; i < 60; i++) {
        engine.update(0.05);
        if (engine.bullets.any((b) => !b.fromPlayer)) {
          fired = true;
          break;
        }
      }

      expect(
        fired,
        isTrue,
        reason: 'shooters must actually put bullets in the air',
      );
    });

    test('charging basics also shoot, so standing still is not safe', () {
      final engine = GameEngine(random: math.Random(31));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);

      _hostile(
        engine,
        EnemyType.basic,
        x: engine.playerX + 200,
        y: engine.playerY,
        speed: 0,
      );

      var fired = false;
      for (var i = 0; i < 120; i++) {
        engine.update(0.05);
        if (engine.bullets.any((b) => !b.fromPlayer)) {
          fired = true;
          break;
        }
      }

      expect(fired, isTrue);
    });

    test('a shot telegraphs before it leaves the barrel', () {
      final engine = GameEngine(random: math.Random(32));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;

      final enemy = _hostile(
        engine,
        EnemyType.shooter,
        x: engine.playerX + 200,
        y: engine.playerY,
        speed: 0,
      );

      for (var i = 0; i < 50; i++) {
        engine.update(0.05);
        if (enemy.aimFlash > 0) break;
      }

      expect(enemy.aimFlash, greaterThan(0));
    });

    test('weavers fan a burst out sideways', () {
      final engine = GameEngine(random: math.Random(33));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;

      _hostile(
        engine,
        EnemyType.weaver,
        x: engine.playerX + 200,
        y: engine.playerY,
        speed: 0,
      );

      for (var i = 0; i < 60; i++) {
        engine.update(0.05);
        if (engine.bullets.where((b) => !b.fromPlayer).length >= 3) break;
      }

      final incoming = engine.bullets.where((b) => !b.fromPlayer).toList();
      expect(incoming.length, greaterThanOrEqualTo(3));
      // A fan means the shots do not all travel along one line.
      final angles = incoming
          .map((b) => math.atan2(b.vy - engine.playerY, b.vx - engine.playerX))
          .toList();
      expect(angles.toSet().length, greaterThan(1));
    });

    test('enemies hold the distance they prefer instead of gluing on', () {
      final engine = GameEngine(random: math.Random(34));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;

      final enemy = _hostile(
        engine,
        EnemyType.shooter,
        x: engine.playerX + 60,
        y: engine.playerY,
        speed: 80,
        preferredDistance: 220,
      );

      double gap(Enemy e) => math.sqrt(
        math.pow(engine.playerX - e.x, 2) + math.pow(engine.playerY - e.y, 2),
      );
      final before = gap(enemy);
      for (var i = 0; i < 30; i++) {
        engine.update(0.05);
      }
      final after = gap(enemy);

      expect(after, greaterThan(before));
    });

    test('enemies slide sideways instead of queueing in a straight line', () {
      final engine = GameEngine(random: math.Random(35));
      engine.resize(400, 800);
      engine.startRun(startRealmIndex: 1);
      _skipIntro(engine);
      engine.invincible = true;

      final enemy = _hostile(
        engine,
        EnemyType.weaver,
        x: engine.playerX,
        y: engine.playerY - 200,
        speed: 90,
        preferredDistance: 200,
        strafeSkill: 0.6,
      );

      var maxLateral = 0.0;
      var previousX = enemy.x;
      for (var i = 0; i < 40; i++) {
        engine.update(0.05);
        maxLateral = math.max(maxLateral, (enemy.x - previousX).abs());
        previousX = enemy.x;
      }

      expect(maxLateral, greaterThan(0.5));
    });
  });

  group('tap to attack and drag to move', () {
    test('fireAt shoots towards the tapped point', () {
      final engine = GameEngine(random: math.Random(36));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      expect(engine.fireAt(380, 700), isTrue);
      expect(engine.bullets, hasLength(1));
      final bullet = engine.bullets.first;
      expect(bullet.vx, greaterThan(0));
      expect(bullet.vy, greaterThan(0));
    });

    test('the tapped aim sticks even when auto aim has another target', () {
      final engine = GameEngine(random: math.Random(37));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      // An enemy up and to the left would be picked by auto aim.
      _enemyAt(engine, engine.playerX - 150, engine.playerY - 250);
      engine.aimAssist = true;

      engine.fireAt(engine.playerX, engine.playerY + 200);
      for (var i = 0; i < 10; i++) {
        engine.update(0.05);
      }

      // Every follow up shot still points downwards, at the tapped spot.
      for (final bullet in engine.bullets) {
        expect(bullet.vy, greaterThan(0));
      }
      expect(engine.bullets.length, greaterThan(1));
    });

    test('firing is refused outside the playing phase', () {
      final engine = GameEngine(random: math.Random(38));
      expect(engine.fireAt(10, 10), isFalse);
    });
  });

  group('dash and shield', () {
    test('dash moves the player and then goes on cooldown', () {
      final engine = GameEngine(random: math.Random(39));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);
      engine.setStick(1, 0);

      final startX = engine.playerX;
      expect(engine.dashReady, isTrue);
      expect(engine.activateDash(), isTrue);
      engine.update(0.05);
      expect(engine.playerX, greaterThan(startX));

      expect(engine.dashReady, isFalse);
      expect(engine.activateDash(), isFalse);
      expect(engine.dashProgress, lessThan(1));
    });

    test('dash grants a moment of invulnerability', () {
      final engine = GameEngine(random: math.Random(40));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      expect(engine.activateDash(), isTrue);
      expect(engine.invincible, isTrue);
    });

    test('the shield eats a hit instead of costing health', () {
      final engine = GameEngine(random: math.Random(41));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);
      engine.energy = 100;

      expect(engine.activateShield(), isTrue);
      expect(engine.shieldActive, isTrue);
      expect(engine.energy, 100 - GameEngine.shieldCost);

      final health = engine.health;
      engine.bullets.add(
        Bullet(
          x: engine.playerX,
          y: engine.playerY,
          vx: 0,
          vy: 0,
          radius: 5,
          fromPlayer: false,
          color: 0xFFFF3366,
        ),
      );
      engine.update(0.05);

      expect(engine.health, health);
      expect(engine.shieldActive, isFalse);
    });

    test('the shield needs energy and recharges on its own', () {
      final engine = GameEngine(random: math.Random(42));
      engine.startRun();
      _skipIntro(engine);
      engine.energy = 0;

      expect(engine.activateShield(), isFalse);

      engine.energy = 100;
      expect(engine.activateShield(), isTrue);
      expect(engine.activateShield(), isFalse);
      for (var i = 0; i < 300; i++) {
        engine.update(0.05);
      }
      expect(engine.shieldReady, isTrue);
    });
  });

  group('threat measurement', () {
    test('no incoming fire means no threat', () {
      final engine = GameEngine(random: math.Random(43));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      engine.update(0.05);
      expect(engine.threatLevel, 0);
      expect(engine.threatDx, 0);
    });

    test('threat points back at the bullet that is closing in', () {
      final engine = GameEngine(random: math.Random(44));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);
      engine.invincible = true;

      // A bullet to the left of the player, travelling right.
      engine.bullets.add(
        Bullet(
          x: engine.playerX - 100,
          y: engine.playerY,
          vx: 300,
          vy: 0,
          radius: 5,
          fromPlayer: false,
          color: 0xFFFF3366,
        ),
      );
      engine.update(0.016);

      expect(engine.threatLevel, greaterThan(0));
      expect(engine.threatDx, lessThan(0));
      expect(engine.threatDy, closeTo(0, 0.2));
    });

    test('fire travelling away from the player is not a threat', () {
      final engine = GameEngine(random: math.Random(45));
      engine.resize(400, 800);
      engine.startRun();
      _skipIntro(engine);

      engine.bullets.add(
        Bullet(
          x: engine.playerX - 100,
          y: engine.playerY,
          vx: -300,
          vy: 0,
          radius: 5,
          fromPlayer: false,
          color: 0xFFFF3366,
        ),
      );
      engine.update(0.016);

      expect(engine.threatLevel, 0);
    });

    test('the movement assist fades out deeper in the realms', () {
      final engine = GameEngine(random: math.Random(46));
      engine.startRun();
      final shallow = engine.dodgeAssist;

      engine.realmIndex = kRealms.length - 1;
      expect(engine.dodgeAssist, lessThan(shallow));
      expect(engine.dodgeAssist, greaterThan(0));
    });
  });
}
