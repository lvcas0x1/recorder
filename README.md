# Recorder

A native macOS menu-bar screen recorder (Swift, AppKit + SwiftUI). It records the full screen, a window, or a custom area to MP4, with live annotation while recording.
The planning artifacts are in `openspec/changes/add-screen-recorder-app/` (proposal, specs, design, tasks).

## Requirements

- macOS 27 or later. Recording mixes the microphone into the system audio with `SCRecordingOutputConfiguration.mixesAudioWithMicrophone`, which needs macOS 27 ([Apple documentation](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration/mixesaudiowithmicrophone)).
- Xcode (built and tested with Xcode 27.0, Swift 6.4). The scripts set `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer` unless you override it.
- No third-party packages.

## Build and run

```bash
Scripts/build-app.sh          # release build -> build/Recorder.app
Scripts/build-app.sh debug    # debug build
open build/Recorder.app
```

The app has no Dock icon. Look for the record icon in the menu bar. If you use a menu-bar manager (Ice, Bartender, and so on), set Recorder to always show: while recording, the menu-bar item shows the time, and clicking it stops the recording.

### Signing and permissions

macOS ties the Screen Recording permission to the app's code signature. `Scripts/build-app.sh` signs with a local code-signing identity named `Screenshot Dev` when one exists in your keychain, so the permission survives rebuilds. Otherwise it falls back to ad-hoc signing with a warning. Use another identity with `SIGN_IDENTITY="My Identity" Scripts/build-app.sh`.

- **Screen Recording** (System Settings > Privacy & Security > Screen & System Audio Recording) is required. Without it, no recording starts, and an onboarding window explains what to enable.
- On the first recording, macOS may ask whether Recorder may bypass the system's private window picker. Choose Allow.
- **Microphone** is asked for the first time you record with Microphone turned on. If it is denied, the recording continues without the microphone and a notice says so.

There is no notarization and no App Store packaging.

### Releases

`.github/workflows/release.yml` runs on every push to `main` that changes the app or its packaging, and can also be run by hand. It runs the tests, builds the app, packages it with `Scripts/make-dmg.sh`, and publishes a GitHub release `v<version>` with `Recorder-<version>.dmg`. The version keeps `Scripts/Info.plist`'s major.minor and raises the patch (`Scripts/next-version.sh`). Only the newest release is kept; older releases and their tags are deleted.

It runs on GitHub's `xcode-27` runner (macOS 27, Xcode 27), which is in public preview ([image details](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)). Release builds are ad-hoc signed, so the Screen Recording and Microphone permissions must be granted again after each update.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`Scripts/inspect-video.swift` prints a recording's tracks, size, codec, duration, and per-second audio peak, and can save frames:

```bash
swift Scripts/inspect-video.swift "~/Movies/Recorder/Recording 2026-10-10 14.03.22.mp4" 2.5
```

Per-scenario verification status: [`docs/verification-checklist.md`](docs/verification-checklist.md).

## Using it

| Mode | Default shortcut | How |
|---|---|---|
| Full screen | ⌃⇧1 | Records the display under the mouse pointer right away. |
| Window | ⌃⇧2 | Move over a window (it is highlighted) and click it. |
| Area | ⌃⇧3 | Drag a rectangle, adjust it with the handles or by dragging it, then press Return or click Record. |

- Esc or a right-click cancels a selection.
- Pressing any of the three shortcuts while recording (or while paused) stops the recording.
- The same actions are in the menu-bar menu.

In window and area modes, a 1 pt red frame marks the recorded area. The frame, the toolbox, and the notices never appear in the video.

### Toolbox

A toolbox appears at the bottom right of the recorded area, right-aligned with it (at the bottom center of the display in full screen mode). Drag it by its grip (≡). The color and width row opens on the side that stays on screen and does not cover the recorded window or area (below when possible). The toolbox never appears in the video, even where it covers the recorded window.

- **Pause / Resume** and **Stop**, with the recorded time. Paused time is left out of the video.
- **Tools:** rectangle, line, arrow, pencil, marker, text, and eraser.
  - Line: click points and right-click to finish, or drag for a single line. **Tab** switches between line and arrow.
  - Text: click to place, type, then press **Esc** to finish. Drag a corner to scale and the top handle to rotate; hold **Shift** while rotating to snap to right angles, or when grabbing a corner to level the text.
  - Eraser: click a drawing, or drag across several drawings, to remove them. One erase is one undo step.
- Color palette, custom color, alpha (0–255), and pen width (1–24 pt; slider, scroll wheel, or the **1** / **2** keys).
- **Undo** (⌘Z), **Redo** (⌘Y), and **Clear All** (⇧⌘Z, cannot be undone).
- **Cursor:** whether the mouse cursor is recorded. It can be switched during a recording, and the choice is kept for later recordings.

While no tool is active, clicks and typing go to the apps under the recorded area. While a tool is active, the mouse draws. Press Esc or click the tool again to stop drawing. Drawings appear in the video from the moment they are drawn and are removed when the recording stops.

### Output

- MP4 with H.264 video, saved to `~/Movies/Recorder` (configurable). The file name is `Recording yyyy-MM-dd HH.mm.ss.mp4`, and existing files are never overwritten.
- **Resolution:** 720p, 1080p, or 4K. The recorded area keeps its aspect ratio and is scaled to fit inside 1280×720, 1920×1080, or 3840×2160. It is never scaled above its native pixel size, and both sides are even numbers.
- **Audio:** System Audio and Microphone can each be turned on or off. When both are on, they are mixed into one audio track. Sound played by Recorder itself is never recorded.
- After saving, a notice shows the file name with a Show in Finder button.

### Preferences

Shortcuts (change, remove, or restore the default for each mode), resolution, Record Cursor, System Audio, Microphone, and the output folder. Appearance follows the system light or dark setting and accent color.

## Project layout

```
Sources/
  Recording/     ScreenCaptureKit engine (segments for pause), segment joining, capture plan, output size, session state machine
  Annotation/    annotation model with undo history, drawing tools, eraser hit testing, text
  Selection/     selection model, window detection, geometry, permissions, output file naming
  Settings/      settings store, hotkey registration (Carbon)
  DesignSystem/  toolbar components
  Recorder/      app: menu bar, selection overlay, annotation overlay, frame, toolbox, notices, Preferences
Scripts/         build-app.sh, make-dmg.sh, next-version.sh, Info.plist, inspect-video.swift
docs/            verification checklist
```

## How pause works

`SCRecordingOutput` has no pause. Each pause ends the current piece of the recording; resuming starts a new piece on the same stream. Stop joins the pieces into one MP4 without re-encoding (`AVAssetExportPresetPassthrough`). Turning the cursor on or off during a recording also starts a new piece, because changing the stream configuration stops a running recording output. If joining fails, the pieces are kept in the output folder as hidden files (`.Recording … .segment-N.mp4`) and the error names them.

## Known limitations

- **Window mode, moving windows:** the recorded area stays where the window was when recording started. A window that is moved or resized is not followed.
- **Window mode, audio:** System Audio records only the sound of the recorded window's app. ScreenCaptureKit captures audio only from the apps in its content filter; this was measured, and Apple's documentation does not state it.
- **Area mode:** the area is limited to one display.
- Mosaic and blur (in Snip) are not available while recording.
- Behavior with two displays has not been checked on physical hardware.
- The default shortcuts may conflict with other apps' shortcuts. If one cannot be registered at launch, the failure is written to the log (subsystem `dev.lvcas0x1.recorder`). Change or remove it in Preferences, which shows an error if a new combination cannot be registered.
