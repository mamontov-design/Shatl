# Shatl agent guide

## Scope and workflow

- These instructions apply to the whole repository.
- Start by checking `git status` and preserve all existing user changes. Do not
  discard, rewrite, or fold unrelated work into the task.
- Prefer narrow fixes backed by a focused test. For restore, filesystem,
  deletion, or lifecycle bugs, establish the event order with a trace or a
  regression test before changing core behavior.

## Project map

- `App/SwiftUIApp`: SwiftUI/AppKit presentation and user flows.
- `App/ShatlCore`: models, `AppStore`, persistence, services, and presentation
  rules. Views must not talk to libtorrent directly.
- `App/LibtorrentShim`: the only libtorrent/C++ boundary.
- `Tests`: XCTest regression suite for both product behavior and safety rules.
- The landing page is developed outside this repository. Do not add a landing
  or Pages workflow here unless the user explicitly puts it in scope.

## Build and verification

The project targets Apple Silicon and macOS 26+ and is built with Xcode 27. If
`xcode-select` points at CommandLineTools, use Xcode explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Shatl.xcodeproj -scheme Shatl \
  -destination 'platform=macOS'

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project Shatl.xcodeproj -scheme Shatl \
  -configuration Release -destination 'platform=macOS'
```

Run the focused test first, then the full suite when the change affects core,
persistence, deletion, restore, or shared UI state.

## Invariants

- `session.json`, archived torrents, bookmarks, and fastresume data are durable
  state, not cache. A failed initial load must stay fail-closed and must not be
  overwritten until the user explicitly starts with an empty list.
- Unit tests are hosted in `Shatl.app`, so a test run also runs `ShatlApp`.
  Under XCTest (`ShatlLaunchMode.unitTestHost`) the host must stay inert: no
  `AppEnvironment.live()`, no bootstrap, no Sparkle, no telemetry. Otherwise
  every test run touches the user's real session and preferences.
- Keep the 1 Hz runtime loop free of filesystem walks and heavy SwiftUI work.
- Preserve manual Start/Stop semantics; do not enable libtorrent `auto_managed`
  or add fake cache controls.
- Payload deletion belongs to `TorrentPayloadDeletionService` and
  `SecureTorrentPayloadFileSystem`, never libtorrent `delete_files` or recursive
  Foundation deletion. Unsafe or partial deletion must remain visible to the
  user.
- The main torrent list intentionally uses stable IDs, lightweight row
  presentation, and `VStack`, not `List` or `LazyVStack`. The large add-review
  file tree may use its separate cached/flattened `LazyVStack` path.
- Release builds must keep file diagnostics disabled. Debug settings and the
  Debug menu stay behind `#if DEBUG`.
- Any source change makes existing ZIP, DMG, appcast signatures, and release
  metadata stale until they are rebuilt and verified.
- Never publish the repository, landing, release assets, telemetry changes, or
  updater feed unless the user explicitly requests publication.
