# Verification checklist

Status of every scenario in `openspec/changes/add-screen-recorder-app/specs/`, checked on macOS 27.0.1, Swift 6.4, one Retina display (1800×1169 pt, scale 2), on 2026-10-10.

- **Verified (app):** exercised in the running app (scripted mouse and keyboard input), and the output checked with `Scripts/inspect-video.swift` or screenshots.
- **Verified (unit):** covered by `swift test`.
- **Pending (manual):** not yet verified; needs a person, or a change to system settings.

## app-shell

| Requirement | Scenario | Status | Evidence |
|---|---|---|---|
| Menu-bar app without Dock icon | Launch | Verified (app) | `.accessory` activation policy; the menu-bar item exists (accessibility query); no Dock icon. |
| Menu | Open menu | Verified (app) | Menu items read through accessibility: three record actions with ⌃⇧1/2/3, Resolution, Record Cursor, System Audio, Microphone, Open Recordings Folder, Preferences, Quit. |
| Menu | Removed shortcut in menu | Verified (app) | After removal, the item read "Record Full Screen" with no shortcut. |
| Menu | Open recordings folder | Pending (manual) | Finder was not checked. |
| Recording indicator | Indicator while recording | Verified (app) | Item title " 00:24" during recording. The icon was not seen: a menu-bar manager hides the item on the test machine. |
| Recording indicator | Indicator while paused | Verified (app) | Title stayed " 00:41" across 3 s of pause. |
| Recording indicator | Stop from menu bar | Verified (app) | Clicking the item stopped the recording and saved the file. |
| Default shortcuts | Default shortcut starts a mode | Verified (app) + unit | ⌃⇧1/2/3 started full screen, window, and area mode. |
| Change shortcuts | Rebind | Verified (app) + unit | Area rebound to ⌃⌥R: ⌃⌥R started area mode and ⌃⇧3 did nothing. |
| Change shortcuts | Registration fails | Verified (unit) | `HotkeyManagerTests.testFailedRebindKeepsPreviousCombo`. The Preferences error text was not seen. |
| Remove shortcuts | Remove | Verified (app) + unit | ⌃⇧1 did not trigger Recorder after removal. Whether the frontmost app received it was not observable in TextEdit. |
| Remove shortcuts | Removed after relaunch | Verified (app) + unit | Still removed after relaunch. |
| Remove shortcuts | Restore default | Verified (app) + unit | ⌃⇧1 worked again. |
| Shortcut stops a recording | Stop with shortcut | Verified (app) + unit | ⌃⇧1 and ⌃⇧2 stopped recordings; `RecordingSessionTests` covers the paused case too. |
| Screen Recording permission onboarding | Permission missing | Verified (app) | After `tccutil reset ScreenCapture dev.lvcas0x1.recorder`, ⌃⇧1 started nothing (no file) and the onboarding window opened. |
| Screen Recording permission onboarding | Grant detected | Verified (app) | Granted in System Settings without relaunching: onboarding switched to "Permission granted" and ⌃⇧1 recorded in the same process. |
| Microphone permission | Microphone denied | Verified (app) + unit | Microphone denied in the system prompt, app relaunched, Microphone on: the "Microphone not recorded" notice appeared and the recording was saved without the microphone. The case where access is revoked while the app runs is handled by retrying without the microphone, but that path was not reproduced. |
| Preferences | Change output folder | Pending (manual) | The folder picker was not exercised. |
| Preferences persistence | Persist | Verified (app) + unit | Settings and shortcuts kept across relaunch; `SettingsStoreTests`. |
| Follow system theme | Dark appearance | Pending (manual) | Uses system materials and colors; not switched during testing. |

## screen-recording

