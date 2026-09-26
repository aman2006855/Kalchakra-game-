import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/engine.dart';
import 'game/renderer.dart';
import 'game/storage.dart';
import 'ui/game_over_screen.dart';
import 'ui/game_screen.dart';
import 'ui/menu_screen.dart';
import 'ui/title_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const KalchakraApp());
}

/// Kalchakra — The Time Weaver's Paradox.
class KalchakraApp extends StatefulWidget {
  const KalchakraApp({super.key, this.store, this.audio});

  /// Injected in tests; the app uses `shared_preferences` when null.
  final SaveStore? store;
  final AudioService? audio;

  @override
  State<KalchakraApp> createState() => _KalchakraAppState();
}

enum _Stage { title, menu, game, gameOver }

class _KalchakraAppState extends State<KalchakraApp> {
  SaveStore? _store;
  AudioService? _audio;
  SaveData _save = const SaveData();
  _Stage _stage = _Stage.title;
  final GameEngine _engine = GameEngine();

  int _startRealm = 0;
  double _multiplier = 1;
  bool _ready = false;

  // Last run summary for the game over screen.
  int _lastScore = 0;
  int _lastCombo = 1;
  int _lastRealm = 1;
  int _lastKills = 0;
  bool _lastCompleted = false;
  bool _isNewRecord = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    SaveStore store;
    if (widget.store != null) {
      store = widget.store!;
    } else {
      try {
        store = await PrefsSaveStore.open();
      } catch (_) {
        // Storage unavailable (rare): keep progress for this session only.
        store = MemorySaveStore();
      }
    }

    final AudioService audio = widget.audio ?? SynthAudioService();
    final data = store.read();
    audio.enabled = data.soundEnabled;

    if (!mounted) return;
    setState(() {
      _store = store;
      _audio = audio;
      _save = data;
      _ready = true;
    });
  }

  Future<void> _persist(SaveData next) async {
    setState(() => _save = next);
    final store = _store;
    if (store != null) {
      await store.write(next);
    }
    final audio = _audio;
    if (audio != null) {
      audio.enabled = next.soundEnabled;
    }
  }

  void _startRun({required int startRealm, required double multiplier}) {
    _startRealm = startRealm;
    _multiplier = multiplier;
    _isNewRecord = false;
    _engine.startRun(startRealmIndex: startRealm, multiplier: multiplier);
    setState(() => _stage = _Stage.game);
    unawaited(_audio?.playMenu());
  }

  Future<void> _finishRun(GameEngine engine) async {
    final previousBest = _save.bestScore;
    final next = recordRun(
      _save,
      score: engine.score,
      maxCombo: engine.maxCombo,
      realmReached: engine.realmIndex,
      kills: engine.kills,
      completed: engine.completedRun,
    );
    _lastScore = engine.score;
    _lastCombo = engine.maxCombo;
    _lastRealm = engine.realmNumber;
    _lastKills = engine.kills;
    _lastCompleted = engine.completedRun;
    _isNewRecord = engine.score > previousBest;
    await _persist(next);
    if (mounted) setState(() => _stage = _Stage.gameOver);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kalchakra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: KalchakraColors.voidBlack,
        colorScheme: const ColorScheme.dark(
          primary: KalchakraColors.gold,
          secondary: KalchakraColors.energyCyan,
          surface: KalchakraColors.cosmic,
        ),
        fontFamily: 'Roboto',
      ),
      // The HUD and menus are hand laid out for a phone in portrait, so the
      // system font size is clamped. Without this a device set to "largest"
      // pushes every stat row off the side of the screen.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _ready ? _buildStage() : const _SplashScreen(),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.title:
        return TitleScreen(
          onStart: () {
            unawaited(_audio?.playMenu());
            setState(() => _stage = _Stage.menu);
          },
        );
      case _Stage.menu:
        return MenuScreen(
          save: _save,
          onPlay: ({required int startRealm, required double multiplier}) =>
              _startRun(startRealm: startRealm, multiplier: multiplier),
          onContinue:
              ({required int startRealm, required double multiplier}) =>
                  _startRun(startRealm: startRealm, multiplier: multiplier),
          onSettingsChanged: (next) => unawaited(_persist(next)),
        );
      case _Stage.game:
      case _Stage.gameOver:
        return Stack(
          children: <Widget>[
            GameScreen(
              engine: _engine,
              audio: _audio ?? SilentAudioService(),
              aimAssist: true,
              haptics: _save.hapticsEnabled,
              onRunFinished: (engine) => unawaited(_finishRun(engine)),
              onQuit: () {
                _engine.quitToMenu();
                setState(() => _stage = _Stage.menu);
              },
            ),
            if (_stage == _Stage.gameOver)
              Positioned.fill(
                child: GameOverScreen(
                  score: _lastScore,
                  combo: _lastCombo,
                  realm: _lastRealm,
                  kills: _lastKills,
                  completed: _lastCompleted,
                  newRecord: _isNewRecord,
                  best: _save.bestScore,
                  onRetry: () => _startRun(
                    startRealm: _startRealm,
                    multiplier: _multiplier,
                  ),
                  onMenu: () {
                    _engine.quitToMenu();
                    setState(() => _stage = _Stage.menu);
                  },
                ),
              ),
          ],
        );
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: KalchakraColors.voidBlack,
      body: Center(
        child: CircularProgressIndicator(color: KalchakraColors.gold),
      ),
    );
  }
}
