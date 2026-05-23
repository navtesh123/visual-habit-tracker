# Progress — iOS Visual Progress Tracker

A single-purpose iOS app that lets you photograph the same subject repeatedly over time and see how it changes. Local-first, no accounts, photos stored in the app's private container.

## Requirements

- **Xcode 26.0+** (Liquid Glass requires the iOS 26 SDK)
- **iOS 26.0+** target device or simulator
- **XcodeGen** (`brew install xcodegen`) — used to generate the `.xcodeproj`

## Build

```bash
xcodegen generate
open Progress.xcodeproj
```

Then build and run the `Progress` scheme on an iOS 26 simulator or device.

## Architecture

See [`Progress/`](Progress/) for source organization:

- `App/` — root navigation
- `DesignSystem/` — Neon Playroom palette, typography, Liquid Glass modifiers
- `Data/` — SwiftData models and `PhotoStore` (writes HEIC originals + thumbs to app Documents)
- `Features/` — `Home/`, `ProjectEditor/`, `Camera/`, `Review/`, `Timeline/`, `Compare/`
- `Utilities/` — image processing, haptics, accessibility env
- `Resources/` — `Assets.xcassets`, fonts, `Info.plist`

## Fonts

The display font (Bebas Neue) and body font (Inter) are referenced by file name in `Info.plist`. To enable them visually:

1. Download [Bebas Neue](https://fonts.google.com/specimen/Bebas+Neue) and [Inter](https://fonts.google.com/specimen/Inter).
2. Drop the `.ttf` files into [`Progress/Resources/Fonts/`](Progress/Resources/Fonts/) matching the names listed in `project.yml`'s `UIAppFonts`.

Until then, system font fallbacks render automatically.

## Privacy posture

- Photos are written to the app's private `Documents/Photos/<projectID>/<photoID>.heic` directory, **never** the camera roll (PRD §4.1).
- EXIF/GPS metadata is stripped on save (PRD §5.3).
- No account system, no server-side storage in v1 (PRD §5.1, §5.2).

## Tests

```bash
xcodebuild -scheme Progress -destination 'platform=iOS Simulator,name=iPhone 16' test
```