| Requirement | Scenario | Status | Evidence |
|---|---|---|---|
| Full screen mode | Start full screen | Verified (app) | Recorded the main display. Two displays were not tested. |
| Window mode | Pick a window | Verified (app) | Hover highlight and click on TextEdit; the video shows only that window. |
| Window mode | Overlapping window excluded | Verified (spike) | Spike 2.3: a window placed over the target was absent from the video. |
| Window mode | Window moves | Verified (app) | TextEdit moved by (+200, +150) during recording: the recorded area stayed put, the window moved inside it, and the uncovered part is black. |
| Custom area mode | Select and record | Verified (app) | Drag, then Return. |
| Custom area mode | Adjust before recording | Verified (app) | Handle drag; label changed from 1200 × 800 to 1400 × 900. |
| Custom area mode | Area limited to one display | Verified (unit) | `SelectionModelTests.testDragIsClampedToBounds`. Only one display was available. |
| Cancel selection | Cancel | Verified (app) | Esc closed the selection; no file. |
| Output resolution | 16:9 display at 1080p | Verified (unit) | `OutputSizeTests`. In the app, 3600×2338 at 1080p gave 1662×1080. |
| Output resolution | Non-16:9 area at 720p | Verified (unit) + app | 1600×1200 window at 720p gave 960×720. |
| Output resolution | No upscaling | Verified (unit) + app | 1200×800 area at 1080p and 4K stayed 1200×800. |
| Recording frame | Frame shown | Verified (app) | Red 1 pt frame on screen in area and window modes. |
| Recording frame | Frame not recorded | Verified (app) | No frame in any sampled video frame. |
| Recording frame | Frame removed | Verified (app) | Gone after stop. |
| Own interface excluded from video | Toolbox not recorded | Verified (app) | Full screen 4K: no toolbox at the bottom center in the video. |
| Cursor in recording | Cursor off in each mode | Verified (app) | End-to-end runs in all three modes toggled the cursor. |
| Cursor in recording | Cursor on | Verified (app) | Cursor visible in the area and full screen videos. |
| Cursor in recording | Toggle during recording | Verified (spike + app) | Spike 2.5: visible before the toggle, absent after. |
| Cursor in recording | Choice kept | Verified (app) | The next recording started with the last choice. |
| Pause and resume | Paused time left out | Verified (spike + app) | Spike 2.4: the clock skips paused periods. End-to-end durations exclude the two 1 s pauses. |
| Pause and resume | Stop while paused | Verified (unit) | `RecordingSessionTests.testStopWhilePausedSaves`. |
| Pause and resume | Audio while paused | Verified (app) | System Audio on, Microphone off: a sound played only while paused; every per-second audio peak in the file is 0. |
| System audio | System audio on | Verified (app) | Area mode with Microphone off: the test sound is at 2 s and 9 s (peak 0.2). |
| System audio | Window mode records the window's app | Verified (app) | Window mode with Microphone off: another app's sound is absent. |
| System audio | System audio off | Verified (spike) | No audio track when both are off. |
| Microphone audio | Both mixed | Verified (spike + app) | One AAC track in every end-to-end file with both on. |
| Stop recording | Stop from toolbox | Verified (app) | The file was saved and the frame, toolbox, and drawings removed. |
| MP4 output | File saved | Verified (app) | `Recording 2026-10-10 19.51.02.mp4`, H.264 + AAC. |
| MP4 output | Name collision | Verified (unit) | `OutputFilesTests.testNameCollisionNeverOverwrites`. |
| Recording failure | Folder not writable | Verified (unit) | `RecordingSessionTests.testReadOnlyFolderReportsErrorWithoutStarting` (real read-only folder). |
| One recording at a time | Second start ignored | Verified (unit) | `RecordingSessionTests.testOneRecordingAtATime`. |

## live-annotation

| Requirement | Scenario | Status | Evidence |
|---|---|---|---|
| Toolbox while recording | Toolbox appears | Verified (app) | Below the area; bottom center in full screen. |
| Toolbox while recording | Move toolbox | Verified (app) | Grip drag moved it by (+100, +100). |
| Pause/Resume and Stop buttons | Buttons always shown | Verified (app) | Visible with the style row open. |
| Pause/Resume and Stop buttons | Pause from toolbox | Verified (app) | Icon changed to play; the timer froze. |
| Pause/Resume and Stop buttons | Resume from toolbox | Verified (app) | — |
| Drawing while paused | Draw while paused | Verified (app) | An arrow drawn while paused appears only after resume in the video. |
| Click-through when no tool is active | Use apps while recording | Verified (app) | Typing reached TextEdit after leaving the tool. |
| Click-through when no tool is active | Draw with a tool | Verified (app) | — |
| Choose and leave a tool | Choose tool | Verified (app) | — |
| Choose and leave a tool | Leave with Esc | Verified (app) | — |
| Drawing tools | Rectangle | Verified (app) + unit | — |
| Drawing tools | Switch line and arrow | Verified (app) | Tab switched line to arrow. |
| Drawing tools | Text | Verified (app) | Real key presses typed text. Japanese input is pending (manual). |
| Drawing limited to the recorded area | Outside the area | Verified (app) | With the pencil active, a drag outside the area drew nothing and selected text in the browser behind it; a drag inside drew a stroke. |
| Eraser | Erase by click | Verified (unit) | `EraserTests`. |
| Eraser | Erase by drag | Verified (app) + unit | — |
| Eraser | Undo erase | Verified (app) + unit | — |
| Eraser | Nothing under eraser | Verified (unit) | — |
| Style controls | Palette color | Verified (app) | Blue swatch. |
| Style controls | Width by key | Verified (app) | The 2 key gave 3 → 5 pt. Scroll wheel direction on a real mouse or trackpad is pending (manual). |
| Undo, redo, and clear all | Undo and redo | Verified (app) | ⌘Z, ⌘Y, and the toolbox buttons. |
| Undo, redo, and clear all | Clear all | Verified (app) + unit | Toolbox button and ⇧⌘Z. |
| Annotations in the video | Drawn during recording | Verified (app) | Strokes appear and disappear in the video at the right times. |
| Annotations in the video | Window mode | Verified (app) | Text and arrow over TextEdit; no editing handles in the video. |
| Annotations end with the recording | Next recording starts clean | Verified (app) | — |

## End-to-end matrix (task 9.2)

Each run: draw two strokes, erase one, undo, pause and resume twice, toggle the cursor, and stop. System Audio and Microphone were both on.

| Mode | 720p | 1080p | 4K | Audio tracks |
|---|---|---|---|---|
| Full screen (3600×2338 native) | 1108×720 | 1662×1080 | 3324×2160 | 1 each |
| Window (1600×1200 native) | 960×720 | 1440×1080 | 1600×1200 | 1 each |
| Area (1200×800 native) | 1080×720 | 1200×800 | 1200×800 | 1 each |

No segment files were left in the output folder after any run.
