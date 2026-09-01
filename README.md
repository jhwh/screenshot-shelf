# Screenshot Shelf

A macOS menu-bar shelf for recent screenshots. One click into Cursor, Claude, or Codex.

No accounts, no network, no analytics. Not a Cursor extension — Cursor is just a drop target.

**Download:** https://jhwh.github.io/screenshot-shelf/

## Build

macOS 14+, Xcode 16+. Open `ScreenshotShelf.xcodeproj` and Run (⌘R), or:

```bash
xcodebuild -scheme ScreenshotShelf -configuration Debug -derivedDataPath build
open "build/Build/Products/Debug/Screenshot Shelf.app"
```

A camera icon appears in the menu bar.

## Use

Click the icon for the latest shots. Drag a thumbnail to drop the real file, click to copy, or turn on destinations in Settings and hit **Send** (needs Accessibility).

Default folder is `~/Desktop`. If the shelf is empty: **Settings → Choose Folder…**, or enable Desktop/Pictures under System Settings → Privacy & Security → Files and Folders.
