# Tasks

## 1. Project scaffold

- [x] 1.1 Create `Package.swift` with modules `DesignSystem`, `Settings`, `Annotation`, `Selection`, and `Recording`, each with a test target, plus the executable `Recorder`. Use platform `.macOS("27.0")`, Swift 5 language mode, and no dependencies (design D1). Verify that `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` succeeds with placeholder sources.
- [x] 1.2 Add `Scripts/Info.plist` (`dev.lvcas0x1.recorder`, `LSUIElement`, `LSMinimumSystemVersion` 27.0, `NSMicrophoneUsageDescription`) and `Scripts/build-app.sh` adapted from Snip (design D10). Verify that `Scripts/build-app.sh` produces a signed `build/Recorder.app` (`codesign -dv build/Recorder.app` shows the identifier).
- [x] 1.3 Add `.gitignore` (`.build/`, `build/`). Verify that `.gitignore` lists both paths.

## 2. Recording engine spike (de-risk design D2/D3 first)

- [x] 2.1 In `Recording`, write a minimal `RecordingEngine` that records the main display for 5 s to MP4 with `SCStream` + `SCRecordingOutput` (H.264, `.mp4`, checked against `availableOutputFileTypes` / `availableVideoCodecTypes`). Record whether a no-op `.screen` `SCStreamOutput` is required (design Risks). Verify that the file plays in QuickTime Player and that `ffprobe` or `mdls` shows H.264 video.
- [x] 2.2 Extend the spike with `capturesAudio`, `captureMicrophone`, and `mixesAudioWithMicrophone`. Verify that the MP4 has exactly one audio track containing both system sound and voice, and no audio track when both toggles are off (`ffprobe -show_streams` or AVFoundation track count).
- [x] 2.3 Verify the window-mode filter `SCContentFilter(display:including: [target, overlay])` with `sourceRect` on a test window covered by another app's window. Verify that the overlapping window is absent from the video and that a red test rectangle drawn on the overlay is present.

- [x] 2.4 Extend the spike with pause and resume (design D11): remove and re-add `SCRecordingOutput` on a running stream to make 3 segments, then join them with `AVMutableComposition` + `AVAssetExportSession` to `.mp4`. Record whether `AVAssetExportPresetPassthrough` lists `.mp4` in `compatibleFileTypes`, and use the fallback preset if it does not. Verify that the joined file's duration ≈ the sum of the segments (`ffprobe`), that there is no gap or frozen frame at the joins, and that audio stays in sync across a join (clap test).
- [x] 2.5 Toggle `showsCursor` with `updateConfiguration` during the spike recording. Verify that the cursor is visible before the toggle and absent after it in the MP4.

## 3. Shared code copied from Snip

- [x] 3.1 Copy `DesignSystem` from Snip and copy its tests. Verify that `swift test --filter DesignSystemTests` passes.
- [x] 3.2 Copy `Selection` (`Geometry`, `SelectionModel`, `WindowDetector`, `PermissionService`, `OutputFiles`) from Snip's `Capture` module with their tests. Change `OutputFiles` to produce `Recording yyyy-MM-dd HH.mm.ss.mp4` without overwriting existing files. Verify that `swift test --filter SelectionTests` passes, including new tests for the `.mp4` name and name collisions.
- [x] 3.3 Copy `Annotation` from Snip without `Redaction`, `.mosaic`, or `.blur`, and copy the remaining tests. Verify that `swift test --filter AnnotationTests` passes and that `grep -r "mosaic\|blur" Sources/Annotation` finds nothing.

## 4. Eraser and undo history (live-annotation spec: Eraser, Undo)

- [x] 4.1 Give annotations stable IDs and change `AnnotationDocument` to an operation history (`.add` / `.remove`), with `clearAll` still not undoable (design D6). Verify with unit tests: add/undo/redo, removing several items then undoing restores them at their original order, and clearAll empties redo.
- [x] 4.2 Add `hitTest(_:tolerance:)` to rectangle, polyline, arrow, and text. Verify with unit tests for each shape: a hit on the stroke, a miss just outside width/2 + tolerance, a hit inside rotated text, and a miss outside it.
- [x] 4.3 Add `DrawingTool.eraser` to `DrawingController`: collect hits along the drag and commit one `.remove` on pointer up, or nothing when there are no hits, and expose pending removals for preview. Verify with unit tests that cover the spec scenarios "Erase by click", "Erase by drag", "Undo erase", and "Nothing under eraser".

## 5. Settings and hotkeys (app-shell spec)

- [x] 5.1 Copy `Settings` and change `HotkeyAction` to `fullScreen`, `window`, and `area` with defaults Control-Shift-1/2/3. `HotkeyStore` stores optional combos where explicit `nil` means removed, with `restoreDefault` (design D7). Verify with unit tests for the defaults, removed after reload, restore default, and rebind persistence.
- [x] 5.2 Add `HotkeyManager.unbind(_:)` and make `start()` skip removed actions. Verify with a unit test that a removed action is not registered. Manually verify that Control-Shift-1 reaches the frontmost app after removal.
- [x] 5.3 Add `SettingsStore` fields: resolution (default 1080p), systemAudio (on), microphone (off), recordCursor (on), and outputFolder (`~/Movies/Recorder`) (design D9). Verify with unit tests for the defaults and persistence using a separate `UserDefaults` suite.

## 6. Recording core (screen-recording spec)

