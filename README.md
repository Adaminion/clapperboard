# Clapperboard

A simple digital movie clapperboard for Android tablets and iPad, built with Flutter.

![Clapperboard icon](assets/icon/icon.png)

## Features

- **Classic layout**: TITLE, DATE/TIME (auto), SCENE, TAKE, ROLL, CAMERA, FPS, SOUND.
- **CLAP button**: tap to invert screen colours for one second (black ↔ white) with haptic feedback. Use it as a visual sync slate.
- **Quick scene/take controls**: `+` increments, `−` decrements (never below 0), `X` clears.
- **Long-press any field** to edit its value with the keyboard.
- **Presets**: save & load the production-static fields (TITLE, ROLL, CAMERA, FPS, SOUND) so you can switch setups in one tap.
- **Local persistence**: every change is saved immediately to local storage (`SharedPreferences`).
- **Landscape locked**: optimised for tablet use.

## Gestures

| Element          | Short tap          | Long-press   |
|------------------|--------------------|--------------|
| TITLE            | —                  | edit         |
| SCENE, TAKE +/X/−| +1 / clear / −1    | (on number) edit value |
| ROLL, CAMERA, FPS, SOUND | —          | edit         |
| DATE/TIME        | —                  | (auto, read-only) |
| CLAP             | trigger flash      | —            |
| ☰ menu           | Save / Load preset / Reset scene & take |

## Running

```sh
flutter pub get
flutter run        # connect an Android device or iPad / simulator
```

### Build

```sh
flutter build apk           # Android
flutter build ios           # iOS (requires macOS + Xcode)
```

## Project layout

```
lib/
  main.dart            # Single-file app: UI, state, persistence, presets
android/               # Native config (landscape locked via AndroidManifest)
ios/                   # Native config (landscape locked via Info.plist)
assets/icon/icon.png   # Source image for the app launcher icon
```

## License

MIT.
