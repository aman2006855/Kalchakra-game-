# कालचक्र गेम (Kaal Chakra Game)

Ek traditional Indian circular dice-race game — pure native Flutter app (koi WebView nahi).
Aap (🔴 laal token) aur computer (🔵 neela token) chakri ke 60 positions pe daudte hain.
Jo pehle **exactly 60** pahuncha, wo jeeta. Zyada aane wale kadam count nahi hote — precision khelna hai!

## Project Structure

```
├── lib/
│   └── main.dart          # Pura game (UI + logic, single file)
├── android/               # Native Android platform folder (Gradle build)
├── test/
│   └── widget_test.dart   # Pura game play karke winner dialog verify karta hai
├── pubspec.yaml           # Package config (name: kaal_chakra_game)
├── pubspec.lock           # Locked dependency versions (reproducible builds)
├── analysis_options.yaml  # Lints
├── .gitignore             # build/, .dart_tool/ etc. zip se bahar rehte hain
├── .metadata              # Flutter tooling metadata
└── README.md
```

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

Note: `.gitignore` ke baaki patterns (`build/`, `.dart_tool/`, `.idea/` etc.) local
machine pe exist hi nahi karte (kabhi build nahi kiya), isliye unhe exclude karne ki
zaroorat nahi. `.git/` folder zaroor exclude karein.
