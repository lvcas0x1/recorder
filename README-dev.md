# Recorder: developer guide

Recorder is a native macOS menu-bar screen recorder written in Swift (AppKit + SwiftUI) and built with Swift Package Manager. Its only third-party package is [Sparkle](https://sparkle-project.org/) for in-app updates.
The planning artifacts are in `openspec/changes/add-screen-recorder-app/` (proposal, specs, design, tasks).

## Requirements

- macOS 27 or later. Recording mixes the microphone into the system audio with `SCRecordingOutputConfiguration.mixesAudioWithMicrophone`, which needs macOS 27 ([Apple documentation](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration/mixesaudiowithmicrophone)).
- Xcode (built and tested with Xcode 27.0, Swift 6.4). The scripts set `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer` unless you override it.

## Build and run

```bash
Scripts/build-app.sh          # release build -> build/Recorder.app
Scripts/build-app.sh debug    # debug build
open build/Recorder.app
```

`Scripts/build-app.sh` reads these optional environment variables:

| Variable | Effect |
|---|---|
| `APP_VERSION` | `CFBundleShortVersionString` of the bundle |
| `BUILD_NUMBER` | `CFBundleVersion` of the bundle |
| `SIGN_IDENTITY` | Code-signing identity (default `Recorder Code Signing`) |
| `DEVELOPER_DIR` | Developer directory (default `/Applications/Xcode.app/Contents/Developer`) |

### Signing and permissions

macOS ties the Screen Recording and Microphone permissions to the app's code signature. With ad-hoc signing (`codesign --sign -`) the designated requirement is the code hash, which changes on every build, so the permissions are lost after each rebuild or update.
Recorder is therefore signed with a self-signed certificate, **Recorder Code Signing** (valid until 2036-10-31). The designated requirement is then `identifier "dev.lvcas0x1.recorder" and certificate leaf = H"95786a7b…"`, which stays the same across builds as long as the same certificate is used.

- **Local builds:** `Scripts/build-app.sh` signs with `Recorder Code Signing` from your login keychain, and falls back to ad-hoc signing with a warning when it is missing. Use another identity with `SIGN_IDENTITY="My Identity" Scripts/build-app.sh`.
- **CI:** the same certificate is imported from the `SIGNING_CERTIFICATE_P12` and `SIGNING_CERTIFICATE_PASSWORD` secrets into a temporary keychain, so releases and local builds have the same designated requirement.
- Sparkle.framework is embedded in `Contents/Frameworks` without its XPC services (needed only by sandboxed apps) and every nested component is signed inside-out with the same identity ([Sparkle: sandboxing](https://sparkle-project.org/documentation/sandboxing/)). Do not enable the hardened runtime: library validation would reject the framework, because a self-signed certificate has no Team ID.

Keep a backup of the certificate (with its private key) outside the keychain. A new certificate changes the designated requirement, so every user would have to grant the permissions once more.

There is no notarization and no App Store packaging.

### DMG

```bash
Scripts/make-dmg.sh 0.1.0     # build/Recorder-0.1.0.dmg from build/Recorder.app
```

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`Scripts/inspect-video.swift` prints a recording's tracks, size, codec, duration, and per-second audio peak, and can save frames:

```bash
swift Scripts/inspect-video.swift "~/Movies/Recorder/Recording 2026-10-10 14.03.22.mp4" 2.5
```

Per-scenario verification status: [`docs/verification-checklist.md`](docs/verification-checklist.md).

## Release

`.github/workflows/release.yml` runs on every push to `main` that changes `Sources/`, `Tests/`, `Package.swift`, `Package.resolved`, the build scripts, `Scripts/Info.plist`, or the workflow itself (and on manual dispatch). It runs the tests, imports the signing certificate, builds and signs the app, packages it with `Scripts/make-dmg.sh`, writes the Sparkle update feed, publishes a GitHub release `v<version>` with `Recorder-<version>.dmg` and `appcast.xml`, and deletes all older releases and their tags.

The version keeps `Scripts/Info.plist`'s major.minor and raises the patch (`Scripts/next-version.sh`).
It runs on GitHub's `xcode-27` runner (macOS 27, Xcode 27), which is in public preview ([image details](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)). Release builds are signed with the self-signed certificate above.

### In-app updates (Sparkle)

- The app reads the feed from `SUFeedURL` = `https://github.com/lvcas0x1/recorder/releases/latest/download/appcast.xml`. Only the newest release is kept, so this URL always points to the current feed.
- `Scripts/make-appcast.sh` writes `build/appcast.xml` with the DMG's EdDSA signature from Sparkle's `sign_update`. In CI the private key comes from the `SPARKLE_ED_PRIVATE_KEY` secret; locally it is read from the login keychain (account `dev.lvcas0x1.recorder`). The public key is `SUPublicEDKey` in `Scripts/Info.plist`.
- Sparkle installs an update only if its EdDSA signature matches `SUPublicEDKey`. If the private key is lost, existing installs cannot be updated any more, so keep a backup of it.
- `CFBundleVersion` is the workflow run number, so every release has a higher build number than the previous one, which Sparkle uses to compare versions.
- Automatic checks are on (`SUEnableAutomaticChecks`); the menu also has **Update**.

## Project layout

```
Sources/
  Recording/     ScreenCaptureKit engine (segments for pause), segment joining, capture plan, output size, session state machine
  Annotation/    annotation model with undo history, drawing tools, eraser hit testing, text
  Selection/     selection model, window detection, geometry, permissions, output file naming
  Settings/      settings store, hotkey registration (Carbon)
  DesignSystem/  toolbar components
  Recorder/      app: menu bar, selection overlay, annotation overlay, frame, toolbox, notices, Preferences
Tests/           one XCTest target per library module
Scripts/         build-app.sh, make-dmg.sh, next-version.sh, Info.plist, inspect-video.swift
docs/            verification checklist, README images
openspec/        planning artifacts
```

## How pause works

`SCRecordingOutput` has no pause. Each pause ends the current piece of the recording; resuming starts a new piece on the same stream. Stop joins the pieces into one MP4 without re-encoding (`AVAssetExportPresetPassthrough`). Turning the cursor on or off during a recording also starts a new piece, because changing the stream configuration stops a running recording output. If joining fails, the pieces are kept in the output folder as hidden files (`.Recording … .segment-N.mp4`) and the error names them.

Window-mode audio: ScreenCaptureKit captures audio only from the apps in its content filter, so System Audio records only the recorded window's app. This was measured; Apple's documentation does not state it.
Hotkey registration failures at launch are written to the log (subsystem `dev.lvcas0x1.recorder`).

## Dependencies

The only package dependency is Sparkle, pinned to an exact version in `Package.swift` and `Package.resolved`. The repository contains no vendored third-party code or binaries.
The app also links Apple system frameworks from the macOS SDK. The other open-source components are the Swift toolchain and the CI tooling.

### Packages

| Package | Version | Use | License | Open source |
|---|---|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.10.1 | In-app updates (framework embedded in the app; `sign_update` in CI) | [MIT](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE) | Yes |

Sparkle's license (with the notices of the code it includes) ships in the app at `Contents/Resources/licenses/Sparkle-LICENSE`, copied from `Scripts/licenses/`, as the MIT license requires.

### Toolchain

| Component | Use | License | Open source |
|---|---|---|---|
| [Swift](https://www.swift.org/) 6 compiler and standard library | Language, `swift-tools-version:6.0`, Swift 5 language mode | [Apache 2.0 with Runtime Library Exception](https://www.swift.org/legal/license.html) | Yes |
| [Swift Package Manager](https://github.com/swiftlang/swift-package-manager) | Build and test | [Apache 2.0 with Runtime Library Exception](https://www.swift.org/legal/license.html) | Yes |
| [Xcode](https://developer.apple.com/xcode/) and the macOS SDK | Developer directory, SDK, `xctest` runner | [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf) | No |

### Apple frameworks (macOS SDK)

All are covered by the [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf) ([agreements overview](https://developer.apple.com/support/terms/)).

| Framework | Used for |
|---|---|
| [AppKit](https://developer.apple.com/documentation/appkit) | Menu-bar item, overlays, toolbox, notices, Preferences |
| [SwiftUI](https://developer.apple.com/documentation/swiftui) | Toolbar, Preferences, and onboarding views |
| [Foundation](https://developer.apple.com/documentation/foundation) | Settings, files, date formatting |
| [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) | Screen and audio capture, recording output |
| [AVFoundation](https://developer.apple.com/documentation/avfoundation) | Microphone permission, joining segments, `inspect-video.swift` |
| [Core Graphics](https://developer.apple.com/documentation/coregraphics) | Geometry, window list, drawing |
| [Core Text](https://developer.apple.com/documentation/coretext) | Text annotations |
| [Carbon](https://developer.apple.com/documentation/carbon) (`Carbon.HIToolbox`) | Global hotkey registration |
| [os](https://developer.apple.com/documentation/os/logging) | Logging (`Logger`) |
| [XCTest](https://developer.apple.com/documentation/xctest) | Unit tests (the copy bundled with Xcode) |

### Build, packaging, and CI tools

| Tool | Use | License | Open source |
|---|---|---|---|
| `codesign`, `security`, `plutil`, `diskutil` (macOS) | Signing, bundle versioning, DMG creation | Part of macOS | No |
| zsh | Build scripts | [Berkeley-style](https://zsh.sourceforge.io/FAQ/zshfaq01.html) | Yes |
| [actions/checkout](https://github.com/actions/checkout) v7.0.1 | Check out the repository in CI | [MIT](https://github.com/actions/checkout/blob/main/LICENSE) | Yes |
| [GitHub CLI](https://github.com/cli/cli) (`gh`) | Create and prune releases in CI | [MIT](https://github.com/cli/cli/blob/trunk/LICENSE) | Yes |
| GitHub-hosted runner `xcode-27` | CI machine | [GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) | No |
