# Nix Mind

[![macOS CI](https://github.com/Duy-Company/nix-mind/actions/workflows/macos.yml/badge.svg)](https://github.com/Duy-Company/nix-mind/actions/workflows/macos.yml)
[![Latest release](https://img.shields.io/github/v/release/Duy-Company/nix-mind)](https://github.com/Duy-Company/nix-mind/releases/latest)

An independent native macOS mind-mapping app for turning ideas into clear, connected plans. Create branches on a free-moving canvas, shape and style your topics, and switch to an editable outline whenever you want to focus on the structure.

Nix Mind is built with **Swift, SwiftUI, and AppKit**. Your maps are local files. There is no account, hosted backend, or built-in AI subscription, and the interface is in English.

## Download and run

**Requires macOS 14 Sonoma or later.** The universal app supports Apple Silicon and Intel Macs.

1. Download the `.dmg` from [GitHub Releases](https://github.com/Duy-Company/nix-mind/releases/latest).
2. Open the disk image and drag **Nix Mind.app** into **Applications**.
3. Launch Nix Mind from Applications and create a map, or choose **File → Open…** to open an existing file.

A `.zip` is also available: extract it, then move **Nix Mind.app** into Applications. Each release includes `SHA256SUMS.txt` for checking the downloads.

**These releases are ad-hoc signed, not Developer ID signed or notarized.** macOS may block the first launch. If you trust this release, follow Apple's [instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445): after attempting to open it, go to **System Settings → Privacy & Security → Open Anyway**, if that option is offered. No system-wide security changes are needed.

## Features

- **A canvas that grows with your ideas.** Add more than six branches to the central topic. New topics automatically arrange themselves, and the view zooms out to make room.
- **Direct editing.** Double-click a topic to rename it on its own background. Drag a topic to move its entire branch; pan and zoom around the canvas.
- **Topic formatting.** Choose an installed font, font size, bold, italic, underline, strikethrough, text alignment, and text color.
- **Node appearance.** Use a rounded rectangle, rectangle, capsule, ellipse, or diamond. Customize fill, border color, and border width, plus branch colors and notes.
- **Branch direction.** Choose Automatic, Left to right, or Right to left. The layout and topic **+** controls follow the direction.
- **Resizable side panels.** Drag either divider to make the topic list or inspector wider. Use the left and right sidebar buttons in the header to hide or show each panel.
- **Multiple sheets in one file.** Create, switch, rename, and remove sheets using tabs at the top of the window.
- **Mind map and Outliner views.** Switch at the bottom right. Both views edit the same topics; Outliner supports collapsing branches and indenting or outdenting topics.
- **Local document workflow.** New, Open, Save, Save As, autosave, multiple document windows, and native Undo/Redo.
- **File exchange.** Import and export compatible mind map archives and FreeMind files.
- **Local MCP for AI clients.** Let an MCP client read and edit topics, formatting, structure, and sheets through 14 local tools, with atomic patches and stale-data checks.

Try [Product Roadmap.nixmap](Examples/Product%20Roadmap.nixmap), a sample workbook with two sheets.

## Basic controls

Select a topic to reveal its **+** controls. The upper control adds a child; the lower control adds a sibling. The central topic has one control for adding children. Use the inspector on the right to change text, appearance, direction, and notes.

| Action | Shortcut or gesture |
| --- | --- |
| New / Open / Save / Save As | `⌘N` / `⌘O` / `⌘S` / `⇧⌘S` |
| Rename a topic on the canvas | Double-click or `E` |
| Confirm / cancel a canvas title edit | `Return` / `Escape` |
| Add child / sibling on the canvas | `Tab` / `Return` |
| Delete the selected branch on the canvas | `Delete` |
| Move a branch | Drag its topic |
| Resize the topic list or inspector | Drag its divider next to the canvas |
| Hide / show a side panel | Left / right sidebar button in the header |
| Pan | Drag the background, or hold `Space` and drag |
| Zoom | Trackpad pinch, or `⌘` + scroll |
| Fit / center on root | `⌘0` / `⌘1` |
| Arrange the current sheet | `⇧⌘L` |
| Undo / Redo | `⌘Z` / `⇧⌘Z` |
| Add sibling while editing in Outliner | `Return` |
| Indent / outdent in Outliner | `Tab` / `Shift-Tab` |

Double-click a sheet tab, or use its context menu, to rename it. Closing a sheet removes it from the workbook and can be undone. At least one sheet always remains.

## File formats

| Format | Use | Sheets |
| --- | --- | --- |
| `.nixmap` | Native JSON workbook; preserves topic IDs, tree, positions, typography, appearance, direction, and notes | All sheets |
| Mind map archive | ZIP/JSON exchange import and export | All sheets |
| `.mm` | FreeMind XML import and export | One sheet; export uses the active sheet |

Use **Save** for the native format and **File → Export…** for exchange formats. Imported archive and FreeMind files open as unsaved native copies, leaving the original files intact. Older single-sheet `.nixmap` files remain readable.

Archive support covers text topics, hierarchy, and plain-text notes. Legacy `content.xml`, encrypted files, attachments, floating topics, relationships, summaries, and boundaries are not supported. Nix Mind's own style metadata survives internal exchange round-trips; other applications may rearrange topics or ignore that metadata. Visual fidelity in other mind-mapping applications has not been verified. Keep the original file when exchanging maps.

There is no separate limit on direct root children. Document safeguards are 50,000 topics per sheet, fewer than 128 levels, up to 500 sheets, and a 64 MB input limit. Interactive performance at those maximum sizes has not been benchmarked.

## Connect an AI client with MCP

1. Open Nix Mind and click **MCP** in the bottom toolbar.
2. Keep **Local MCP** enabled, select **VS Code** or **Other clients (mcpServers)**, and click **Copy MCP configuration**.
3. Add the configuration to a client that supports local stdio MCP servers.
4. Keep Nix Mind open while the client works with your maps.

The server uses a private Unix socket under your macOS account, with no TCP listener. Nix Mind itself does not call an AI model. Your client decides whether map data is sent to a remote provider. Disable Local MCP in the same settings to stop access.

See [MCP.md](MCP.md) for tools and the editing contract, or start with the [VS Code example](mcp-config.vscode.example.json) or [mcpServers example](mcp-config.example.json). VS Code uses a top-level `servers` object with `type: "stdio"`; do not nest `mcpServers` inside it. If you move the app, copy its configuration again so the executable path stays correct.

## Build from source

Install **Xcode 16.4 or later**, select it as your active developer directory, and complete Xcode's first-launch setup. There are no third-party app dependencies to install.

```sh
git clone git@github.com:Duy-Company/nix-mind.git
cd nix-mind
open NixMind.xcodeproj
```

In Xcode, select the **NixMind** scheme and **My Mac**, then press `⌘R`.

Or build from Terminal:

```sh
xcodebuild -project NixMind.xcodeproj -scheme NixMind \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
open 'build/Build/Products/Release/Nix Mind.app'
```

Create the same universal ZIP and DMG used by releases:

```sh
./scripts/build-release.sh
```

The packaged downloads appear in `dist/`.

## Tests and releases

```sh
./scripts/test.sh          # Model, layout, file formats, and MCP patches
./scripts/test-editor.sh   # Native editor state, styles, sheet operations, and Undo/Redo
./scripts/test-canvas.sh   # Indexed culling, render caches, drag preview, and Undo
# Optional: run canvas checks and a local benchmark on your own map
./scripts/test-canvas.sh /path/to/map.nixmap
./scripts/benchmark-canvas.sh /path/to/map.nixmap
# With the app running and Local MCP enabled:
python3 scripts/test-mcp.py
```

The suites cover the model and file formats, native editing, canvas indexing and caching, branch drags and Undo, and live MCP integration. MCP tests create their own files under `build/`; they do not edit existing documents. Automated checks do not replace visual and gesture testing on every supported macOS version.

[GitHub Actions](https://github.com/Duy-Company/nix-mind/actions) runs tests, builds a universal app, verifies its ad-hoc signature and architectures, exercises MCP against the built app, and packages downloads on pushes and pull requests to `main`. Pushing a version tag such as `v1.0` publishes a GitHub Release only after these checks pass. The tag must match the app version and have a corresponding file in `release-notes/`.

Source code, the Xcode project, tests, scripts, and the sample workbook are tracked. Build outputs, local MCP configurations, and personal Xcode settings are excluded. Run `python3 scripts/create-project.py` if you add Swift source files and need to regenerate the project.
