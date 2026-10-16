# TouchMiddle

[繁體中文](README.zh-TW.md)

A native macOS menu bar app that turns trackpad gestures into keyboard shortcuts or a middle click. You choose the gesture, the action, and whether the rule applies to all apps or to one app.

## What it does

- **17 trackpad gestures**, listed below.
- **Two kinds of action**: a keyboard shortcut you record (with ⌘ ⌥ ⌃ ⇧), or a middle click at the pointer.
- **Global or per-app rules.** An enabled per-app rule takes priority over the global rule for the same gesture.
- **Modifier conditions.** A rule can require ⌘, ⌥, ⌃ or ⇧ to be held during the gesture, so one gesture can trigger different actions.
- **Update check.** The app checks GitHub for new releases once every 24 hours. You download and replace the app yourself.

Taps do not need a physical click. Lift all fingers fully between taps.

| Gesture | How to do it |
|---|---|
| Three-finger tap | Tap with three fingers, then lift. Default rule: middle click. |
| Four-finger tap | Tap with four fingers, then lift. |
| Two-finger double tap | Tap twice with two fingers. |
| Three-finger double tap | Tap twice with three fingers. |
| Three-finger long press | Hold three fingers still for at least 500 ms, then lift within 2 s. |
| Corner two-finger tap (×4) | Tap with two fingers inside one corner (25% of width and height): top-left, top-right, bottom-left or bottom-right. |
| One finger hold + left / right tap (×2) | Hold one finger still for 150 ms, then tap with another finger on its left or right. |
| Two fingers hold + left / right tap (×2) | Hold two fingers still for 150 ms, then tap with a third finger outside them on the left or right. Keep holding to repeat. |
| Two fingers hold + left / right double tap (×2) | Same as above, but tap twice with the third finger. |
| Two fingers hold + swipe up / down (×2) | Hold two fingers still for 150 ms, then swipe a third finger up or down (at least 6% of the trackpad height). |

"Left" and "right" are relative to the fingers you hold, not to the halves of the trackpad. Tap movement tolerance, tap duration and double-tap interval can be adjusted in the settings tab (狀態與設定).

## Install

1. Download the latest `TouchMiddle-*-macos-arm64.zip` from [GitHub Releases](https://github.com/ilovetai1/TouchMiddle/releases). The "Source code" archives are not the app.
2. Unzip it and move `TouchMiddle.app` to `/Applications` or `~/Applications`.
3. Open the app. The app is not notarized by Apple, so macOS may block it the first time. If you trust the source, allow it in **System Settings → Privacy & Security**.
4. Grant **Accessibility** permission when asked.
5. Add a gesture rule. Then touch the trackpad once and lift all fingers to calibrate.

**Permission is on, but the app still says it has no permission?** macOS can keep the permission of an older build. Quit TouchMiddle, remove it from the Accessibility list, add the new app again, and restart it.

More detail (Traditional Chinese): [install, update and uninstall](docs/INSTALL.md) · [signing and permission troubleshooting](docs/SIGNING.md) · [full usage guide](touchmiddle/README.txt)

## Requirements and known limits

- **The app interface is in Traditional Chinese only.**
- **Apple Silicon only.** Release builds contain arm64 only.
- **Tested on one setup.** The package declares macOS 14 or later, but real-device testing covers only Apple M5, the built-in trackpad, and macOS 27.0.1. External Magic Trackpad and Intel Macs are not tested.
- **Uses a private framework** (MultitouchSupport) to read touches. A macOS update can break it.
- **Does not block macOS gestures.** A built-in macOS gesture and a TouchMiddle gesture can both fire.
- **Missed or false triggers can happen.** Not all newer gestures have been tested by hand on a real trackpad.
- **The target app decides the result.** TouchMiddle sends the shortcut; it cannot make an app respond to it.
- **Not tested yet:** sleep/wake, long sessions, all palm contacts, and launch at login after a real re-login.
- **Privacy:** rules and diagnostics stay on your Mac. The only network request is the GitHub release check.

## Background

TouchMiddle started as a study of how existing trackpad tools on the market handle touch input. That study used static analysis as design reference only. TouchMiddle's gesture recognition and event output are written from scratch for this project, and the project does not claim to reproduce any other product. Third-party research material is not in this repository and is not covered by this project's license.

## Build from source

Requires macOS, Xcode / Swift 6 and Python 3. From the repository root:

```bash
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
bash touchmiddle/Tools/build-app.sh --output "$HOME/Applications/TouchMiddle.app"
```

The output path must not exist yet. Signing, packaging and versioning: [docs/BUILDING.md](docs/BUILDING.md) (Traditional Chinese). Release history: [CHANGELOG](CHANGELOG.md).

## License

[MIT](LICENSE) © [ilovetai1](https://github.com/ilovetai1). Provided as is, without warranty.
