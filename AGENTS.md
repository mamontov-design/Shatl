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

## What shows what

Before changing one of these, check every place it shows up; a text that
promises behaviour is checked against the code in `CopyPromiseTests`. When
something new shows a part listed here, add the place to its line.

- Download card (`TorrentCardView`): the list (`TorrentListView`), and the
  demo card (`TorrentCardPreviewView`) in Settings → Appearance and in the
  onboarding's expanded-card step; Figma `components / torrent-card`. Its
  corner radius also shapes the demo cards' shadow.
- Metric formats (`MetricsDisplayRules`, `Metrics`): the card's speed set,
  expanded groups and speed chips; the add window's file sizes, summary and
  low-space text (`AddTorrentSummaryByteFormatter`, `DiskSpaceCheck`); the
  "Точность значений" popover, whose examples must be what the formatter
  shows; README ("simplified metrics").
- Metric plates (`ShatlMetricSet`, `ShatlMetricItem`, `ShatlMetricGroup`):
  the card's speed set and expanded groups, the demo cards, and the add
  window's summary (`AddTorrentSummaryMetrics`), which also shows counts
  ("1 из 2", `of` / `total`) and a spinner (`isPending`); Figma
  `components / metric / metric-set` and `metric-item` (`Type=Value` /
  `Count`).
- Speed levels (`TransferSpeedLevel` thresholds): the card's speed icons and
  colours, the speed-colour legend in Settings (derived from the code), and
  the descriptions of Figma's `speed/badge/*` tokens, which name the
  thresholds.
- Status badges (`ShatlStatusBadgePalette`): the card's badge, on one line
  too, the demo cards, the monochrome appearance; Figma
  `components / torrent-card / statusBadge` and the `status/*` token
  descriptions.
- Selection mark (`ShatlSelectionMark`): the download card and the option
  cards (`ShatlSettingsInputCard`: performance modes, themes).
- Performance profiles (`LTMakePerformanceSettingsPack`): Halo's limits are
  named in `settings.downloads.performance.caption.economical` and
  `halo_notice.message`; the speedometers; README.
- Usage statistics (`UsageTelemetryPayload`): `DataCollectionInfo` in
  Settings → Data and in the onboarding's statistics step, the inspectable
  payload, README "Privacy", the privacy policy on the site, the Privacy
  Manifest. Any change to what is sent goes into all of them.
