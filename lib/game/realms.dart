/// Realm (Loka) definitions — the seven stages of the shattered Kalchakra.
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
  });

  /// English name of the realm, e.g. `SATYA LOKA`.
  final String name;

  /// Fantasy subtitle shown during the realm intro, e.g. `Realm of Truth`.
  final String subtitle;

  /// Primary accent colour of the realm.
  final int color;

  /// Background colour of the realm.
  final int background;
}

/// The nine mythological realms, in play order.
const List<Realm> kRealms = <Realm>[
  Realm(
    name: 'SATYA LOKA',
    subtitle: 'Realm of Truth',
    color: 0xFF00FFCC,
    background: 0xFF0A1A2E,
  ),
  Realm(
    name: 'TAPTA LOKA',
    subtitle: 'Realm of Fire',
    color: 0xFFFF6633,
    background: 0xFF2E1A0A,
  ),
  Realm(
    name: 'JALA LOKA',
    subtitle: 'Realm of Water',
    color: 0xFF3399FF,
    background: 0xFF0A2E2E,
  ),
  Realm(
    name: 'VAYU LOKA',
    subtitle: 'Realm of Wind',
    color: 0xFF99FF99,
    background: 0xFF1A2E0A,
  ),
  Realm(
    name: 'BHUMI LOKA',
    subtitle: 'Realm of Earth',
    color: 0xFFCC9966,
    background: 0xFF2E1A0A,
  ),
  Realm(
    name: 'ANTARIKSHA LOKA',
    subtitle: 'Realm of Space',
    color: 0xFFCC66FF,
    background: 0xFF1A0A2E,
  ),
  Realm(
    name: 'SWARGA LOKA',
    subtitle: 'Realm of Light',
    color: 0xFFFFE082,
    background: 0xFF2E2A0A,
  ),
  Realm(
    name: 'NARAKA LOKA',
    subtitle: 'Realm of Fire and Shadow',
    color: 0xFFB71C1C,
    background: 0xFF1A0505,
  ),
  Realm(
    name: 'MAHAKAAL LOKA',
    subtitle: 'Realm of Time',
    color: 0xFFFF3366,
    background: 0xFF2E0A1A,
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
