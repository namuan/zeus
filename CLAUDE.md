# CLAUDE.md

## Project Overview

**Open-Zeus** is a native macOS AI agent orchestrator. It provides a three-column SwiftUI interface (Projects | Tasks | Terminal) for managing, monitoring, and interacting with multiple agent processes running against local filesystem directories.

- **Language:** Swift 6
- **Platform:** macOS 15+ (Sequoia)
- **Build System:** Swift Package Manager
- **License:** MIT

## Common Commands

```bash
# Build
swift build

# Run (development)
swift run OpenZeus

# Test
swift test

# Lint
./scripts/lint.sh

# Lint + tests
./scripts/check.sh

# Install repo Git hooks
./scripts/install-hooks.sh

# Setup Git notes sharing (once per clone)
./scripts/setup-git-notes.sh

# Build release + install to ~/Applications/OpenZeus.app
./install.command
```

## Codebase Documentation

Detailed codebase analysis lives in `.planning/codebase/`:

| Document | Description |
|----------|-------------|
| [STACK.md](.planning/codebase/STACK.md) | Languages, runtime, frameworks, dependencies |
| [ARCHITECTURE.md](.planning/codebase/ARCHITECTURE.md) | System design, patterns, data flow, entry points |
| [STRUCTURE.md](.planning/codebase/STRUCTURE.md) | Directory layout and key file locations |
| [CONVENTIONS.md](.planning/codebase/CONVENTIONS.md) | Code style, naming, error handling patterns |
| [TESTING.md](.planning/codebase/TESTING.md) | Test framework, structure, mocking patterns |
| [INTEGRATIONS.md](.planning/codebase/INTEGRATIONS.md) | External services, system integrations |
| [CONCERNS.md](.planning/codebase/CONCERNS.md) | Tech debt, bugs, performance, security |

**Quick reference:**
- Models: `Sources/OpenZeus/Models/`
- Core (DB, actors): `Sources/OpenZeus/Core/`
- Views (MVVM): `Sources/OpenZeus/Views/`
- Services: `Sources/OpenZeus/Services/`
- Tests: `Tests/OpenZeusTests/`

## GSD Planning

If using Get-Shit-Done workflow:
- Project state: `.planning/STATE.md`
- Roadmap: `.planning/ROADMAP.md`
- Quick tasks: `.planning/quick/`

## What to Avoid

- Do not introduce DispatchQueue, NSLock, or Combine `sink` — use `async/await` and actors
- Do not use SwiftData — the project uses GRDB; keep all persistence in `AppDatabase`
- Do not add Xcode `.xcodeproj` files — this is a pure SPM project

## Automated Visual Verification

For UI/layout work, use `ImageRenderer` to render SwiftUI views headlessly and verify pixel positions programmatically — no manual app launching required.

**Pattern:**
1. Write a standalone `swift` script (e.g., `./_verify/check_layout.swift`) that:
   - Defines a minimal mock view replicating only the relevant layout (hardcode data, skip DB/actors)
   - Renders it via `ImageRenderer` inside a minimal `NSApplication` bootstrap
   - Reads back the `NSBitmapImageRep` and checks pixel positions/colors against expected values
   - Exits `0` on pass, `1` on fail with a descriptive message
2. Run it with `swift ./_verify/check_layout.swift`
3. Keep iterating until it passes before considering the UI task done

**Key techniques used:**
- `NSApplication.shared` + `app.setActivationPolicy(.prohibited)` + `Task { @MainActor in ... }` + `app.run()` to bootstrap SwiftUI rendering
- `ImageRenderer(content:).nsImage` → `NSBitmapImageRep` → `colorAt(x:y:)` for pixel inspection
- Use solid, distinguishable colors (e.g., `.blue`, `.red`) in mock views so pixels are easy to identify
- `ScrollView` does not render inside `ImageRenderer` headlessly — substitute a plain `HStack` to verify layout logic
- Check rightmost/leftmost content pixel as a fraction of total width; assert it falls within expected range

**Use automated verification as much as possible** for any SwiftUI layout change — it catches issues (like `Spacer` + `ScrollView` flex-space competition) that are invisible from code review alone.

## Temporary Files

When writing verification scripts or other temporary files, create them in a local `_verify/` folder inside the project root (not `/tmp`):

```bash
mkdir -p _verify
# write scripts to _verify/
swift _verify/check_something.swift
```

`_verify/` is gitignored. **If the task completes successfully, delete it:**

```bash
rm -rf _verify/
```

If the task fails or is interrupted, tell the user: "You can delete the `_verify/` folder — it contains only temporary verification scripts."
