# Design

## Context

- The repository is empty apart from `openspec/`. See proposal.md (Why) for the motivation.
- Reference implementation: Snip (`~/Documents/github/snip`), a SwiftPM menu-bar app (Swift 6 tools, Swift 5 language mode, macOS 14, no third-party packages). It has these modules:
  - `Annotation`: `Annotation` protocol, `AnnotationDocument` (undo/redo stack of items), `DrawingController` (pointer input to shapes, text editing), shapes, `Redaction`.
  - `Settings`: `HotkeyManager` (Carbon `RegisterEventHotKey`), `HotkeyStore`, `SettingsStore`.
  - `DesignSystem`: `FloatingToolbar`, `ToolbarButton`, interface font.
  - `Capture`: `Geometry`, `SelectionModel`, `WindowDetector`, `PermissionService`, `OutputFiles`.
  - `Snip`: the app target, with `SnipToolbar.swift` (SwiftUI toolbar plus a style row) and `SnipSession.swift` (full-screen overlay panel at `.screenSaver` level).
  - Snip is built by `Scripts/build-app.sh`. The script signs the app with the `Screenshot Dev` identity so the Screen Recording permission survives rebuilds.
- Toolchain on the dev Mac: macOS 27.0.1, Apple Swift 6.4, Xcode at `/Applications/Xcode.app`.
- The minimum OS is macOS 27, chosen by the user. Reason: `SCRecordingOutputConfiguration.mixesAudioWithMicrophone` is available from macOS 27.0 (https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration/mixesaudiowithmicrophone).

## Goals / Non-Goals

**Goals:**
- Let the system write the file (ScreenCaptureKit recording output) so there is no custom encoding pipeline.
- Copy Snip's annotation code with small, testable changes: an eraser hit test and an undo history that records operations instead of single items.
- Keep pure logic (output-size math, selection, hit testing, hotkey store, file naming) in library modules with unit tests. Keep AppKit and ScreenCaptureKit code in thin layers.

**Non-Goals:**
- A countdown, webcam overlay, trimming or editing, GIF output.
- Following a window that moves during a recording (see the spec scenario "Window moves").
- A custom area that spans two displays.
- Mosaic and blur during recording.
- Notarization, App Store, and DMG packaging.

## Decisions

### D1. Package layout
SwiftPM package `Recorder`. Each module gets a test target, following Snip's `Package.swift` pattern.
- `DesignSystem`, `Settings`, `Annotation`: copied from Snip and adapted. `Redaction.swift` and the mosaic and blur tools are dropped.
- `Selection`: copied from Snip's `Capture` module: `Geometry`, `SelectionModel`, `WindowDetector`, `PermissionService`, `OutputFiles`.
- `Recording` (new): output-size math, content-filter planning, the `SCStream` + `SCRecordingOutput` wrapper, and microphone permission.
- `Recorder`: executable target with the AppKit shell, overlay, frame, toolbox, Preferences, and onboarding.

Platform: `.macOS("27.0")` (the string form, so the build does not depend on whether this PackageDescription version has a `.v27` constant). Bundle ID `dev.lvcas0x1.recorder`, `LSUIElement = true`, `NSMicrophoneUsageDescription`.
Alternative considered: a shared package used by Snip and the recorder. The user rejected it.

