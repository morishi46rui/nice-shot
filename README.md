# NiceShot

**English** | [日本語](README.ja.md)

A lightweight screenshot tool for macOS. Capture a region → annotate → copy / save / pin, all quickly from the menu bar. A Shottr-like workflow implemented natively in Swift (AppKit + ScreenCaptureKit).

## Features

- **Menu bar app** with a customizable global hotkey (default ⌥⇧4)
- **Region capture** (drag to select, live dimensions, HiDPI / multi-monitor aware)
- **Annotation editor**
  - Arrow / rectangle / ellipse / line / freehand / text / blur (pixelate)
  - Color & line width, undo (⌘Z)
  - After drawing, it auto-switches to the select tool so you can immediately **move & resize** (corner + edge handles, Shift to lock aspect ratio / snap to 45°, Delete to remove)
- **Export**: copy to clipboard (⌘C) / save as PNG (⌘S) / pin to screen (⌘P, floating window)
- Hotkey is configurable from the preferences window and persisted

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 / Xcode 16 or later (to build)

## Build & Run

```sh
git clone <this-repo>
cd nice-shot
./build.sh          # swift build + assemble the .app bundle + code sign
open NiceShot.app
```

`build.sh` signs the app with a code-signing certificate found via `security find-identity`
(Apple Development / Developer ID). If none is found, it falls back to ad-hoc signing.
To use a specific certificate:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

## Permissions (Screen Recording)

On the first capture, macOS will ask for Screen Recording permission. Enable NiceShot under
**System Settings → Privacy & Security → Screen Recording**.

> ⚠️ With ad-hoc signing, the permission resets on every rebuild. Signing with a stable
> certificate keeps the grant across rebuilds, because TCC ties the permission to the signing
> identity.

## Changing the Hotkey

Open the menu bar icon → **"ショートカットを設定… (Configure Shortcut)"** (⌘,).

If you use a combo that collides with a macOS default screenshot shortcut (e.g. `⌘⇧4`), turn off
the matching OS shortcut under **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**.

## Implementation Notes

- Capture uses `ScreenCaptureKit` (`SCScreenshotManager`). The crop scale is derived from the
  `NSScreen` point size and the actual captured pixel dimensions, so it stays correct under HiDPI
  scaling and mixed multi-monitor setups.
- The global hotkey uses Carbon's `RegisterEventHotKey` (no Accessibility permission required).
- Diagonal resize cursors are not in the public API, so AppKit's private cursors are used with a
  fallback to horizontal/vertical resize cursors (`ResizeCursors.swift`). **Because of this private
  API usage, the app cannot be submitted to the Mac App Store.** Distributing via GitHub / directly
  is fine.

## License

[MIT](LICENSE)
