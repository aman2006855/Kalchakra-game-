import 'package:flutter/material.dart';

import '../game/renderer.dart';
import '../game/realms.dart';

/// The end of run summary.
///
/// Everything is sized from the available box rather than from fixed font sizes,
/// because this screen used to push its stat rows off both edges of a narrow
/// phone once the system font was turned up.
class GameOverScreen extends StatelessWidget {
  const GameOverScreen({
    super.key,
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
      color: KalchakraColors.voidBlack.withValues(alpha: 0.92),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = (constraints.maxWidth / 360).clamp(0.75, 1.15);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          completed ? 'THE WHEEL IS WHOLE' : 'WHEEL SHATTERED',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: KalchakraColors.gold,
                            fontSize: 24 * scale,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      if (newRecord) ...<Widget>[
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '★ NEW RECORD ★',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: KalchakraColors.energyCyan,
                              fontSize: 15 * scale,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 18 * scale),
                      _StatPanel(
                        scale: scale,
                        rows: <_StatRow>[
                          _StatRow('Final score', score.toString()),
                          _StatRow('Realm reached', '$realm / ${kRealms.length}'),
                          _StatRow('Enemies defeated', kills.toString()),
                          _StatRow('Max combo', 'x$combo'),
                          _StatRow('Best ever', best.toString()),
                        ],
                      ),
                      SizedBox(height: 20 * scale),
                      FilledButton(
                        key: const Key('retry'),
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: KalchakraColors.gold,
                          foregroundColor: KalchakraColors.voidBlack,
                          padding: EdgeInsets.symmetric(vertical: 14 * scale),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'THREAD AGAIN',
                            maxLines: 1,
                            style: TextStyle(fontSize: 15 * scale),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const Key('back-to-menu'),
                        onPressed: onMenu,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KalchakraColors.parchment,
                          side: const BorderSide(color: KalchakraColors.parchment),
                          padding: EdgeInsets.symmetric(vertical: 14 * scale),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'MAIN MENU',
                            maxLines: 1,
                            style: TextStyle(fontSize: 15 * scale),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatRow {
  const _StatRow(this.label, this.value);
  final String label;
  final String value;
}

/// The run summary panel. Rows are laid out as a fixed ratio so the label can
/// shrink and ellipsise instead of shoving the value off the screen.
class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.scale, required this.rows});

  final double scale;
  final List<_StatRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        border: Border.all(color: KalchakraColors.gold.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          for (final row in rows) _row(row.label, row.value),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * scale),
      child: Row(
        children: <Widget>[
          Flexible(
            flex: 5,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: KalchakraColors.parchment,
                fontSize: 14 * scale,
              ),
            ),
          ),
          SizedBox(width: 10 * scale),
          Flexible(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: KalchakraColors.gold,
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
