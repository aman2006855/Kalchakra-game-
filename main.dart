import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() {
  runApp(const KaalChakraGame());
}

class KaalChakraGame extends StatelessWidget {
  const KaalChakraGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'कालचक्र गेम',
      theme: ThemeData(
        primarySwatch: Colors.red,
        fontFamily: 'Devanagari',
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _Game_screenState();
}

class _Game_screenState extends State<GameScreen> {
  int playerPosition = 0;
  int computerPosition = 0;
  int diceValue = 1;
  String currentPlayer = 'player';
  int stepsToWin = 60;
  bool gameStarted = false;
  String message = 'खेल शुरू करने के लिए बटन दबाएं';

  void rollDice() {
    setState(() {
      diceValue = math.Random().nextInt(6) + 1;
    });
  }

  void movePlayer() {
    if (playerPosition + diceValue <= stepsToWin) {
      setState(() {
        playerPosition += diceValue;
      });
      checkWinner('आप जीत गए! 🎉');
      Future.delayed(const Duration(seconds: 1), rollDice);
    } else {
      setState(() {
        message = 'केवल ${stepsToWin - playerPosition} कदम बचे हैं!';
      });
    }
  }

  void moveComputer() {
    setState(() {
      diceValue = math.Random().nextInt(6) + 1;
      computerPosition += diceValue;
    });
    checkWinner('कम्प्यूटर जीत गया! 😢');
    Future.delayed(const Duration(seconds: 1), switchTurn);
  }

  void switchTurn() {
    setState(() {
      if (currentPlayer == 'player') {
        currentPlayer = 'computer';
        message = 'कम्प्यूटर का टर है...';
        Future.delayed(const Duration(seconds: 1), moveComputer);
      } else {
        currentPlayer = 'player';
        message = 'आपका टर है! 🔴';
      }
      gameStarted = true;
    });
  }

  void checkWinner(String winMessage) {
    if (playerPosition >= stepsToWin || computerPosition >= stepsToWin) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('गेम ओवर!'),
          content: Text(winMessage),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  playerPosition = 0;
                  computerPosition = 0;
                  gameStarted = false;
                  currentPlayer = 'player';
                  message = 'खेल रीस्टार्ट करें';
                });
              },
              child: const Text('रीस्टार्ट'),
            ),
          ],
        ),
      );
    }
  }

  void startGame() {
    setState(() {
      gameStarted = true;
      switchTurn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('कालचक्र गेम'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red, Colors.orange],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Game Board - Spiral Track
              SizedBox(
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Track
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: CustomPaint(
                        painter: TrackPainter(),
                      ),
                    ),
                    // Player position (red)
                    if (gameStarted)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                      ),
                    // Computer position (blue)
                    if (gameStarted)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.computer, color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
              // Positions display
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text('आप', style: TextStyle(color: Colors.white, fontSize: 20)),
                      Text('$playerPosition/$stepsToWin', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('कम्प्यूटर', style: TextStyle(color: Colors.white, fontSize: 20)),
                      Text('$computerPosition/$stepsToWin', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ],
              ),
              // Dice display
              if (gameStarted)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text('डाइस', style: TextStyle(fontSize: 18)),
                      Text('$diceValue', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              // Message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              // Control buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!gameStarted)
                      ElevatedButton(
                        onPressed: startGame,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        ),
                        child: const Text('शुरू करें', style: TextStyle(fontSize: 18)),
                      ),
                    if (gameStarted && currentPlayer == 'player' && playerPosition < stepsToWin)
                      ElevatedButton(
                        onPressed: () {
                          rollDice();
                          Future.delayed(const Duration(milliseconds: 500), movePlayer);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        ),
                        child: const Icon(Icons.casino, size: 30),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    
    // Draw 60 numbered positions
    for (int i = 0; i < 60; i++) {
      final angle = (i * 60 * 3.14159 / 180) - 3.14159 / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      
      canvas.drawCircle(Offset(x, y), 5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}