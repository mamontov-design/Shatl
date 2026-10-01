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

## Interface copy

- Russian is the source; every key exists in all seven languages
  (`LocalizationCoverageTests`). The owner's full copy guide, with the
  dictionary and approved wordings, lives outside the repository in
  `Shatl-Internal/Docs/Shatl Copy Guide.ru.md`; read it before changing any
  visible string when it is available.
- Write about the object and the result, not about the app: "Shatl" appears
  only where the reader could not tell which app is meant
  (`CopyTypographyTests` keeps the list).
- An error says what happened, the likely cause, and an action that really
  fixes it and is on screen. No bare "try again".
- Never place non-breaking spaces by hand: write plain text and run
  `Scripts/typograph.sh`, which applies the per-language rules in
  `Tests/Typography/ShatlTypograph.swift`; the tests fail on an untypeset
  string. Counts take plural keys through `L10n.pluralKey`, never "file(s)".

## Invariants

- `session.json`, archived torrents, bookmarks, and fastresume data are durable
  state, not cache. A failed initial load must stay fail-closed and must not be
  overwritten until the user explicitly starts with an empty list.
- Unit tests are hosted in `Shatl.app`, so a test run also runs `ShatlApp`.
  Under XCTest (`ShatlLaunchMode.unitTestHost`) the host must stay inert: no
  `AppEnvironment.live()`, no bootstrap, no Sparkle, no telemetry. Otherwise
  every test run touches the user's real session and preferences.
- One live Shatl per data folder. `ShatlMain` takes `Shatl.lock` (`flock`,
  close-on-exec) in the data folder root before SwiftUI starts; a second copy
  builds no store, hands its torrents to the first copy and quits. Cleanup must
  never delete the lock file or the folder root.
- Keep the 1 Hz runtime loop free of filesystem walks and heavy SwiftUI work.
  A card is a pure function of `TorrentRowInputs` and is rebuilt only when
  they change: anything new a card shows must enter through them, and the
  tick must not scan the list per card (look records up through the ID index).
- Preserve manual Start/Stop semantics; do not enable libtorrent `auto_managed`
  or add fake cache controls.
- Payload deletion belongs to `TorrentPayloadDeletionService` and
  `SecureTorrentPayloadFileSystem`, never libtorrent `delete_files` or recursive
  Foundation deletion. Unsafe or partial deletion must remain visible to the
  user.
- The main torrent list intentionally uses stable IDs, lightweight row
  presentation, and a plain `VStack`, not `List` or `LazyVStack`. Every card is
  built once and scrolling moves finished layers; a `LazyVStack` builds and
  lays out cards as they scroll in, and on a short list every scroll started
  with a jerk (bisected in September 2026). Downloads are usually few, so the
  plain stack stays even though it tires on dozens of cards. Card guards:
  hover waits for a resting pointer (`TorrentCardHoverTiming`), the progress
  bar moves in steps (`TorrentProgressBarSteps`), speed icons change level
  with hysteresis (`TransferSpeedLevel`), only the download speed bounces, and
  metric shadows sit under the plate so changing digits leave the blur alone.
  With many active downloads the cards leave out their costliest motion
  (`CardSimplificationLevel`: from 15, no bounce and no metric shadows, a
  bar that steps 5 % and a download speed that shows its level icon alone,
  its number under the pointer, `foldsDownloadSpeed`; from 25, digits also
  stop rolling and the bar steps 10 %); the level enters each card through
  its row inputs. A finished
  download's card is one line, the status badge beside the title naming the
  status under the pointer (`TorrentRowState.usesFinishedLayout`). Cards
  built for finished downloads, at launch too, start on one line without
  animation; a card that finishes in view takes `TorrentCardFinishStage`
  steps one after another, and goes back in one move. If a hang returns,
  sample it first. The large add-review file tree may use its separate
  cached/flattened `LazyVStack` path.
- Release builds must keep file diagnostics disabled. Debug settings and the
  Debug menu stay behind `#if DEBUG`.
- Any source change makes existing ZIP, DMG, appcast signatures, and release
  metadata stale until they are rebuilt and verified.
- Never publish the repository, landing, release assets, telemetry changes, or
  updater feed unless the user explicitly requests publication.
