# Spec Delta

## Purpose

Records the screen to MP4 files. Covers the three recording modes and how the target is selected, output resolution, the recording frame, audio, and starting, stopping, and saving recordings.

## ADDED Requirements

### Requirement: Full screen mode
The system SHALL record the whole display that contains the mouse pointer when full screen mode starts. Recording SHALL start immediately, without a selection step.

#### Scenario: Start full screen
- **WHEN** the pointer is on the secondary display and the user starts full screen mode
- **THEN** a recording of the entire secondary display starts

### Requirement: Window mode
The system SHALL let the user choose a window to record. The window under the pointer SHALL be highlighted, and clicking SHALL start recording that window. The video SHALL contain only that window's content and the annotations, not other windows that overlap it.

#### Scenario: Pick a window
- **WHEN** window mode is active and the user clicks a browser window
- **THEN** recording of that browser window starts

#### Scenario: Overlapping window excluded
- **WHEN** a window is being recorded and another app's window is moved over it
- **THEN** the other window does not appear in the video

#### Scenario: Window moves
- **WHEN** the recorded window is moved or resized during recording
- **THEN** the recorded area stays where the window was when recording started

### Requirement: Custom area mode
The system SHALL let the user drag a rectangle on one display, adjust it by its handles or by dragging it, and start recording with Return or a Record button. The selection size SHALL be shown in pixels.

#### Scenario: Select and record
- **WHEN** custom area mode is active, the user drags a 800x600 point rectangle and presses Return
- **THEN** recording of that rectangle starts

#### Scenario: Adjust before recording
- **WHEN** the user drags a selection handle before starting
- **THEN** the selection is resized and the shown pixel size updates

#### Scenario: Area limited to one display
- **WHEN** the user drags past the edge of the display where the drag began
- **THEN** the selection stops at that display's edge

### Requirement: Cancel selection
The system SHALL cancel window or custom area selection when the user presses Esc, without creating a file.

#### Scenario: Cancel
- **WHEN** custom area mode is active and the user presses Esc before recording
- **THEN** the selection closes and no recording starts

### Requirement: Output resolution
The system SHALL support 720p, 1080p, and 4K output. The recorded area SHALL keep its aspect ratio and be scaled to fit inside 1280x720, 1920x1080, or 3840x2160. It SHALL NOT be scaled above its native pixel size. Width and height SHALL be even numbers.

#### Scenario: 16:9 display at 1080p
- **WHEN** a 2880x1620 pixel display is recorded in full screen mode at 1080p
- **THEN** the video is 1920x1080

#### Scenario: Non-16:9 area at 720p
- **WHEN** a 1600x1200 pixel area is recorded at 720p
- **THEN** the video is 960x720

#### Scenario: No upscaling
- **WHEN** a 1000x500 pixel area is recorded at 4K
- **THEN** the video is 1000x500

### Requirement: Recording frame
In window and custom area modes, the system SHALL draw a 1 point frame just outside the recorded area for the whole recording. The frame SHALL NOT appear in the video. Full screen mode SHALL NOT show a frame.

#### Scenario: Frame shown
- **WHEN** a custom area recording starts
- **THEN** a 1 point frame surrounds the area on screen

#### Scenario: Frame not recorded
- **WHEN** the recording is played back
- **THEN** the frame is not visible in any frame of the video

#### Scenario: Frame removed
- **WHEN** the recording stops
- **THEN** the frame disappears

### Requirement: Own interface excluded from video
The system SHALL keep its own selection overlay, recording frame, toolbox, and windows out of the video. Annotations SHALL be the only exception.

#### Scenario: Toolbox not recorded
- **WHEN** the toolbox is over the recorded area during a full screen recording
- **THEN** the toolbox does not appear in the video

### Requirement: Cursor in recording
In all three modes, the system SHALL let the user choose whether the mouse cursor appears in the video. The choice SHALL be set with the Record Cursor toggle in the menu or in Preferences before recording, and with the toolbox cursor toggle during recording. The default SHALL be on, and the last choice SHALL be kept for later recordings.

