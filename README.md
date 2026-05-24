# Bloom Tracker — iOS Visual Progress Tracker

A single-purpose iOS app that lets you photograph the same subject repeatedly over time and see how it changes. Local-first, no accounts, photos stored in the app's private container.

## Requirements

- **Xcode 26.0+** (Liquid Glass requires the iOS 26 SDK)
- **iOS 26.0+** target device or simulator
- **XcodeGen** (`brew install xcodegen`) — used to generate the `.xcodeproj`

## Build

```bash
xcodegen generate
open Bloom.xcodeproj
```

Then build and run the `Bloom` scheme on an iOS 26 simulator or device.

## Architecture

See [`Bloom/`](Bloom/) for source organization:

- `App/` — root navigation
- `DesignSystem/` — Neon Playroom palette, typography, Liquid Glass modifiers
- `Data/` — SwiftData models, `ProjectRepository`, `PhotoAssetStore`, `MediaLoader`, and `PhotoStore`
- `Features/` — `Home/`, `ProjectEditor/`, `Camera/`, `Review/`, `Timeline/`, `Compare/`, `Timelapse/`, `Export/`, `Settings/`
- `Utilities/` — image processing, haptics, accessibility env
- `Resources/` — `Assets.xcassets`, fonts, `Info.plist`

## Fonts

The display font (Bebas Neue) and body font (Inter) are referenced by file name in `Info.plist`. To enable them visually:

1. Download [Bebas Neue](https://fonts.google.com/specimen/Bebas+Neue) and [Inter](https://fonts.google.com/specimen/Inter).
2. Drop the `.ttf` files into [`Bloom/Resources/Fonts/`](Bloom/Resources/Fonts/) matching the names listed in `project.yml`'s `UIAppFonts`.

Until then, system font fallbacks render automatically.

## Privacy posture

- Photos are written to the app's private `Documents/Photos/<projectID>/<photoID>.heic` directory, **never** the camera roll (PRD §4.1).
- EXIF/GPS metadata is stripped on save (PRD §5.3).
- No account system, no CloudKit runtime, no server-side storage in v1 (PRD §5.1, §5.2).

## Tests

```bash
xcodebuild -scheme Bloom -destination 'platform=iOS Simulator,name=iPhone 16' test
```
