# KALCHAKRA — The Time Weaver's Paradox

Pure native Flutter (Dart) port of the mythic space-shooter. No WebView, no web
assets — every entity, particle and sound is generated in Dart.

You are the last Time Weaver. The cosmic wheel of time has shattered and the
fragments are scattered across seven mythological realms.

## Gameplay

- **7 Lokas** — SATYA, TAPTA, JALA, VAYU, BHUMI, ANTARIKSHA and MAHAKAAL LOKA.
  Each realm has its own palette, spawns faster and demands more kills
  (20 → 45) to clear.
- **Enemies** — `basic`, `shooter` (fires back), `fast`, and armoured **wraiths**
  (6 HP, 4.5× score) that appear from the third realm onwards.
- **Time powers** — ❄ **Freeze** (30 energy, world drops to 0.3×), ↺ **Rewind**
  (3 uses, jumps you ~2 s back in time with brief invulnerability),
  ⏩ **Fast Forward** (20 energy, you speed up while the world barely does).
- **Combo** — every kill raises the multiplier up to ×10, but the window only
  stays open for 3.5 s, so you have to keep the pressure on.
- **Power-ups** — defeated enemies can drop energy, health or an extra rewind.

### Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Move | Drag anywhere (floating stick) | WASD / arrows |
| Shoot | Automatic with aim assist | Hold click |
| Freeze / Rewind / Fast forward | ❄ ↺ ⏩ buttons | Space / Q / E |
| Pause | ⏸ button | — |

## Progress is saved locally

High scores (top 10), best score, best combo, the **highest realm you unlocked**,
total runs, total kills and the sound/vibration toggles are stored on the device
with `shared_preferences`. Once you clear a realm you can use **CONTINUE** to
start straight from it with a score multiplier (×1.5 per skipped realm) — a real
risk/reward option instead of replaying from the beginning.

## Bugs fixed during the port

1. **Power-ups never spawned** — `spawnPowerUp()` existed but was never called.
2. **Frame-rate dependent game** — the original counted 60 fps frames, so on
   90/120 Hz phones everything ran up to 2× too fast. Now delta-time based.
3. **Fast-forward was a punishment** — enemies moved 4× and the player only
   1.5×. Now the world speeds up slightly while the player speeds up a lot.
4. **Unbounded enemy spawning** — enemies accumulated forever off screen;
   there is now a per-realm cap and off-screen recycling.
5. **Rewind was nearly useless** — it moved you back ~10 px. It now rewinds
   ~2.2 s and grants invulnerability.
6. **Combo never decayed** — it only reset when you got hit, which made ×10
   trivial to hold forever.
7. **No continuous fire** — the old `keys['click']` path did nothing and mobile
   could not move and shoot at the same time.
8. **Division by zero** when an enemy sat exactly on the player.
9. **The realm intro blocked the pause button** for its whole 2.4 s.

## Project structure

```
├── lib/
│   ├── main.dart              # App root, screen flow, game over screen
│   ├── game/
│   │   ├── engine.dart        # Pure Dart simulation (no Flutter imports)
│   │   ├── realms.dart        # The seven Lokas + lore text
│   │   ├── renderer.dart      # CustomPainter for the whole world
│   │   ├── audio.dart         # Synthesised WAV sound effects + ambient drone
│   │   └── storage.dart       # Save data model + shared_preferences store
│   └── ui/
│       ├── title_screen.dart  # Animated chakra title
│       ├── menu_screen.dart   # Rotating wheel menu, scores, lore, settings
│       └── game_screen.dart   # Game loop, input layer, HUD, overlays
├── test/
│   ├── engine_test.dart       # 21 unit tests over the simulation
│   └── widget_test.dart       # Title → menu → game → pause flow
├── android/ ios/ web/ linux/ macos/ windows/
└── pubspec.yaml
```

## Verification

```bash
flutter pub get
flutter analyze   # No issues found
flutter test      # 23 tests, all passing
```

## Build the APK

Every push to `main` builds the release APK through GitHub Actions
(`.github/workflows/apk-release.yml`):

1. Repo → **Actions** → latest *Build Release APK* run
2. **Artifacts** → download `kaal-chakra-release-apk`
3. Push a `v1.0.1` style tag to also publish the APK under **Releases**

Signing: set the repository secrets `KEYSTORE_BASE64`, `STORE_PASSWORD`,
`KEY_PASSWORD` and `KEY_ALIAS` and the release build is signed with your
keystore (otherwise it falls back to debug signing, which is fine for testing).
The APK is restricted to `arm64-v8a` in `android/app/build.gradle.kts`.