#### Scenario: Cursor off in each mode
- **WHEN** Record Cursor is off and the user records in full screen, window, or custom area mode
- **THEN** the cursor does not appear in the video

#### Scenario: Cursor on
- **WHEN** Record Cursor is on and the user records in any mode
- **THEN** the cursor appears in the video

#### Scenario: Toggle during recording
- **WHEN** the user turns the cursor off with the toolbox toggle 10 seconds into a recording
- **THEN** the cursor appears in the video before about 10 seconds and not after

#### Scenario: Choice kept
- **WHEN** the user turns the cursor off in the toolbox, stops, and starts a new recording
- **THEN** the new recording starts with the cursor off

### Requirement: Pause and resume
The system SHALL let the user pause and resume a recording any number of times. Nothing SHALL be recorded while paused, and the saved video SHALL play the recorded parts back to back without a gap. The frame, toolbox, and annotations SHALL stay on screen while paused.

#### Scenario: Paused time left out
- **WHEN** the user records 10 seconds, pauses for 30 seconds, records 5 more seconds, and stops
- **THEN** the MP4 is about 15 seconds long and contains nothing from the paused period

#### Scenario: Stop while paused
- **WHEN** the recording is paused and the user stops it
- **THEN** the file is saved with everything recorded before the pause

#### Scenario: Audio while paused
- **WHEN** System Audio is on and another app plays sound while the recording is paused
- **THEN** that sound is not in the MP4

### Requirement: System audio
When System Audio is on, the system SHALL record the sound played by other apps in full screen and custom area modes, and only the sound of the recorded window's app in window mode. It SHALL NOT record sound played by the recorder itself.

#### Scenario: System audio on
- **WHEN** System Audio is on and a video plays in another app during recording
- **THEN** the MP4 contains that video's sound

#### Scenario: Window mode records the window's app
- **WHEN** System Audio is on, a browser window is recorded in window mode, and both the browser and another app play sound
- **THEN** the MP4 contains the browser's sound and not the other app's sound

#### Scenario: System audio off
- **WHEN** System Audio and Microphone are both off
- **THEN** the MP4 has no audio track

### Requirement: Microphone audio
When Microphone is on, the system SHALL record the default microphone. When System Audio and Microphone are both on, the MP4 SHALL contain one audio track with both mixed.

#### Scenario: Both mixed
- **WHEN** both toggles are on and the user speaks while another app plays sound
- **THEN** the MP4 has one audio track containing both the voice and the app sound

### Requirement: Stop recording
The system SHALL stop the recording, whether running or paused, from the toolbox Stop button, the menu-bar item, or any recording-mode shortcut, and SHALL then remove the frame, toolbox, and annotations from the screen.

#### Scenario: Stop from toolbox
- **WHEN** the user clicks Stop in the toolbox
- **THEN** recording ends, the file is saved, and the frame, toolbox, and annotations disappear

### Requirement: MP4 output
The system SHALL save each recording as an MP4 file with H.264 video in the output folder (default `~/Movies/Recorder`). The file name SHALL be `Recording yyyy-MM-dd HH.mm.ss.mp4`. An existing file SHALL NOT be overwritten. After saving, the system SHALL show a notice with the file name and a way to show it in Finder.

#### Scenario: File saved
- **WHEN** a recording started at 2026-10-10 14:03:22 is stopped
- **THEN** `Recording 2026-10-10 14.03.22.mp4` is in the output folder and plays in QuickTime Player

#### Scenario: Name collision
- **WHEN** a file with that name already exists
- **THEN** the new recording is saved under a different name and the existing file is unchanged

### Requirement: Recording failure
If recording cannot start or stops unexpectedly, for example because the display is disconnected or the output folder is not writable, the system SHALL end the recording, remove the frame and toolbox, keep any part already written when it is playable, and show an error.

#### Scenario: Folder not writable
- **WHEN** the output folder is not writable and the user starts a recording
- **THEN** no recording starts and an error names the folder

### Requirement: One recording at a time
The system SHALL allow only one selection or recording at a time.

#### Scenario: Second start ignored
- **WHEN** custom area selection is active and the user presses the Record Window shortcut
- **THEN** the custom area selection continues and no window selection starts
