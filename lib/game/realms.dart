/// Realm (Loka) definitions — the nine stages of the shattered Kalchakra.
///
/// Colours are plain ARGB ints so the game engine stays free of any Flutter
/// import and can be unit tested in a plain Dart environment.
library;

class Realm {
  const Realm({
    required this.name,
    required this.subtitle,
    required this.color,
    required this.background,
    required this.threat,
  });

  /// English name of the realm, e.g. `SATYA LOKA`.
  final String name;

  /// Fantasy subtitle shown during the realm intro, e.g. `Realm of Truth`.
  final String subtitle;

  /// Primary accent colour of the realm.
  final int color;

  /// Background colour of the realm.
  final int background;

  /// What the enemies of this realm are capable of, shown during the intro so
  /// the player can see exactly which ability just unlocked.
  final String threat;
}

/// The nine mythological realms, in play order.
const List<Realm> kRealms = <Realm>[
  Realm(
    name: 'SATYA LOKA',
    subtitle: 'Realm of Truth',
    color: 0xFF00FFCC,
    background: 0xFF0A1A2E,
    threat: 'They only close in. Learn to move.',
  ),
  Realm(
    name: 'TAPTA LOKA',
    subtitle: 'Realm of Fire',
    color: 0xFFFF6633,
    background: 0xFF2E1A0A,
    threat: 'UNLOCKED — they open fire.',
  ),
  Realm(
    name: 'JALA LOKA',
    subtitle: 'Realm of Water',
    color: 0xFF3399FF,
    background: 0xFF0A2E2E,
    threat: 'UNLOCKED — they dodge your shots.',
  ),
  Realm(
    name: 'VAYU LOKA',
    subtitle: 'Realm of Wind',
    color: 0xFF99FF99,
    background: 0xFF1A2E0A,
    threat: 'UNLOCKED — Weavers sidestep in bursts.',
  ),
  Realm(
    name: 'BHUMI LOKA',
    subtitle: 'Realm of Earth',
    color: 0xFFCC9966,
    background: 0xFF2E1A0A,
    threat: 'They hold their range and circle you.',
  ),
  Realm(
    name: 'ANTARIKSHA LOKA',
    subtitle: 'Realm of Space',
    color: 0xFFCC66FF,
    background: 0xFF1A0A2E,
    threat: 'Their fire leads where you are going.',
  ),
  Realm(
    name: 'SWARGA LOKA',
    subtitle: 'Realm of Light',
    color: 0xFFFFE082,
    background: 0xFF2E2A0A,
    threat: 'Nothing is wasted here.',
  ),
  Realm(
    name: 'NARAKA LOKA',
    subtitle: 'Realm of Fire and Shadow',
    color: 0xFFB71C1C,
    background: 0xFF1A0505,
    threat: 'Wraiths hunt you in the open.',
  ),
  Realm(
    name: 'MAHAKAAL LOKA',
    subtitle: 'Realm of Time',
    color: 0xFFFF3366,
    background: 0xFF2E0A1A,
    threat: 'Every skill. All of them. At once.',
  ),
];

/// Lore shown from the main menu.
const String kLore = '''
KALCHAKRA — The Time Weaver's Paradox

The cosmic wheel of time has shattered into fragments. You are the last Time
Weaver, threading the nine mythological realms to gather the pieces before the
wheel can never be rebuilt.

Every realm you clear pulls you deeper into the wheel. Enemies leave echoes of
where they were — your own footsteps can be rewound, and time itself can be
frozen or hurried.

In the deeper lokas the weavers fight back: they read your shots and slip aside,
and their aim leads where you are going instead of where you are.

Your actions echo through time. Choose wisely, Weaver.
''';
