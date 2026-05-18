# Clapperboard

Flutter app. Digital movie clapperboard. Targets: Android tablets, iPad, web.

GitHub: https://github.com/Adaminion/clapperboard

## Run / build / test

```sh
flutter run -d chrome          # web (fastest dev loop)
flutter run                    # connected Android / iOS device
flutter build web --release    # production web bundle in build/web
flutter build apk              # Android
flutter test
flutter analyze
```

## Project conventions

- Single-file UI in `lib/main.dart`. Keep MVP — no premature splitting.
- Persistence: `SharedPreferences` only. JSON-encode complex values.
- Landscape locked on mobile (`AndroidManifest.xml`, `Info.plist`).
  Web is responsive.
- Default palette: black background, white text.
  Inverted (white bg / black text) during the 1-second clap flash.
- UI chrome (CLAP label, ☰ menu, bump buttons) is dimmed to alpha 0.45
  so the production data dominates visually.
- Bump button order is **− X +** (not + X −).
- Grid divider thickness: 5 px.
- Text size setting (S 0.85 / M 1.0 / L 1.5 / XL 2.0) multiplies every
  font size via `_scale`.

## Don't (without asking)

- Add new packages to `pubspec.yaml`.
- Break the web build (`flutter build web --release` must keep working).
- Add platform code for desktop (Windows/macOS/Linux) — not in scope.
- Add analytics, crash reporting, or network calls — this app is fully local.
