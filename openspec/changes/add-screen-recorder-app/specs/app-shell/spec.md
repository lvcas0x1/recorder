# Spec Delta

## Purpose

Defines how the recorder appears on the Mac: a menu-bar icon without a Dock icon, the menu, permission onboarding, global shortcuts that can be changed or removed, and saved preferences.

## ADDED Requirements

### Requirement: Menu-bar app without Dock icon
The system SHALL run as a menu-bar app. It SHALL show a menu-bar icon and SHALL NOT show a Dock icon or appear in the app switcher.

#### Scenario: Launch
- **WHEN** the app launches
- **THEN** a menu-bar icon appears and no Dock icon is shown

### Requirement: Menu
While no recording is in progress, the system SHALL open a menu when the user clicks the menu-bar icon. The menu SHALL list Record Full Screen, Record Window, and Record Area with their shortcuts, the resolution choice, the Record Cursor, System Audio, and Microphone toggles, Open Recordings Folder, Preferences, and Quit.

#### Scenario: Open menu
- **WHEN** no recording is in progress and the user clicks the menu-bar icon
- **THEN** the menu opens with the three record actions, each showing its current shortcut

#### Scenario: Removed shortcut in menu
- **WHEN** the shortcut for Record Window has been removed and the user opens the menu
- **THEN** Record Window is listed without a shortcut and can still be chosen

#### Scenario: Open recordings folder
- **WHEN** the user chooses Open Recordings Folder
- **THEN** the output folder opens in Finder

### Requirement: Recording indicator
While a recording is in progress, the system SHALL show a recording icon and the recorded time (minutes and seconds, paused time excluded) in the menu bar. While paused, it SHALL show a paused icon and the time SHALL not advance. Clicking it SHALL stop the recording.

#### Scenario: Indicator while recording
- **WHEN** a recording has been running for 75 seconds
- **THEN** the menu-bar item shows the recording icon and 01:15

#### Scenario: Indicator while paused
- **WHEN** the user records 20 seconds and then pauses for 30 seconds
- **THEN** the menu-bar item shows the paused icon and 00:20 throughout the pause

#### Scenario: Stop from menu bar
- **WHEN** a recording is in progress and the user clicks the menu-bar item
- **THEN** the recording stops and the file is saved

### Requirement: Default shortcuts
On first launch, the system SHALL assign a default global shortcut to each of the three recording modes: Control-Shift-1 for full screen, Control-Shift-2 for window, and Control-Shift-3 for custom area. The shortcuts SHALL work while any app is frontmost.

#### Scenario: Default shortcut starts a mode
- **WHEN** the app is newly installed and the user presses Control-Shift-2 while another app is frontmost
- **THEN** window recording mode starts

### Requirement: Change shortcuts
The system SHALL let the user record a new key combination for each recording mode in Preferences. If the new combination cannot be registered, the old one SHALL stay active and an error SHALL be shown.

#### Scenario: Rebind
- **WHEN** the user sets Record Area to Control-Option-R
- **THEN** Control-Option-R starts custom area mode and Control-Shift-3 no longer does

#### Scenario: Registration fails
- **WHEN** the user chooses a combination that the system refuses to register
- **THEN** Preferences shows an error and the previous shortcut keeps working

### Requirement: Remove shortcuts
The system SHALL let the user remove the shortcut of any recording mode, leaving that mode with no shortcut. A removed shortcut SHALL stay removed after relaunch, and the user SHALL be able to restore the default.

#### Scenario: Remove
- **WHEN** the user removes the Record Full Screen shortcut
- **THEN** Control-Shift-1 no longer starts a recording, and the key combination reaches the frontmost app

#### Scenario: Removed after relaunch
- **WHEN** the user removes a shortcut and relaunches the app
- **THEN** that mode still has no shortcut

#### Scenario: Restore default
- **WHEN** the user chooses Restore Default for a removed shortcut
- **THEN** that mode's default shortcut is active again

### Requirement: Shortcut stops a recording
While a recording is in progress, running or paused, pressing any recording-mode shortcut SHALL stop the recording instead of starting a new one.

#### Scenario: Stop with shortcut
- **WHEN** a custom area recording is in progress and the user presses the Record Full Screen shortcut
- **THEN** the recording stops and no new recording starts

### Requirement: Screen Recording permission onboarding
If Screen Recording permission is missing when a recording mode is started, the system SHALL NOT start the mode. It SHALL show an onboarding window that explains why the permission is needed, links to System Settings, and reports when the permission has been granted.

#### Scenario: Permission missing
- **WHEN** Screen Recording permission is not granted and the user starts any recording mode
- **THEN** no selection or recording starts and the onboarding window opens

#### Scenario: Grant detected
- **WHEN** the user grants the permission while onboarding is shown
- **THEN** onboarding reports success and recording modes become available

### Requirement: Microphone permission
When microphone capture is turned on, the system SHALL ask for Microphone permission before the first recording. If the permission is denied, the system SHALL record without the microphone and tell the user that the microphone was not recorded.

#### Scenario: Microphone denied
- **WHEN** microphone capture is on, the permission is denied, and the user records
- **THEN** the recording is made without microphone audio and a notice says the microphone was not recorded

### Requirement: Preferences
The system SHALL provide a Preferences window with the three shortcuts, the default resolution, the System Audio and Microphone toggles, the Record Cursor toggle, and the output folder.

#### Scenario: Change output folder
- **WHEN** the user chooses a different output folder in Preferences
- **THEN** later recordings are saved to that folder

### Requirement: Preferences persistence
The system SHALL keep all settings across app launches.

#### Scenario: Persist
- **WHEN** the user changes the resolution, audio toggles, cursor setting, output folder, or shortcuts and relaunches the app
- **THEN** the changed values are kept

### Requirement: Follow system theme
The system SHALL follow the system light or dark appearance and accent color in its menus, toolbox, and windows.

#### Scenario: Dark appearance
- **WHEN** the system appearance switches to dark
- **THEN** the toolbox and Preferences switch to dark styling without a relaunch
