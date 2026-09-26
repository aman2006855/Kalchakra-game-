import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const KaalChakraGame());
}

class KaalChakraGame extends StatelessWidget {
  const KaalChakraGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'कालचक्र गेम',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB71C1C))
            .copyWith(primary: const Color(0xFFB71C1C)),
        scaffoldBackgroundColor: const Color(0xFFFDF3E7),
        fontFamily: 'Roboto',
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const int _stepsToWin = 60;
  static const int _trackSegments = _stepsToWin;
  static const List<Color> _chakraColors = [
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFFF9A825),
    Color(0xFF2E7D32),
    Color(0xFF1A237E),
    Color(0xFF4A148C),
  ];

  final math.Random _random = math.Random();

  int playerPosition = 0;
  int computerPosition = 0;
  int diceValue = 1;
  String currentPlayer = 'player';
  bool gameStarted = false;
  bool diceRolling = false;
  String message = 'खेल शुरू करने के लिए बटन दबाएं';
  AnimationController? _diceController;

  @override
  void dispose() {
    _diceController?.dispose();
    super.dispose();
  }

  // ---------- Game logic ----------

  void rollDice() {
    if (!gameStarted ||
        diceRolling ||
        currentPlayer != 'player' ||
        playerPosition >= _stepsToWin) {
      return;
    }
    setState(() => diceRolling = true);
    _animateDice(whenDone: _movePlayer);
  }

  void _animateDice({required VoidCallback whenDone}) {
    // Ek hi ticker reuse karte hain (SingleTickerProviderStateMixin ki requirement).
    final controller = _diceController ??= AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    int tick = 0;
    void reroll() {
      if (tick++ < 8 && controller.status != AnimationStatus.dismissed) {
        setState(() => diceValue = _random.nextInt(6) + 1);
        controller.forward(from: 0).whenComplete(reroll);
      } else {
        setState(() {
          diceValue = _random.nextInt(6) + 1;
          diceRolling = false;
        });
        whenDone();
      }
    }

    setState(() => diceValue = _random.nextInt(6) + 1);
    controller.forward().whenComplete(reroll);
  }

  void _movePlayer() {
    final next = playerPosition + diceValue;
    setState(() {
      if (next <= _stepsToWin) {
        playerPosition = next;
        message = 'आप $diceValue कदम आगे बढ़े!';
      } else {
        message = 'जीतने के लिए ${_stepsToWin - playerPosition} कदम बचे हैं!';
      }
    });
    Future.delayed(
      const Duration(milliseconds: 900),
      playerPosition >= _stepsToWin ? _finishGame : _passTurnToComputer,
    );
  }

  void _passTurnToComputer() {
    if (!gameStarted || mounted == false) return;
    setState(() {
      currentPlayer = 'computer';
      message = 'कम्प्यूटर का टर्न है...';
    });
    Future.delayed(const Duration(milliseconds: 900), _moveComputer);
  }

  void _moveComputer() {
    if (!gameStarted || mounted == false) return;
    final next = computerPosition + diceValue;
    setState(() {
      if (next <= _stepsToWin) {
        computerPosition = next;
        message = 'कम्प्यूटर $diceValue कदम आगे बढ़ा!';
      } else {
        message =
            'कम्प्यूटर को ${_stepsToWin - computerPosition} कदम और चाहिए!';
      }
    });
    Future.delayed(
      const Duration(milliseconds: 900),
      computerPosition >= _stepsToWin ? _finishGame : _passTurnToPlayer,
    );
  }

  void _passTurnToPlayer() {
    if (!gameStarted || mounted == false) return;
    setState(() {
      currentPlayer = 'player';
      message = 'आपका टर्न है! 🔴';
    });
  }

  void _finishGame() {
    if (mounted == false) return;
    final playerWon = playerPosition >= _stepsToWin;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('गेम ओवर!'),
        content: Text(
          playerWon ? 'आप जीत गए! 🎉' : 'कम्प्यूटर जीत गया! 😢',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _resetGame();
            },
            child: const Text('नया खेल'),
          ),
        ],
      ),
    );
  }

  void _resetGame() {
    setState(() {
      playerPosition = 0;
      computerPosition = 0;
      diceValue = 1;
      currentPlayer = 'player';
      gameStarted = false;
      diceRolling = false;
      message = 'खेल शुरू करने के लिए बटन दबाएं';
    });
  }

  void _startGame() {
    setState(() {
      gameStarted = true;
      currentPlayer = 'player';
      message = 'आपका टर्न है! 🔴';
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('कालचक्र गेम'),
        centerTitle: true,
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFE65100)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.vertical -
                        (Theme.of(context).appBarTheme.toolbarHeight ??
                            kToolbarHeight),
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    const SizedBox(height: 4),
                    _buildBoard(),
                    _buildScores(),
                    _buildDiceCard(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    _buildControls(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return SizedBox(
      width: 290,
      height: 290,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CustomPaint(
              painter: TrackPainter(colors: _chakraColors),
            ),
          ),
          // Player token (red) — travels clockwise from the top.
          if (gameStarted)
            const Positioned(
              top: 10,
              right: 10,
              child: _Token(
                color: Colors.red,
                icon: Icons.person,
                label: 'आप',
              ),
            ),
          // Computer token (blue) — travels counter-clockwise from bottom-left.
          if (gameStarted)
            const Positioned(
              bottom: 10,
              left: 10,
              child: _Token(
                color: Colors.blue,
                icon: Icons.computer,
                label: 'कम्प्यूटर',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScores() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ScoreCard(
            label: 'आप',
            position: playerPosition,
            total: _stepsToWin,
            color: Colors.red,
          ),
          _ScoreCard(
            label: 'कम्प्यूटर',
            position: computerPosition,
            total: _stepsToWin,
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildDiceCard() {
    if (!gameStarted) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            diceRolling ? 'पासा घूम रहा है...' : 'पासा',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '$diceValue',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Color(0xFFB71C1C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!gameStarted)
            ElevatedButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                'शुरू करें',
                style: TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          if (gameStarted &&
              currentPlayer == 'player' &&
              !diceRolling &&
              playerPosition < _stepsToWin)
            ElevatedButton.icon(
              onPressed: rollDice,
              icon: const Icon(Icons.casino, size: 30),
              label: const Text('पासा फेंकें', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9A825),
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
        ],
      ),
    );
  }
}

class _Token extends StatelessWidget {
  const _Token({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.position,
    required this.total,
    required this.color,
  });

  final String label;
  final int position;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$position/$total कदम',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class TrackPainter extends CustomPainter {
  TrackPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const segmentArc = 2 * math.pi / _GameScreenState._trackSegments;

    for (int i = 0; i < _GameScreenState._trackSegments; i++) {
      final color = colors[i % colors.length];
      final startAngle = i * segmentArc - math.pi / 2;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentArc,
        false,
        paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant TrackPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
