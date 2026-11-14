# MacroForMac

A native macOS app for making and running macros: sequences of keystrokes, typed text, mouse clicks, drags, scrolls, waits, app launches, URLs, shell commands and AppleScript. You can record them or build them step by step, then run them from the window, the menu bar, or a global keyboard shortcut.

Requires macOS 13 Ventura or later. Built with Swift and SwiftUI. No dependencies.

## Features

- **Record macros.** Click **Record**, use your Mac normally, then click **Stop** (or press ⌃⌥⌘.). Typing becomes "Type Text" steps, shortcuts become key presses, and clicks, double-clicks, drags, scrolls and pauses are captured too. **How long you hold each key or mouse button is recorded** ("Press W · held 1.2 s"), and if you press other things while holding one, you get separate Key Down / Key Up steps so the timing plays back the same. Input aimed at MacroForMac itself is ignored.
- **Build macros by hand** from 15 step types:

  | Step | What it does |
  | --- | --- |
  | Type Text | Types any text, including line breaks and emoji |
  | Press Keys | Presses a key combo such as ⌘C, ⇧⌘4, ↩, F5, optionally holding it for a set time |
  | Key Down / Key Up | Holds a key down until a later step releases it |
  | Wait | Pauses for a number of seconds |
  | Click | Left, right or middle click; single, double or triple; at a position or wherever the pointer is; can hold ⌘/⌥/⌃/⇧ and hold the button for a set time |
  | Mouse Button Down / Up | Holds a mouse button down until a later step releases it (Move Mouse steps in between drag) |
  | Move Mouse | Moves the pointer |
  | Drag | Drags from one point to another |
  | Scroll | Scrolls vertically and/or horizontally |
  | Open App | Launches or switches to an app (by name, bundle ID or path) |
  | Open URL or File | Opens a website, file, folder or app link |
  | Run Shell Command | Runs a zsh command, optionally waiting for it to finish |
  | Run AppleScript | Runs an AppleScript |

- **Global shortcuts.** Give any macro a shortcut and it runs from any app. Press it again to stop. ⌃⌥⌘. stops whatever is running (you can change this in Settings).
- **Menu bar menu** to run any macro, start a recording, or stop playback.
- **Repeat** a macro N times or loop it until stopped, and change its **speed** (0.25× to 10×, scaling waits and hold times).
- Keys held during playback auto-repeat like a real keyboard, and anything still held when a macro ends or is stopped is released automatically.
- **Edit freely:** reorder by dragging, duplicate, disable steps, use "Pick" to capture a screen position with the pointer.
- **Import and export** macros as JSON files to back them up or share them.
- Steps are highlighted live while a macro runs.

## Install

### Option A: download a build

Every push builds the app on GitHub Actions. Open the repository's **Actions** tab, pick the latest **Build** run, and download the **MacroForMac** artifact (a zip containing `MacroForMac.app`, universal for Apple Silicon and Intel).

The build isn't notarized by Apple, so macOS blocks the first launch. After unzipping, either:

- Move `MacroForMac.app` to `/Applications`, try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or
- Run this once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/MacroForMac.app
```

### Option B: build it yourself

You need Xcode 15 or later, or the Xcode Command Line Tools.

```bash
git clone https://github.com/pebbleford/macroformac.git
```

```bash
cd macroformac && make install
```

This builds `dist/MacroForMac.app`, copies it to `/Applications`, and opens it. `make app` only builds, and `make test` runs the unit tests. You can also open `Package.swift` in Xcode.

## First launch: permissions

macOS needs your permission before any app can type or click for you:

1. **Accessibility** (required). Go to System Settings → Privacy & Security → Accessibility and turn on **MacroForMac**. The app shows a banner with buttons that take you there.
2. **Automation** (only for AppleScript steps). macOS asks the first time a script controls another app.
3. **Input Monitoring** (optional). Recording works with Accessibility alone. Input Monitoring lets the recorder use a lighter, listen-only event tap.

> If you rebuild the app yourself, macOS may treat the new build as a different app. If macros stop working after a rebuild, remove MacroForMac from the Accessibility list with **–** and add it again.

## Using it

1. Click **+** to create a macro, or **Record** to capture one.
2. Add steps with **Add Step**. Select a step to edit it in the right-hand panel.
3. Optionally set a **Shortcut**, **Repeat** count and **Speed**.
4. Click **Run** (⌘↩). MacroForMac hides itself so the input goes to the app you were using before. Or press the macro's shortcut from inside any app.

Tips:

- Put a short **Wait** after **Open App** or **Open URL** steps so the app is ready before you type into it.
- Clicks use absolute screen positions, measured from the top-left corner of the main display. Use **Pick** to capture a spot: hover over it and wait for the 3-second countdown to finish.
- Recording records where you click, not how the pointer moves.
- Presses shorter than 0.25 s are recorded as quick taps. Change this, or turn hold recording off, in Settings → Recording.
- Shortcuts need ⌘, ⌃ or ⌥ (F-keys work alone), so they don't take over normal typing.

## Where your macros are stored

`~/Library/Application Support/MacroForMac/macros.json`. It's plain, readable JSON:

```json
{
  "version": 1,
  "macros": [{
    "name": "Sign-off",
    "hotkey": { "keyCode": 1, "modifiers": 3 },
    "repeatCount": 1,
    "speed": 1,
    "steps": [
      { "action": { "type": "typeText", "text": "Best,\nSam" } },
      { "action": { "type": "keyPress", "keyCode": 36, "modifiers": 0 } }
    ]
  }]
}
```

`modifiers` is a bit mask: 1 = ⌃, 2 = ⌥, 4 = ⇧, 8 = ⌘. Settings → General → **Show in Finder** reveals the file.

## Project layout

```
Package.swift
Sources/
  MacroCore/            Platform-independent model, JSON storage, playback sequencing, recording logic
  MacroForMac/
    MacroForMacApp.swift  App, window, menu bar and menu commands
    AppState.swift        Library, playback, recording, hotkeys, settings
    Engine/               CGEvent playback, CGEvent-tap recorder, Carbon hotkeys, permissions
    Views/                SwiftUI interface
Tests/MacroCoreTests/   Unit tests for MacroCore
Support/                Info.plist and AppIcon.icns
scripts/build-app.sh    Builds and ad-hoc signs dist/MacroForMac.app
scripts/make-icon.py    Regenerates the app icon (Pillow)
```

## Limitations

- Typed text is sent as Unicode characters. A few apps, mostly games and some remote-desktop tools, read raw key codes instead. For those, use **Press Keys** steps.
- Positions are absolute, so a macro that clicks may need re-picking if windows move or you change displays.
- macOS doesn't let apps type into password fields protected by Secure Input.
