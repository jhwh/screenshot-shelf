# Screenshot Shelf

Taking the screenshot was the easy part — you hit ⇧⌘4. Then comes the fun bit: forty files named `Screenshot 2026-08-14 at 3.41.07 PM`. Shelf keeps your last shots in the menu bar.

One click to send screenshot into Cursor, Claude, Codex, Slack, or Grok Bot.

**Download:** https://jhwh.github.io/screenshot-shelf/

## Build

macOS 14+, Xcode 16+. Open `ScreenshotShelf.xcodeproj` and Run (⌘R), or:

```bash
xcodebuild -scheme ScreenshotShelf -configuration Debug -derivedDataPath build
open "build/Build/Products/Debug/Screenshot Shelf.app"
```

A camera icon appears in the menu bar.

## Use

Click the icon for the latest shots, or press **⌥⌘S** to toggle the shelf from any app (change it in Settings). Drag a thumbnail to drop the real file, click to copy, or turn on destinations in Settings and hit **Send** (needs Accessibility).

Default folder is `~/Desktop`. If the shelf is empty: **Settings → Choose Folder…**, or enable Desktop/Pictures under System Settings → Privacy & Security → Files and Folders.
