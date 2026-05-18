# Clapperboard — Claude project notes

Flutter app. Targets: Android tablets, iPad, web. Solo developer (Adaminion).

## Workflow rules — IMPORTANT

- **Never create branches.** Work on `main` only.
- **Never open pull requests.** This is a solo repo, branches and PRs add zero value.
- **Never push without explicit user approval.** Make changes locally, let the user test, only push after the user says it's OK.
- After approval: `git add` → commit → push directly to `origin/main`. Done.
- Never force-push to `main`. If history needs editing, ask first.

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

- Single-file UI in `lib/main.dart`. Keep MVP — no premature splitting until pain is real.
- Persistence: `SharedPreferences` only. JSON-encode complex values.
- Landscape locked on mobile (`AndroidManifest.xml`, `Info.plist`). Web is responsive.
- Colour palette: black background, white text. Inverted (white bg / black text) for the 1-second clap flash.
- UI chrome (CLAP label, ☰ menu, − X + buttons) is dimmed to alpha 0.45 so the production data dominates.
- Bump button order is **− X +** (not + X −).
- Grid divider thickness: 5 px.
- All text sizes multiply by `_scale` from the text-size setting (S 0.85 / M 1.0 / L 1.5 / XL 2.0).

## Don't (without asking)

- Add new packages to `pubspec.yaml`.
- Break the web build (`flutter build web --release` must keep working).
- Add platform code for desktop (Windows/macOS/Linux) — not in scope.
- Add analytics, crash reporting, network calls — this is a fully local app.

## Repo

- GitHub: https://github.com/Adaminion/clapperboard
- Default branch: `main` (the only branch)