- [x] 6.1 Implement `OutputSize.fit(nativePixels:preset:)` (design D4). Verify with unit tests for the three spec scenarios plus odd-size inputs, which must give even output.
- [x] 6.2 Implement `CapturePlan`, a pure mapping from mode, area, display, and settings to the filter kind, `sourceRect`, output size, and audio, cursor, and codec flags (design D2/D3). Verify with unit tests for each mode, including window mode including only the target and the overlay, and own windows excluded.
- [x] 6.3 Turn the spike into `RecordingEngine`: start, stop, write to a temp file and rename it to the final name, report delegate failures, and keep a playable partial file on failure. Verify by recording, stopping, and checking that the final file exists with the spec name. Also verify that making the output folder read-only produces the "Folder not writable" error without starting a recording.
- [x] 6.4 Add pause, resume, and segment joining to `RecordingEngine` (design D11), and an `ElapsedTime` value (sum of finished segments plus the current one). Verify with unit tests for `ElapsedTime`. Manually verify the spec scenarios "Paused time left out", "Stop while paused", and "Audio while paused". Also verify that a forced export failure keeps the segments and shows an error.
- [x] 6.5 Add a live cursor toggle to `RecordingEngine` (`updateConfiguration` with `showsCursor`), saved as `recordCursor`. Verify manually with "Cursor off in each mode" in all three modes, "Toggle during recording", and "Choice kept".
- [x] 6.6 Implement `RecordingSessionController`, the state machine idle → selecting → starting → recording ⇄ paused → finishing → idle. It ignores starts while busy and turns a shortcut press during recording or pause into stop. Verify with unit tests using a fake engine for "One recording at a time", "Shortcut stops a recording" (also from paused), pause/resume transitions, and failure-path transitions.
- [x] 6.7 Add microphone permission handling (design D8): check or request before recording, and when denied record without the mic and post a notice. Verify manually by denying Microphone in System Settings and confirming that the recording still saves and the notice appears.

## 7. On-screen UI (screen-recording and live-annotation specs)

- [x] 7.1 Implement the selection overlay for window mode (hover highlight, click to pick) and custom area mode (drag, handles, pixel-size label, Return or Record button, Esc to cancel, clamped to one display) (design D5). Verify manually against the spec scenarios "Pick a window", "Select and record", "Adjust before recording", "Area limited to one display", and "Cancel".
- [x] 7.2 Implement the 1 pt recording frame panel for window and area modes only (design D5). Verify that the frame appears around the area, does not appear in full screen mode, is absent from every frame of the MP4 (step through it in QuickTime), and disappears on stop.
- [x] 7.3 Implement the annotation overlay panel: covers the area, click-through when no tool is active, draws the document and the draft, hides pending eraser removals, and becomes key while a tool is active. Verify manually that a click passes through to an app with no tool active, a stroke is drawn with the pencil, and Esc leaves the tool. If key status fails, apply the fallback from design Risks and record the result in README.
- [x] 7.4 Build the toolbox SwiftUI view from Snip's toolbar and style row. It has a fixed control group (Pause/Resume, Stop, elapsed time), tools rectangle, line, arrow, pencil, marker, text, and eraser, Undo, Redo, Clear All, and the cursor toggle. It is draggable and placed per design D5. Verify manually against the live-annotation scenarios "Toolbox appears", "Move toolbox", "Buttons always shown", "Pause from toolbox", "Resume from toolbox", "Draw while paused", "Choose tool", "Palette color", "Width by key", and "Clear all".
- [x] 7.5 Wire keyboard handling in the overlay (Tab line/arrow, 1/2 width, scroll width, ⌘Z, ⌘Y, ⇧⌘Z, text input including Japanese IME). Verify manually by drawing a line strip, toggling with Tab, and typing Japanese text.

## 8. App shell (app-shell spec)

- [x] 8.1 Implement the `AppDelegate` with `.accessory` activation policy and a status item menu (three record actions with shortcut display, Resolution submenu, Record Cursor, System Audio, and Microphone toggles, Open Recordings Folder, Preferences, Quit). Verify that the app launches with no Dock icon and that the menu matches the spec "Menu" scenarios.
- [x] 8.2 Show the recording indicator (recording or paused icon, mm:ss recorded time, and a progress state while joining segments) and stop on click. Verify manually with "Indicator while recording", "Indicator while paused", and "Stop from menu bar".
- [x] 8.3 Copy the Screen Recording onboarding from Snip and gate every mode start on permission. Verify by resetting with `tccutil reset ScreenCapture dev.lvcas0x1.recorder` and confirming the "Permission missing" and "Grant detected" scenarios.
- [x] 8.4 Build the Preferences window: three shortcut recorders, each with Remove and Restore Default buttons and an error display, plus resolution, audio toggles, Record Cursor toggle, and output folder picker. Verify the scenarios "Rebind", "Registration fails", "Remove", "Restore default", "Change output folder", and "Persist" after relaunch.
- [x] 8.5 Implement the saved-file HUD with Show in Finder (design D8). Verify that it appears after stop, reveals the file, and closes after 5 s.

## 9. Documentation and integration

- [x] 9.1 Write `README.md`: requirements (macOS 27, Xcode), build and run, signing and permissions, usage per mode, shortcuts, toolbox, and known limitations (window not followed, single-display area). Verify that the documented build command runs as written.
- [x] 9.2 Run the end-to-end check in each mode at 720p, 1080p, and 4K with both audio toggles on: draw, erase, undo, pause and resume twice, toggle the cursor, and stop. Verify in each MP4 the expected dimensions (`ffprobe`), a single mixed audio track, annotations visible in the video, and the toolbox and frame absent. Record the results in `docs/verification-checklist.md` with one row per spec scenario.
- [x] 9.3 Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` and `openspec validate add-screen-recorder-app --strict`. Verify that both pass.

## Workflow follow-up

- Archive the change with `/opsx:archive` after the verification checklist is complete.
