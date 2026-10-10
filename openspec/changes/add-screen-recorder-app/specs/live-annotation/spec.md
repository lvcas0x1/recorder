# Spec Delta

## Purpose

Lets the user draw on the recorded area while a recording runs, with the same tools as the Snip app plus an eraser, so the drawings appear in the video.

## ADDED Requirements

### Requirement: Toolbox while recording
The system SHALL show a floating toolbox for the whole recording, in every mode. It SHALL contain the drawing tools, the eraser, Undo, Redo, Clear All, a cursor toggle, and the elapsed time. The user SHALL be able to drag the toolbox to another position.

#### Scenario: Toolbox appears
- **WHEN** a recording starts
- **THEN** the toolbox appears next to the recorded area, or near the bottom of the display in full screen mode

#### Scenario: Move toolbox
- **WHEN** the user drags the toolbox
- **THEN** it moves and stays at the new position until the recording ends

### Requirement: Pause/Resume and Stop buttons
The toolbox SHALL always show two recording control buttons, Pause/Resume and Stop, side by side, whether or not a tool is active. Pause/Resume SHALL show Pause while recording and Resume while paused.

#### Scenario: Buttons always shown
- **WHEN** the pencil is active and the style controls are open
- **THEN** the Pause and Stop buttons are still visible and clickable

#### Scenario: Pause from toolbox
- **WHEN** the user clicks Pause
- **THEN** the recording pauses and the button changes to Resume

#### Scenario: Resume from toolbox
- **WHEN** the recording is paused and the user clicks Resume
- **THEN** the recording continues and the button changes to Pause

### Requirement: Drawing while paused
The system SHALL keep the toolbox and all tools usable while the recording is paused.

#### Scenario: Draw while paused
- **WHEN** the user pauses, draws an arrow, and resumes
- **THEN** the arrow is visible in the video from the moment recording resumes

### Requirement: Click-through when no tool is active
While no tool is active, the system SHALL let mouse and keyboard input pass to the apps under the recorded area. While a tool is active, mouse input over the recorded area SHALL go to the tool.

#### Scenario: Use apps while recording
- **WHEN** no tool is active and the user clicks a button in the recorded area
- **THEN** the click reaches the app under the pointer

#### Scenario: Draw with a tool
- **WHEN** the pencil is active and the user drags over the recorded area
- **THEN** a stroke is drawn and the app under the pointer receives no click

### Requirement: Choose and leave a tool
The system SHALL activate a tool when its toolbox button is clicked and highlight that button. Clicking the active tool's button again, or pressing Esc while not editing text, SHALL leave the tool.

#### Scenario: Choose tool
- **WHEN** the user clicks the Rectangle button
- **THEN** the rectangle tool is active, its button is highlighted, and the color, width, and alpha controls are shown

#### Scenario: Leave with Esc
- **WHEN** the arrow tool is active and the user presses Esc
- **THEN** no tool is active and input passes to the apps again

### Requirement: Drawing tools
The system SHALL provide the rectangle, line, arrow, pencil, marker, and text tools with the same behavior as the Snip app: Tab switches between line and arrow, clicking points and right-clicking makes a line strip, the marker is translucent and wider, and text can be scaled and rotated while being edited.

#### Scenario: Rectangle
- **WHEN** the rectangle tool is active and the user drags from A to B
- **THEN** a rectangle with corners A and B is drawn in the current color, alpha, and width

#### Scenario: Switch line and arrow
- **WHEN** the line tool is active and the user presses Tab
- **THEN** the arrow tool becomes active

#### Scenario: Text
- **WHEN** the text tool is active and the user clicks and types "Hello"
- **THEN** "Hello" appears at the click position in the current color

### Requirement: Drawing limited to the recorded area
The system SHALL accept drawing only inside the recorded area.

#### Scenario: Outside the area
- **WHEN** a tool is active in a custom area recording and the user drags outside the area
- **THEN** nothing is drawn outside the area and input outside the area reaches the apps there

### Requirement: Eraser
The system SHALL provide an eraser tool. Clicking an annotation or dragging across annotations SHALL remove each annotation the eraser touches. Each eraser gesture SHALL be one undoable step.

#### Scenario: Erase by click
- **WHEN** the eraser is active and the user clicks on an arrow
- **THEN** the arrow is removed

#### Scenario: Erase by drag
- **WHEN** the eraser is active and the user drags across two strokes and a rectangle
- **THEN** all three are removed

#### Scenario: Undo erase
- **WHEN** the user erases three annotations in one drag and presses Command-Z
- **THEN** all three annotations return

#### Scenario: Nothing under eraser
- **WHEN** the eraser is active and the user clicks where there is no annotation
- **THEN** nothing changes and no undo step is added

### Requirement: Style controls
The system SHALL let the user choose a color from the Snip palette or a custom color, set alpha from 0 to 255, and set pen width from 1 to 24 points with a slider, the scroll wheel, or the 1 and 2 keys while a tool is active.

#### Scenario: Palette color
- **WHEN** the user clicks the blue swatch
- **THEN** later annotations are blue

#### Scenario: Width by key
- **WHEN** the pencil is active and the user presses 2
- **THEN** the pen width increases by 1 point

### Requirement: Undo, redo, and clear all
The system SHALL support Undo (Command-Z), Redo (Command-Y), and Clear All (Shift-Command-Z) of annotation changes while a tool is active, and from the toolbox buttons at any time. Clear All SHALL NOT be undoable.

#### Scenario: Undo and redo
- **WHEN** the user draws a shape, clicks Undo, then clicks Redo
- **THEN** the shape disappears and then returns

#### Scenario: Clear all
- **WHEN** the user clicks Clear All after drawing three shapes
- **THEN** all annotations are removed and Redo restores nothing

### Requirement: Annotations in the video
The system SHALL show annotations in the video at the moment they are drawn and SHALL stop showing them in the video from the moment they are erased, undone, or cleared. The video SHALL never show the toolbox or the tool hints.

#### Scenario: Drawn during recording
- **WHEN** the user draws an arrow 10 seconds into a recording and erases it at 20 seconds
- **THEN** the arrow is visible in the video from about 10 to 20 seconds

#### Scenario: Window mode
- **WHEN** the user draws over a window being recorded in window mode
- **THEN** the drawing is visible in the video over the window content

### Requirement: Annotations end with the recording
The system SHALL remove all annotations from the screen when the recording stops. Annotations SHALL NOT carry over to the next recording.

#### Scenario: Next recording starts clean
- **WHEN** the user stops a recording with annotations and starts a new one
- **THEN** the new recording starts with no annotations
