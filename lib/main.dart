import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/engine.dart';
import 'game/realms.dart';
import 'game/renderer.dart';
import 'game/storage.dart';
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
                child: _GameOverScreen(
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

class _GameOverScreen extends StatelessWidget {
  const _GameOverScreen({
    required this.score,
    required this.combo,
    required this.realm,
    required this.kills,
    required this.completed,
    required this.newRecord,
    required this.best,
    required this.onRetry,
    required this.onMenu,
  });

  final int score;
  final int combo;
  final int realm;
  final int kills;
  final bool completed;
  final bool newRecord;
  final int best;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KalchakraColors.voidBlack.withValues(alpha: 0.9),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                completed ? 'THE WHEEL IS WHOLE' : 'WHEEL SHATTERED',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KalchakraColors.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              if (newRecord) ...<Widget>[
                const SizedBox(height: 8),
                const Text(
                  '★ NEW RECORD ★',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: KalchakraColors.energyCyan,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _row('Final score', score.toString()),
              _row('Realm reached', '$realm / ${kRealms.length}'),
              _row('Enemies defeated', kills.toString()),
              _row('Max combo', 'x$combo'),
              _row('Best ever', best.toString()),
              const SizedBox(height: 26),
              FilledButton(
                key: const Key('retry'),
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: KalchakraColors.gold,
                  foregroundColor: KalchakraColors.voidBlack,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('THREAD AGAIN'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('back-to-menu'),
                onPressed: onMenu,
                style: OutlinedButton.styleFrom(
                  foregroundColor: KalchakraColors.parchment,
                  side: const BorderSide(color: KalchakraColors.parchment),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('MAIN MENU'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: KalchakraColors.parchment),
          ),
          Text(
            value,
            style: const TextStyle(
              color: KalchakraColors.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
