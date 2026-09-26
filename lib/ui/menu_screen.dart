import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/realms.dart';
import '../game/renderer.dart';
import '../game/storage.dart';

/// Main menu presented as a rotating wheel of options.
class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    required this.save,
    required this.onPlay,
    required this.onContinue,
    required this.onSettingsChanged,
  });

  final SaveData save;
  final void Function({required int startRealm, required double multiplier}) onPlay;
  final void Function({required int startRealm, required double multiplier})
      onContinue;
  final void Function(SaveData save) onSettingsChanged;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  int get _unlockedRealm => widget.save.unlockedRealm;

  double get _continueMultiplier => 1 + 0.5 * _unlockedRealm;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _playFrom(int realm) {
    widget.onPlay(
      startRealm: realm,
      multiplier: 1 + 0.5 * realm,
    );
  }

  Future<void> _showScores() async {
    final scores = widget.save.highScores;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KalchakraColors.cosmic,
        title: const Text(
          'HIGH SCORES',
          style: TextStyle(color: KalchakraColors.gold),
        ),
        content: SizedBox(
          width: 260,
          child: scores.isEmpty
              ? const Text(
                  'No runs recorded yet. Weave your first thread!',
                  style: TextStyle(color: KalchakraColors.parchment),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < scores.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              '${i + 1}.',
                              style: const TextStyle(
                                color: KalchakraColors.energyCyan,
                              ),
                            ),
                            Text(
                              scores[i].toString(),
                              style: const TextStyle(
                                color: KalchakraColors.gold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(color: Colors.white24),
                    _statRow('Best score', widget.save.bestScore.toString()),
                    _statRow('Best combo', 'x${widget.save.bestCombo}'),
                    _statRow('Total kills', widget.save.totalKills.toString()),
                    _statRow('Runs', widget.save.totalRuns.toString()),
                  ],
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: const TextStyle(color: KalchakraColors.parchment)),
        Text(
          value,
          style: const TextStyle(
            color: KalchakraColors.gold,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _showLore() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KalchakraColors.cosmic,
        title: const Text(
          'LORE',
          style: TextStyle(color: KalchakraColors.gold),
        ),
        content: const SingleChildScrollView(
          child: Text(
            kLore,
            style: TextStyle(
              color: KalchakraColors.parchment,
              height: 1.5,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettings() async {
    var sound = widget.save.soundEnabled;
    var haptics = widget.save.hapticsEnabled;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: KalchakraColors.cosmic,
          title: const Text(
            'SETTINGS',
            style: TextStyle(color: KalchakraColors.gold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SwitchListTile(
                key: const Key('sound-toggle'),
                value: sound,
                activeThumbColor: KalchakraColors.gold,
                title: const Text(
                  'Sound',
                  style: TextStyle(color: KalchakraColors.parchment),
                ),
                onChanged: (value) => setState(() => sound = value),
              ),
              SwitchListTile(
                key: const Key('haptics-toggle'),
                value: haptics,
                activeThumbColor: KalchakraColors.gold,
                title: const Text(
                  'Vibration',
                  style: TextStyle(color: KalchakraColors.parchment),
                ),
                onChanged: (value) => setState(() => haptics = value),
              ),
              const SizedBox(height: 12),
              const Text(
                'Controls\n'
                '• Drag anywhere to weave the weaver\n'
                '• Weapons fire on their own with aim assist\n'
                '• ❄ Freeze time   ↺ Rewind   ⏩ Fast forward',
                style: TextStyle(color: KalchakraColors.energyCyan, height: 1.5),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                widget.onSettingsChanged(
                  widget.save.copyWith(
                    soundEnabled: sound,
                    hapticsEnabled: haptics,
                  ),
                );
                Navigator.of(dialogContext).pop();
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KalchakraColors.cosmic,
        title: const Text(
          'RESET PROGRESS',
          style: TextStyle(color: KalchakraColors.temporalRed),
        ),
        content: const Text(
          'All scores, unlocked realms and stats will be erased. Continue?',
          style: TextStyle(color: KalchakraColors.parchment),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      widget.onSettingsChanged(const SaveData());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _unlockedRealm > 0;
    final options = <_MenuOption>[
      _MenuOption(
        buttonKey: const Key('menu-play'),
        icon: Icons.play_arrow,
        label: 'PLAY',
        sublabel: 'Start from ${kRealms.first.name}',
        onTap: () => _playFrom(0),
      ),
      _MenuOption(
        buttonKey: const Key('menu-continue'),
        icon: Icons.fast_forward,
        label: 'CONTINUE',
        sublabel: canContinue
            ? '${kRealms[_unlockedRealm].name}  •  x${_continueMultiplier.toStringAsFixed(1)} score'
            : 'Locked — clear a realm first',
        enabled: canContinue,
        onTap: () => widget.onContinue(
          startRealm: _unlockedRealm,
          multiplier: _continueMultiplier,
        ),
      ),
      _MenuOption(
        buttonKey: const Key('menu-scores'),
        icon: Icons.emoji_events,
        label: 'SCORES',
        sublabel: widget.save.highScores.isEmpty
            ? 'No runs yet'
            : 'Best ${widget.save.bestScore}',
        onTap: _showScores,
      ),
      _MenuOption(
        buttonKey: const Key('menu-lore'),
        icon: Icons.auto_stories,
        label: 'LORE',
        sublabel: 'The legend of the wheel',
        onTap: _showLore,
      ),
      _MenuOption(
        buttonKey: const Key('menu-settings'),
        icon: Icons.settings,
        label: 'SETTINGS',
        sublabel: 'Sound, vibration, controls',
        onTap: _showSettings,
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, 0),
            radius: 1.3,
            colors: <Color>[KalchakraColors.cosmic, KalchakraColors.voidBlack],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 18, bottom: 6),
                child: Text(
                  'KALCHAKRA',
                  style: TextStyle(
                    color: KalchakraColors.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5,
                  ),
                ),
              ),
              Text(
                'Realm ${_unlockedRealm + 1} of ${kRealms.length} unlocked',
                style: const TextStyle(color: KalchakraColors.parchment, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final radius = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ) * 0.30;
                    return Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: _spin,
                          builder: (context, child) => CustomPaint(
                            size: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                            painter: _WheelPainter(progress: _spin.value),
                          ),
                        ),
                        for (var i = 0; i < options.length; i++)
                          _positionedOption(options[i], i, options.length, radius),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextButton.icon(
                  key: const Key('menu-reset'),
                  onPressed: _confirmReset,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text(
                    'Reset progress',
                    style: TextStyle(color: KalchakraColors.parchment),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedOption(
    _MenuOption option,
    int index,
    int total,
    double radius,
  ) {
    final angle = -math.pi / 2 + index * 2 * math.pi / total;
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Center(child: option),
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  const _MenuOption({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.enabled = true,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? KalchakraColors.gold : Colors.white24;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        key: buttonKey,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: 132,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: KalchakraColors.cosmic.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KalchakraColors.parchment,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    final spin = progress * 2 * math.pi;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KalchakraColors.gold.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KalchakraColors.gold.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      radius * 0.55,
      Paint()
        ..color = KalchakraColors.energyCyan.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke,
    );

    for (var i = 0; i < 5; i++) {
      final angle = spin + i * 2 * math.pi / 5;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.5),
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        Paint()
          ..color = KalchakraColors.gold.withValues(alpha: 0.25)
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
