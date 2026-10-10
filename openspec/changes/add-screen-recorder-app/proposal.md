# Proposal

## Why

The user needs a simple native macOS screen recorder that lives in the menu bar, records a full screen, a window, or a custom area to MP4, and supports live annotation while recording. It should use the same annotation tools as the existing Snip app (`~/Documents/github/snip`) so both apps work the same way. The repository is empty, so this change creates the whole app.

## What Changes

- New native Swift menu-bar app (AppKit + SwiftUI, Swift Package Manager, no third-party packages). It has a menu-bar icon and no Dock icon. Minimum macOS version: 27.
- Three recording modes:
  - **Full screen**: records the display under the mouse pointer.
  - **Window**: the user clicks a window to record it.
  - **Custom area**: the user drags a rectangle, which can be adjusted before recording starts.
- Three output resolutions: 720p, 1080p, and 4K. The recorded area keeps its aspect ratio and is scaled to fit inside 1280x720, 1920x1080, or 3840x2160. It is never scaled above its native pixel size.
- In window and custom-area modes, a 1 px frame is drawn around the recorded area while recording. The frame does not appear in the video.
- Each mode has a default global shortcut. The user can change or remove each shortcut in Preferences.
- Optional system audio and microphone audio, mixed into one audio track.
- In every mode, the user chooses whether the mouse cursor is recorded: from the menu, in Preferences, or live from the toolbox.
- Pause, resume, and stop with two buttons that are always in the toolbox. Paused time is left out of the video.
- The output is an MP4 file saved to a configurable folder.
- A toolbox is shown while recording, for live annotation over the recorded area. Besides the Pause/Resume and Stop buttons, it has Snip's rectangle, line, arrow, pencil, marker, and text tools, plus a new eraser. Snip's color, width, and alpha controls and its undo, redo, and clear all are included. Annotations appear in the video; the toolbox does not. Snip's mosaic and blur tools are not included.
- Snip's Annotation, hotkey (Settings), and DesignSystem code is copied into this repository and adapted. The two apps do not share a package.

## Capabilities

### New Capabilities
- `app-shell`: menu-bar presence without a Dock icon, the menu, permission onboarding (Screen Recording, Microphone), global shortcuts that can be changed or removed, and saved preferences.
- `screen-recording`: the three recording modes and how a target is selected, output resolution, the 1 px recording frame, cursor and audio capture, starting, pausing, resuming, and stopping, and MP4 output.
- `live-annotation`: the toolbox shown while recording, the drawing tools, the eraser, style controls, undo, redo, and clear all, and annotations appearing in the recording.

### Modified Capabilities
- None. `openspec/specs/` contains no capabilities yet.

## Impact

- New code in this repository: `Package.swift`, `Sources/`, `Tests/`, `Scripts/` (build, Info.plist), and `README.md`.
- System frameworks: ScreenCaptureKit (`SCStream`, `SCRecordingOutput`), AVFoundation (`AVMutableComposition`, `AVAssetExportSession` to join paused segments), AppKit, SwiftUI, Carbon (global hotkeys).
- Permissions: Screen Recording, and Microphone when microphone capture is turned on. Info.plist needs `NSMicrophoneUsageDescription`.
- Snip is not modified. Code is copied from it.
- The app runs only on macOS 27 or later, because mixing the microphone into the recording output requires macOS 27.
