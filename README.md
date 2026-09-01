# Screenshot Shelf

A native macOS menu-bar app that shows recent screenshots and lets you drag the original files into other apps, or send them into the active Cursor, Claude, or Codex session.

This is **not** a Cursor extension. Cursor is only a drop target. Open this folder in Cursor to edit the source; the running app lives in the macOS menu bar at the top of the screen.

No accounts, no network, no analytics.

Landing (download the latest DMG): https://jhwh.github.io/screenshot-shelf/

## Requirements

- Apple Silicon Mac
- macOS 14 or later (built and used on macOS 26)
- [Xcode](https://developer.apple.com/xcode/) 16 or later (Xcode 26 is fine)

## Open in Cursor

1. Open Cursor.
2. **File → Open Folder…** and choose this repository (`screenshot-shelf`).
3. Edit the Swift sources under `ScreenshotShelf/`.

Do not add this project as a Cursor extension. Building and running happens with Xcode / `xcodebuild`.

## Build and run

### Xcode

1. Open `ScreenshotShelf.xcodeproj`.
2. Select the **ScreenshotShelf** scheme.
3. Press **Run** (⌘R).
4. A camera icon appears in the menu bar. Click it to open the shelf.

### Command line

```bash
xcodebuild -scheme ScreenshotShelf -configuration Debug -derivedDataPath build
open "build/Build/Products/Debug/Screenshot Shelf.app"
```

A Release build:

```bash
xcodebuild -scheme ScreenshotShelf -configuration Release -derivedDataPath build
```

## Put it in /Applications

1. Build Release (Xcode **Product → Archive**, or the `xcodebuild` command above).
2. Copy `Screenshot Shelf.app` to `/Applications`.
3. Open it once from `/Applications` (right-click → Open if Gatekeeper asks).
4. The app is a menu-bar agent: it has no Dock icon.

Launch at login is more reliable from `/Applications` than from an Xcode DerivedData path.

## Folder permissions

Screenshot Shelf only indexes files. It does not move, rename, or hide captures.

- Default folder: `~/Desktop`
- Optional extra folder: `~/Pictures/Screenshots` (toggle in Settings)
- Matching names: `Screenshot *` and `Zrzut ekranu *` with `png`, `jpg`, `jpeg`, `heic`, or `webp`

macOS may ask for Desktop or Pictures access the first time the app lists those folders.

If the panel is empty after you take a screenshot:

1. Click the menu-bar icon → **Settings** → **Choose Folder…** and select Desktop (or your screenshot folder).
2. Or open **System Settings → Privacy & Security → Files and Folders** and enable **Desktop Folder** and **Pictures Folder** for Screenshot Shelf.

Screen Recording is not required.

**Send to Cursor / Claude / Codex** needs Accessibility so the shelf can focus the target window and paste. Drag-and-drop still works without it. macOS will prompt on first send, or open **Settings → Destinations → Open Accessibility Settings**.

A Debug build is ad-hoc signed. macOS treats each rebuild as a new app, so the Accessibility toggle can look on while this running copy is still untrusted. After a rebuild, turn **Screenshot Shelf** off and on in that list, then quit the app completely and open the same `.app` again.

## How to use

- Click the menu-bar icon for a newest-first grid (about 30 items).
- **Drag** a thumbnail into Cursor chat, Slack, Finder, or Mail. The drop is the real file URL, not a bitmap-only promised file.
- **Click** a thumbnail to copy the image to the clipboard.
- **Send** only after you turn on destinations in **Settings**. The shelf then shows those apps under each thumbnail — not the full list. Click a chip to paste into that session (⌘V for GUI apps, Ctrl+V for Claude Code / Codex CLI). Several windows of the same app open a title menu. In Cursor, keep the chat composer focused if the image lands in the editor — the shelf tries to find the composer first.
- Right-click for **Send to**, **Reveal in Finder**, or **Move to Trash**.
- Esc or a click outside the panel closes it.
- Settings: watched folder, optional Pictures/Screenshots folder, system screenshot location, skip floating preview, which apps you send to, launch at login, Quit.

To have a new ⌘⇧3 / ⌘⇧4 / ⌘⇧5 capture appear instantly, open Settings and enable **Save new screenshots to this folder** plus **Skip floating preview**. That writes the same macOS options as Screenshot → Options (⌘⇧5). Screenshot Shelf does not intercept the system preview HUD.

A new ⌘⇧3 / ⌘⇧4 / ⌘⇧5 capture should appear without relaunching the app.

## Success check

1. Build and launch Screenshot Shelf.
2. Take a screenshot onto the Desktop.
3. Click the menu-bar icon and confirm the new thumbnail is first.
4. Drag that thumbnail into a Cursor chat. Cursor should receive the original PNG file.
5. Or click the Cursor chip under the thumbnail. After Accessibility is granted, the image should paste into the active Cursor session.
