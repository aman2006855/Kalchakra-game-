# कालचक्र गेम (Kaal Chakra Game)

Ek traditional Indian circular dice-race game — pure native Flutter app (koi WebView nahi).
Aap (🔴 laal token) aur computer (🔵 neela token) chakri ke 60 positions pe daudte hain.
Jo pehle **exactly 60** pahuncha, wo jeeta. Zyada aane wale kadam count nahi hote — precision khelna hai!

## Project Structure

Poora Flutter-standard structure — sabhi 6 platforms ke saath (Android par focus,
baaki folders builders ki requirement ke liye maujood hain):

```
├── lib/
│   └── main.dart          # Pura game (UI + logic, single file)
├── android/               # Native Android platform folder (arm64-v8a release target)
├── ios/                   # iOS platform folder (builders ki requirement)
├── web/, linux/, macos/, windows/  # Baaki platform folders
├── test/
│   └── widget_test.dart   # Pura game play karke winner dialog verify karta hai
├── pubspec.yaml           # Package config (name: kaal_chakra_game)
├── pubspec.lock           # Locked dependency versions (reproducible builds)
├── analysis_options.yaml  # Lints (platform directories excluded)
├── .gitignore             # build/, .dart_tool/ etc. zip se bahar rehte hain
├── .metadata              # Flutter tooling metadata
└── README.md
```

## GitHub Actions se APK banana

Har push to `main` pe workflow (`.github/workflows/apk-release.yml`) automatically
release APK build karta hai:

1. GitHub repo → **Actions** tab → latest "Build Release APK" run
2. Run page ke **Artifacts** section se `kaal-chakra-release-apk` download karo
3. Version tag push karo (`v1.0.1` jaisa) to APK **Releases** section mein bhi attach ho jata hai

Signing: repo secrets (`KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`)
set hon to release keystore se sign hota hai, warna debug-signing fallback.

## Verification

```bash
flutter pub get
flutter analyze   # No issues found
flutter test      # All tests passed
```

## Android Release (ARM64)

`android/app/build.gradle.kts` mein `abiFilters` sirf `arm64-v8a` ko include karta hai,
isliye release APK automatically 64-bit ARM devices ke liye banta hai.

Local build (agar Flutter SDK ho):

```bash
flutter build apk --release --target-platform android-arm64
```

## Online Builder (FlutLab / flutter.io style) pe zip upload

Repo ka zip direct upload ho sakta hai — structure Flutter-standard hai:

```bash
git clone <this-repo>
cd <repo-folder>
zip -r ../kaal_chakra.zip . -x ".git/*"
```

Note: `.gitignore` ke patterns (`build/`, `.dart_tool/`, `.idea/` etc.) local
machine pe un folders ko commit hone se rok dete hain. `.git/` folder zip mein
zaroor exclude karein.
