<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Dotphin icon">
</p>

<h1 align="center">Dotphin</h1>

<p align="center">A native macOS file manager, built with SwiftUI, that brings KDE Dolphin's file-exploration workflow to the Mac.</p>

<p align="center">
  <img src="screenshot.png" alt="Dotphin main window" width="900">
</p>

## What it is

Dotphin is a from-scratch macOS file manager inspired by [KDE Dolphin](https://apps.kde.org/dolphin/)'s feature set, restyled to Apple's Human Interface Guidelines and Liquid Glass rather than cloned pixel-for-pixel. It does not share code with Dolphin — only the UX ideas it's worth porting.

## Features

- Tabs and split-pane browsing, with drag & drop between panes and with Finder
- Places sidebar (local/USB volumes) and a navigable folder tree
- Icon, compact, and details view modes with per-folder view properties (sort, group, zoom)
- Breadcrumb navigation and a filter/search bar (filename, content, size, type)
- Git status overlays on files and folders in a repo
- File operations: copy/move/rename, batch rename, undo/redo, archives (zip), file compare
- Info panel with Quick Look thumbnails and rich metadata
- Trash as a navigable location, with external volume eject support
- Embedded terminal panel (F4) synced to the active folder: a full xterm-compatible terminal with 256-color and truecolor support, `vim`/`less`/`htop`, and mouse support
- Configurable toolbar and a Settings window (default view, startup location, hidden files)

## Install

```sh
brew install --cask dotfn/tap/dotphin
```

Dotphin is still in beta and isn't notarized yet; the cask clears the download quarantine so macOS lets it open.

## Requirements

- macOS 27 or later
- Xcode 27 / Swift 6.4 toolchain (to build from source)

## Build & run

```sh
swift run
```

Or open `Package.swift` directly in Xcode and hit Run.

## Tests

```sh
swift test
```

## Project layout

Pure Swift Package Manager, no `.xcodeproj` checked in:

```
Sources/Dotphin/
  App/        # app entry point, menu commands
  Models/     # value types (FileItem, AppSettings, ViewProperties, ...)
  Services/   # file system, git, search, archive, settings persistence, ...
  ViewModels/ # BrowserViewModel, TabsViewModel
  Views/      # SwiftUI views
Tests/DotphinTests/
```

The only dependency is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT), the terminal engine behind the embedded terminal panel.
