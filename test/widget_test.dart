import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaal_chakra_game/main.dart';

void main() {
  testWidgets('game builds, plays out, and shows the winner dialog',
      (WidgetTester tester) async {
    await tester.pumpWidget(const KaalChakraGame());

    // Initial screen: title, both scores at 0, start button visible.
    expect(find.text('कालचक्र गेम'), findsOneWidget);
    expect(find.text('0/60 कदम'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Start the game: the player dice button should appear.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.text('पासा फेंकें'), findsOneWidget);

    // Roll whenever it is the player's turn and let the timers run,
    // until someone reaches 60 and the game-over dialog appears.
    final gameOver = find.text('गेम ओवर!');
    var rolled = false;
    for (var i = 0; i < 2000; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (gameOver.evaluate().isNotEmpty) break;
      final rollButton = find.text('पासा फेंकें');
      if (rollButton.evaluate().isNotEmpty) {
        await tester.tap(rollButton);
        rolled = true;
      }
    }

    expect(rolled, isTrue, reason: 'the player should have rolled the dice');
    expect(gameOver, findsOneWidget);

    // Restart from the dialog: everything resets cleanly.
    await tester.tap(find.text('नया खेल'));
    await tester.pumpAndSettle();

    expect(find.text('0/60 कदम'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