- Message in the middle of a window (`ShatlMessageBlockPrimary`): session
  load and its errors, the empty search, the drop screen, the add window's
  messages, and in the add window's summary the low-space message (`tone:
  .error`, full width, parts changing in turn, `ShatlMessageParts`).
- Brand marks (`ShatlWordmark`: the type wordmark `ShatlTypeWordmark` and
  the logomark): the empty list, where the box follows the mark shown
  (`heightFollowsMark`) and the window's title fades with the wordmark
  (`MainWindowTitle`); Settings → About, one box for both marks; the
  onboarding, the logomark alone. The wordmark's colours
  (`ShatlColor.Wordmark`: four hues, grey in monochrome, the macOS accent
  mixed by weight) and timings (`ShatlMotion.wordmark*`,
  `brandMarkChangeDuration`); under Reduce Motion both marks stand still.
  Its four hues also tint the Settings option cards' wink
  (`ShatlColor.InputCardActivationPulse`).
- Link button (`ShatlLinkButton`): the About footer and the "Лицензии"
  button (name alone, no symbol); on a popover, `onPopover()`, Figma's
  "Contrast on Transparent" variants: the licences popover, the monochrome
  popover.
- Third-party code: `THIRD-PARTY-NOTICES.md`, `Vendor/Licenses` and
  `ShatlThirdPartyComponent` (`ThirdPartyLicensesTests`).
- Setting names reused elsewhere: the onboarding's last step names Settings
  sections by the same keys (`settings.appearance.metrics.section`,
  `settings.downloads.performance.section`).
- Any visible string: all seven languages, and §8 of the owner's Copy Guide
  when the wording is approved.

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
  with hysteresis (`TransferSpeedLevel`) and change it quietly, a badge
  loses its fill for "Простаивает" only after a spell without speed and
  takes it back on held speed (`TransferActivity`), never second by second,
  and metric shadows sit under the plate so changing digits leave the blur alone.
  A status badge is filled only while the download works ("Скачивается",
  "Проверяется", "Раздаётся"); one that stands, has finished ("Скачана") or
  failed ("Ошибка") wears an outline without a fill, and the error's
  outline stays red in the monochrome appearance (`StatusBadgePaletteTests`).
  A card never shows a zero (the owner's product decision): a metric with
  nothing to count is hidden, not shown as "0" seeds or peers or "0 КБ/с".
  The cells follow the numbers at once; only the title over seeds and peers
  waits for a change to hold before it names "Сиды" or "Пиры" alone
  (`PeerGroupTitle`: 3 s to come, 5 s to go, as "Простаивает"). Over one
  lone cell of 1 it says "Сид" or "Пир" once the 1 has held 3 s, and goes
  back to the plural the moment the number changes; over 21 it stays plural,
  whatever a language's plural rules say.
  With many active downloads the cards leave out their costliest motion
  (`CardSimplificationLevel`: from 10, no metric shadows, a
  bar that steps 5 % and a download speed that shows its level icon alone,
  its number under the pointer, `foldsDownloadSpeed`; from 25, digits also
  stop rolling and the bar steps 10 %); the level enters each card through
  its row inputs. A finished
  download's card is one line, the status badge beside the title naming the
  status under the pointer (`TorrentRowState.usesFinishedLayout`). Cards
  built for finished downloads, at launch too, start on one line without
  animation; a card that finishes in view takes `TorrentCardFinishStage`
  steps one after another, and goes back in one move. Its expand button and
  selection mark stand in the middle of its row, and at the top once the
  card is open, as on a card of several lines; they move only a second
  after the click (`ShatlMotion.cardControlsSettleDelay`), once the expand
  symbol has been replaced in place: a symbol replaced while it moves draws
  artefacts. If a hang returns,
  sample it first. The large add-review file tree may use its separate
  cached/flattened `LazyVStack` path.
- The list is moved with a card that expands, and to its new end after
  cards leave, through `TorrentListScrollDriver`, which sets the scroll
  view's clip origin in AppKit. An animated SwiftUI `scrollTo` (or
  `ScrollPosition`) is lost when the next request or the 1 Hz redraw
  interrupts it (measured in October 2026). After cards leave the driver is
  given a goal, the end to stand at, never a place: it works the place out
  anew with every frame of the display and moves by the system's spring,
  keeping its speed when the goal changes. What is around the list changes
  while it moves: the selection bar under the toolbar takes the list from
  under the toolbar and back, cards leave one after another. A list the
  system has moved for that is not a list scrolled by hand; the driver gives
  way only when the list moves with nothing around it changed. Only the card
  that expands reports its frame; the driver does nothing between requests.
  A card that expands partly out of sight is brought into sight along the
  curve it grows by, from the frame it begins to grow in, never in one step
  before it. Content that shrinks under a list scrolled down pushes it there
  in one frame, so room is kept under the content while cards leave or the
  room under the speed chips goes with them, until the driver says the list
  stands at its new end. When the chips come under a list at its end, the
  driver takes it down to the new end, so the last card stays clear of them.
- Arrow keys do not select cards. Every step drew the whole list anew, and
  with 15 active downloads a held arrow gave one frame of 60-70 ms per step
  (measured in October 2026; the figures are in the owner's chronicle). ⌘A,
  Esc, Space and Delete work on the list as before. Do not bring the arrows
  back before the list stops being rebuilt on every change of the store.
- From two to nine selected cards wear their numbers in place of the check
  mark, in the order they were selected; from ten the bar under the toolbar
  names the count and the cards wear check marks (`TorrentSelectionCount`).
- In the add window nothing is shown or hidden through an effect of its own
  over the settings plate: no opacity, scale or blur on the files stage. For
  as long as such an effect lasts, SwiftUI keeps the plate's labels in one
  AppKit view with its text field and switch, and there they are at times
  drawn upside down (the owner's recordings, September and October 2026).
  The files come out from under a cover of the window's own colour and go
  back under it, which is why the add window has a fixed background
  (`ShatlColor.backgroundWindow`) and not the system's, tinted by the
  wallpaper. The files' half is a step darker (`backgroundAddWindow`) and
  shows from under the same cover. `AddTorrentReviewAppearanceTests`
  watches where the labels sit.
- Colours follow Figma. `ShatlPalette` (`Palette.swift`) holds the Radix
  values of Figma's Palette collection, `ShatlColor` (`Colors.swift`) the
  tokens of its UI collection under their iOS code syntax names, each a
  light and dark pair. Figma's macOS, Graphics and System collections paint
  what Shatl does not draw itself (system chrome, artwork, the file) and have
  no counterpart here. Views use only `ShatlColor`; the one colour asset is
  `AccentColor`, which the system needs. Change a colour in Figma first, then
  point the token at the same step here; `ColorTokenTests` rejects colours
  written into views.
- Release builds must keep file diagnostics disabled. Debug settings and the
  Debug menu stay behind `#if DEBUG`.
- Any source change makes existing ZIP, DMG, appcast signatures, and release
  metadata stale until they are rebuilt and verified.
- Never publish the repository, landing, release assets, telemetry changes, or
  updater feed unless the user explicitly requests publication.