### D2. Recording engine: `SCStream` + `SCRecordingOutput`
`SCRecordingOutput` (macOS 15+, https://developer.apple.com/documentation/screencapturekit/screcordingoutput) is added to the stream with `SCStream.addRecordingOutput(_:)` (https://developer.apple.com/documentation/screencapturekit/scstream/addrecordingoutput(_:)). Its configuration (https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration):
- `outputURL`: a temporary file in the output folder. It is renamed to the final name when the recording finishes.
- `outputFileType = .mp4`.
- `videoCodecType = .h264`. Before setting either value, check that it is listed in `availableOutputFileTypes` / `availableVideoCodecTypes`.
- `mixesAudioWithMicrophone = true` when both audio toggles are on.

`SCRecordingOutputDelegate` callbacks `recordingOutputDidStartRecording`, `recordingOutputDidFinishRecording`, and `recordingOutput(_:didFailWithError:)`, together with `SCStreamDelegate.stream(_:didStopWithError:)`, drive the state machine idle → selecting → starting → recording ⇄ paused → finishing → idle. Recording failures follow the spec.

`SCStreamConfiguration` (https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration):
- `width` and `height` come from D4.
- `sourceRect` is the recorded area, in display-local points.
- `scalesToFit = true`, `preservesAspectRatio = true`.
- `minimumFrameInterval = 1/60` (at most 60 fps).
- `showsCursor` follows the setting.
- `capturesAudio` follows System Audio, with `excludesCurrentProcessAudio = true`.
- `captureMicrophone` follows Microphone. `microphoneCaptureDeviceID = nil` uses the default microphone.

`showsCursor` is changed during a recording with `SCStream.updateConfiguration(_:completionHandler:)` (https://developer.apple.com/documentation/screencapturekit/scstream/updateconfiguration(_:completionhandler:)). The SDK header says a configuration update stops a running recording output (`SCStream.h`, `removeRecordingOutput`: "In case client update the stream configuration during recording, recording will be stopped as well"). So a toggle while recording finishes the current segment, updates the configuration, and starts a new segment, reusing the D11 mechanism. Spike 2.5 confirmed this.

Alternative considered: `AVAssetWriter` fed with `.screen`, `.audio`, and `.microphone` sample buffers. It would allow macOS 15, but the two audio sources would have to be mixed and synchronized in the app. The user chose macOS 27 instead.

### D3. What each mode captures (content filter)
The recorder's own windows are kept out of the video by the filter. `NSWindow.sharingType` is not used for this. The annotation overlay is the only window of the app that the filter includes.

| Mode | Filter | `sourceRect` |
|---|---|---|
| Full screen | `SCContentFilter(display:excludingApplications: [this app], exceptingWindows: [overlay])` | whole display |
| Custom area | same as full screen | selected rect |
| Window | `SCContentFilter(display:including: [target window, overlay])` | target window frame at start |

Filter API: https://developer.apple.com/documentation/screencapturekit/sccontentfilter. Measured during implementation (the docs do not state it): system audio follows the filter's applications, so window mode records only the target window's app. The user accepted this, and the spec says so. Window mode uses a display filter that includes only those two windows, so overlapping windows of other apps are left out and the overlay can still be composited over the window. `init(desktopIndependentWindow:)` is rejected because it cannot include the overlay. Before the filter is built, the overlay is put on screen, then `SCShareableContent` is fetched and the overlay is matched by `SCWindow.windowID == NSWindow.windowNumber`.

### D4. Output size
This is a pure function `OutputSize.fit(nativePixels:preset:)`.
- `nativePixels` = recorded area in points × display scale (`NSScreen.backingScaleFactor`).
- `factor = min(1, boxW / w, boxH / h)` for the box 1280x720, 1920x1080, or 3840x2160.
- Each dimension is `floor(x * factor)`, then rounded down to an even number.

It is unit-tested with the spec scenarios: 2880x1620 → 1920x1080, 1600x1200 → 960x720, and 1000x500 → 1000x500.

### D5. Windows on screen
- **Selection overlay**: adapted from Snip's `OverlayPanel` at `.screenSaver` level. Window mode highlights the window under the pointer using `WindowDetector`; custom area mode uses `SelectionModel` with handles, a pixel-size label, and a Record button. The overlay is closed before recording starts.
- **Annotation overlay**: a transparent borderless `NSPanel` that covers exactly the recorded area, at `.floating` level. `ignoresMouseEvents = (tool == nil)` gives click-through. Because the panel covers only the area, drawing is limited to it. It draws `AnnotationDocument.draw(in:draft:)` with the same coordinate mapping as Snip. It is a non-activating panel, so it can become key while a tool is active (for text, Esc, Tab, ⌘Z, and the 1/2 keys) without activating the app.
- **Frame**: a transparent panel 1 pt larger than the area on each side. It strokes a 1 pt `systemRed` line on its inside edge and ignores mouse events. The filter excludes it.
- **Toolbox**: a non-activating `NSPanel` hosting a SwiftUI view built from Snip's `SnipToolbarView` and `StyleRow`. Row 1 starts with a fixed control group: Pause/Resume (`pause.fill` / `play.fill`), Stop (`stop.fill`), and the elapsed time. It is followed by the tools including Eraser, Undo, Redo, Clear All, and a cursor toggle (`cursorarrow` / `cursorarrow.slash`). Snip's Copy, Save, and Pin buttons are removed. The control group is never hidden. In window and area modes it is right-aligned with the area: below it when both rows fit there, else above it, else wherever the main row fits, else inside its bottom-right corner. The style row opens on a side that fits on the screen and does not cover the area, preferring below; this is re-evaluated after a drag. In full screen mode the toolbox is placed at the bottom center of the display, and the style row opens above it. The panel is sized for both rows and never resized, so showing the style row does not move or flicker the window; its transparent part passes clicks through. It can be dragged by its grip.

### D6. Eraser and undo history
- The `Annotation` protocol gets `func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool`:
  - Rectangle: distance to the outline.
  - Polyline and arrow: distance to a segment ≤ width/2 + tolerance.
  - Text: the point lies inside the rotated box.
- `AnnotationDocument` changes from a stack of items to a stack of operations: `.add(item)` or `.remove([(index, item)])`. Undo reverts the operation and Redo reapplies it. `clearAll` still empties both stacks.
- An eraser gesture collects the hits along the drag path, with tolerance = eraser radius 6 pt. On release it commits one `.remove` operation, and nothing when there were no hits. While dragging, the overlay hides the items that will be removed.
- Annotations get stable IDs (`UUID`) so removal does not depend on indices that shift.

### D7. Hotkeys
- `HotkeyAction` = `fullScreen`, `window`, `area`.
- Defaults are Control-Shift-1/2/3 (`kVK_ANSI_1...3`, `controlKey | shiftKey`). These avoid the Option-only combinations that Snip documents as rejected by macOS 15.0 and 15.1, and they avoid the system's Shift-Command-3/4/5.
- `HotkeyStore` stores `[HotkeyAction: KeyCombo?]`. An explicit `nil` means the shortcut was removed, so it is not filled again from the defaults on load. `HotkeyManager.unbind(_:)` unregisters the shortcut, and Restore Default rebinds the default.
- The handler sends the action to the session controller. That controller ignores the action while selecting and stops the recording while recording.

### D8. Permissions and notices
- Screen Recording: `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`, and Snip's onboarding window. Found during implementation: the preflight answer stays the same for the life of the process. tccd logs showed the running app stopped asking after its first query; Apple's docs do not state this. So the onboarding and the start gate also ask ScreenCaptureKit directly (`SCShareableContent`), and a success is remembered.
- Microphone: `AVCaptureDevice.authorizationStatus(for: .audio)` and `requestAccess(for: .audio)` before a recording with Microphone on. If access is denied, `captureMicrophone` is set to false and a notice is shown. Found during implementation: after `tccutil reset Microphone`, the running app still got "authorized", and the stream's own prompt was denied. The session then hung while finishing, because no finish callback came. So the engine now waits for start and finish callbacks with a 5 s timeout, records callbacks that arrive before it waits, and retries a failed start once without the microphone (with the same notice).
- The saved-file notice is a small HUD panel near the menu-bar item with a Show in Finder button that closes itself after 5 s. It does not use `UserNotifications`, so no notification permission is needed.

### D9. Settings
`SettingsStore` in `UserDefaults` holds the resolution preset (default 1080p), systemAudio (default on), microphone (default off), recordCursor (default on, shared by the menu toggle, Preferences, and the toolbox toggle), and outputFolder (default `~/Movies/Recorder`, created on first use). File naming copies Snip's `OutputFiles` collision logic and adds `.mp4`.

### D11. Pause and resume by segments
`SCRecordingOutput` has no pause. Its only lifecycle calls are `SCStream.addRecordingOutput(_:)` and `removeRecordingOutput(_:)` (macOS 15+, https://developer.apple.com/documentation/screencapturekit/scstream/removerecordingoutput(_:)).
- **Pause**: `removeRecordingOutput` finishes the current segment file (`<temp>-<n>.mp4`). The stream keeps running, so the frame, overlay, and toolbox stay unchanged and resume is fast.
- **Resume**: a new `SCRecordingOutput` for segment n+1 is added to the same stream with the same configuration.
- **Stop**: the last segment is finished.
  - With one segment, it is renamed to the final name.
  - With several segments, they are appended in order into an `AVMutableComposition` (https://developer.apple.com/documentation/avfoundation/avmutablecomposition) at running offsets, so there are no gaps. The composition is exported with `AVAssetExportSession` to `.mp4` using `AVAssetExportPresetPassthrough` (https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough), which avoids re-encoding. The segments are deleted only after a successful export.
  - While joining, the menu-bar item shows a progress state. If the export fails, the segments are kept in the output folder and the error names them.
- **Elapsed time**: the sum of finished segments' `recordedDuration` plus the time of the current segment. It is pure logic and unit-tested.

Alternatives considered:
- Stopping and restarting the whole stream: slower to resume, and it re-creates the filter.
- Dropping sample buffers in an `AVAssetWriter` pipeline: rejected with D2.

### D10. Build
`Scripts/build-app.sh` is adapted from Snip and builds `build/Recorder.app`. It signs with the same `Screenshot Dev` identity when that identity exists, because the TCC grant is tied to the code signature.

## Risks / Trade-offs

- [`SCRecordingOutput` might need at least one `SCStreamOutput`.] → Resolved by spike 2.1: no stream output is needed.
- [The annotation overlay is visible in the window list, and other apps' screenshots could capture it.] → Accepted. It exists only during a recording.
- [A non-activating panel may not get key status reliably, so text input or Esc might go to the frontmost app.] → Test early. If it fails, briefly activate the app while a tool is active and restore the previous app when no tool is active.
- [In window mode, the target window may change Space or go full screen.] → Recording continues with the area fixed. This is documented as a limitation.
- [4K60 H.264 may drop frames on slower Macs.] → The cap is 60 fps. If dropped frames show up in testing, change `minimumFrameInterval` to 1/30 for 4K.
- [`AVAssetExportPresetPassthrough` may not support `.mp4` output for these segments.] → Spike 2.4: on macOS 27.0.1 passthrough lists `public.mpeg-4`, and the joined file plays with no gap and with A/V sync kept across joins. Kept as a safeguard: Spike task 2.4 checks it with `AVAssetExportSession.compatibleFileTypes`. The fallback is `AVAssetExportPresetHighestQuality`, which re-encodes and is slower.
- [Small audio/video offsets at segment joins, because each segment's tracks may start at slightly different times.] → Insert each segment by its video track's time range, and check A/V sync across a join in the end-to-end test.
- [A pause during a failing stream leaves partial segments.] → On failure, join whatever segments are complete. If joining fails, keep them, as with the export failure.
- [Control-Shift-digit may conflict with other apps' shortcuts.] → Registration failure is logged and shown in Preferences. The user can rebind or remove the shortcut.
- [Copied code drifts from Snip.] → Accepted. The user chose to copy the code.

## Migration Plan

New app. No migration. Rollback means deleting the app.

## Open Questions

- Is the frame color fixed (`systemRed`) or the accent color? This can change later without affecting the specs.
