# KALCHAKRA — The Time Weaver's Paradox

Pure native Flutter (Dart) port of the mythic space-shooter, built for Android
phones. No WebView, no web assets — every entity, particle and sound is
generated in Dart, and every action is touch driven.

You are the last Time Weaver. The cosmic wheel of time has shattered and the
fragments are scattered across nine mythological realms.

## Gameplay

- **9 Lokas** — SATYA, TAPTA, JALA, VAYU, BHUMI, ANTARIKSHA, SWARGA, NARAKA and
  MAHAKAAL LOKA. Each realm has its own palette, spawns faster, mixes in nastier
  archetypes and demands more kills (20 → 60) to clear.
- **Enemies** — every archetype shoots back, so standing in the middle is never
  safe:
  - `basic` charges you *and* fires a slow aimed shot.
  - `fast` darts in and snipes from close range.
  - `shooter` holds a 250 px ring and fires aimed, lead-predicted shots.
  - `weaver` (from the third realm) slides sideways at mid range and fans
    2–3 round bursts so a single sidestep is not enough.
  - `wraith` — armoured, 6 HP, 4.5× score.
  - They weave around their preferred distance, watch your own shots and
    actively slip sideways to dodge them (dodging gets more likely deeper in).
  - Every shot is telegraphed with a closing red ring ~0.3 s before it leaves
    the barrel, so incoming fire is always readable.
- **Real-time threat measurement** — every frame the engine sums up the
  incoming enemy fire that is actually closing in on you, weighted by distance,
  and exposes it as a direction + intensity. A HUD arrow points at the danger,
  and a faint movement assist nudges you sideways *only* when you are not
  actively steering. The assist fades by up to 65% in the deepest realm, so the
  game still gets harder as you progress.
- **Time powers** — ❄ **Freeze** (30 energy, world drops to 0.3×), ↺ **Rewind**
  (3 uses, jumps you ~2 s back in time with brief invulnerability),
  ⏩ **Fast Forward** (20 energy, you speed up while the world barely does).
- **Combat skills** — ➤ **Dash** (2.4 s cooldown, a burst of movement with 0.3 s
  of invulnerability; with no input it dashes *away* from the incoming fire) and
  🛡 **Weave Shield** (25 energy, eats one hit entirely, 11 s recharge).
- **Combo** — every kill raises the multiplier up to ×10, but the window only
  stays open for 3.5 s, so you have to keep the pressure on.
- **Power-ups** — defeated enemies can drop energy, health or an extra rewind.

### Controls — touch only

This is a phone game, so **everything is done with your thumb**. There is no
keyboard or mouse support at all; the whole game is playable with one hand.

| Action | Touch |
| --- | --- |
| Move | **Drag** anywhere on the screen (a floating stick appears under your finger) |
| Attack | **Tap** a spot — fires there and keeps that aim locked for 1.6 s. If you are not touching anything, the weaver auto-fires with aim assist. |
| Freeze / Rewind / Fast forward | ❄ ↺ ⏩ buttons on the bottom bar |
| Dash / Shield | ➤ 🛡 buttons on the bottom bar |
| Pause | ⏸ button, top right |

Both gestures can be mixed freely — drag to run and tap to shoot are
independent, so you never have to stop moving to attack.

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
10. **The enemies never attacked** — only `shooter` enemies fired, they spawned
    off-screen and were killed before they ever lined up a shot, and the player
    could camp the centre forever. Now every archetype shoots, shooters hold a
    mid-range ring instead of walking into your bullet, shots lead your movement,
    and a new `weaver` archetype trades in sidestepping bursts.
11. **Enemies walked in a straight line into your gun** — they now weave around
    a preferred distance and actively dodge shots that are about to land.
12. **Tapping on yourself did nothing** — the shot was discarded when the target
    was within 1 px of the weaver. It now keeps firing the way you were aiming.
13. **The title screen was laid out with `Spacer`s around a fixed 240 px wheel**,
    which overflowed on real phones: the wordmark and the button were clipped on
    the left. It is now sized from the available box with `LayoutBuilder` and
    `FittedBox`, so nothing clips on any screen.
14. **Keyboard controls removed** — this ships as an Android phone game and a
    smartphone has no keyboard, so the `Focus`/`KeyEvent` handler and the
    engine's `setKeyboard` input channel are gone. Move, attack, all three time
    powers, dash, shield and pause are now reachable by touch only.

## Project structure

```
├── lib/
│   ├── main.dart              # App root, screen flow, game over screen
│   ├── game/
│   │   ├── engine.dart        # Pure Dart simulation (no Flutter imports)
│   │   ├── realms.dart        # The nine Lokas + lore text
│   │   ├── renderer.dart      # CustomPainter for the whole world
│   │   ├── audio.dart         # Synthesised WAV sound effects + ambient drone
│   │   └── storage.dart       # Save data model + shared_preferences store
│   └── ui/
│       ├── title_screen.dart  # Animated chakra title
│       ├── menu_screen.dart   # Rotating wheel menu, scores, lore, settings
│       └── game_screen.dart   # Game loop, touch input layer, HUD, overlays
├── test/
│   ├── engine_test.dart       # 42 unit tests over the simulation
│   └── widget_test.dart       # 6 tests: title, menu, game loop, tap vs drag
├── android/ ios/ web/ linux/ macos/ windows/
└── pubspec.yaml
```

## Verification

```bash
flutter pub get
flutter analyze   # No issues found
flutter test      # 48 tests, all passing
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
