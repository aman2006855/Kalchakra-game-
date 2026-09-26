import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaal_chakra_game/game/audio.dart';
import 'package:kaal_chakra_game/game/storage.dart';
import 'package:kaal_chakra_game/main.dart';

void main() {
  testWidgets('title -> menu -> game -> pause -> resume works',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      KalchakraApp(
        store: MemorySaveStore(),
        audio: SilentAudioService(),
      ),
    );
    await tester.pump();

    // Title screen.
    expect(find.text('KALCHAKRA'), findsOneWidget);
    expect(find.text('WEAVE TIME'), findsOneWidget);

    // Into the menu.
    await tester.tap(find.text('WEAVE TIME'));
    await tester.pump();
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('SCORES'), findsOneWidget);
    expect(find.text('LORE'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);

    // Start a run.
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    // HUD is live: score, health threads, powers and the pause button.
    expect(find.byKey(const Key('score')), findsOneWidget);
    expect(find.byKey(const Key('power-freeze')), findsOneWidget);
    expect(find.byKey(const Key('power-rewind')), findsOneWidget);
    expect(find.byKey(const Key('power-fast')), findsOneWidget);
    expect(find.byKey(const Key('pause-button')), findsOneWidget);

    // The realm intro is showing at the start of a run.
    expect(find.text('SATYA LOKA'), findsWidgets);

    // Let the realm intro finish so the run is live. Small steps mimic real
    // frames — one giant pump would be clamped by the engine's delta guard.
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Pause overlay.
    await tester.tap(find.byKey(const Key('pause-button')));
    await tester.pump();
    expect(find.text('TIME FROZEN'), findsOneWidget);
    expect(find.byKey(const Key('resume')), findsOneWidget);

    // Resume and restart.
    await tester.tap(find.byKey(const Key('resume')));
    await tester.pump();
    expect(find.text('TIME FROZEN'), findsNothing);

    await tester.tap(find.byKey(const Key('pause-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('restart')));
    await tester.pump();
    expect(find.text('TIME FROZEN'), findsNothing);
    expect(find.byKey(const Key('score')), findsOneWidget);
  });

  testWidgets('menu can start a run from a saved realm',
      (WidgetTester tester) async {
    final store = MemorySaveStore(
      const SaveData(unlockedRealm: 4, bestScore: 4242),
    );

    await tester.pumpWidget(
      KalchakraApp(store: store, audio: SilentAudioService()),
    );
    await tester.pump();

    await tester.tap(find.text('WEAVE TIME'));
    await tester.pump();

    // Continue is available because a realm was unlocked previously.
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.textContaining('BHUMI LOKA'), findsOneWidget);

    await tester.tap(find.text('CONTINUE'));
    await tester.pump();

    expect(find.text('BHUMI LOKA'), findsWidgets);
    expect(find.byKey(const Key('score')), findsOneWidget);
  });
}
