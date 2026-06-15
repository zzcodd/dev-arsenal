# CC Token Dashboard

A menu-bar app that shows your **Claude Code token usage in real time**, by reading
the local transcript files Claude Code writes under `~/.claude/projects/`. No API, no
network — pure local file parsing.

> _Tip: it lives in your menu bar as a gauge icon + a live token count (no Dock icon).
> Add a `docs/preview.png` screenshot here if you fork it._

## Requirements

- **macOS 14+**
- **Claude Code** installed and used at least once (so there's data under `~/.claude/projects/`)
- **Swift toolchain** to build — Xcode's Command Line Tools is enough (`xcode-select --install`); no full Xcode needed

## Does it work for me? (data source)

Yes — it reads **your own** local Claude Code transcripts, resolved per-user:

- Default location is `~/.claude/projects/` (the `~` resolves to *your* home, so there's
  nothing to configure).
- If you relocate Claude Code's config via the `CLAUDE_CONFIG_DIR` env var, the app honors
  that too. (Caveat: an app launched at login by macOS doesn't inherit shell env vars, so a
  `CLAUDE_CONFIG_DIR` set in `~/.zshrc` only applies when you launch from a terminal.)

Everything stays on your machine — no network, no telemetry.

## What it does

- **Always-visible menu bar metric** — today's tokens (or cost / current session)
- **Click for a card** with:
  - Headline total + equivalent cost ($)
  - 4-way token split: input / output / cache write / cache read
  - 7-day trend bar chart
  - Per-project breakdown (the second-level view)
  - Rolling last-5h usage
- **Real time** — a FSEvents watcher re-parses incrementally the instant a transcript
  changes, so the number climbs while you work
- **Settings** — switch the menu bar metric, launch at login, and a "notify when today
  exceeds N" threshold alert

> The `$` figure is an *equivalent market value* from a static price table — on a
> subscription it is **not** your actual bill. See `Sources/CCTokenCore/PricingTable.swift`
> (`// TODO: verify pricing`).

## Build & run

Requires the Swift toolchain (Command Line Tools is enough — no full Xcode needed).

```bash
# 1. Verify the data pipeline (M0) — prints today's usage to the terminal
swift run cctoken-cli            # or: cctoken-cli week | all

# 2. Run the tests
swift test

# 3. Build the double-clickable app and launch it
./scripts/build-app.sh
open build/CCTokenDashboard.app

# (optional) install to /Applications
./scripts/build-app.sh --install
```

The app has no Dock icon — look for the gauge glyph + number in the **menu bar**.
Quit via the power button in the popover's footer.

## How it works

```
~/.claude/projects/**/*.jsonl   ← Claude Code writes one JSON object per line
        │
   FSEventsWatcher  ──(file changed)──▶  JSONLParser (incremental, byte-offset)
        │                                       │
        ▼                                       ▼
   UsageStore  ◀──────  Aggregator (dedupe → filter by range → group)
        │                       │
        ▼                       ▼
   menu bar text          AggregatedUsage ──▶ SwiftUI PopoverView
```

Each `type: "assistant"` line carries a `message.usage` object
(`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
`output_tokens`) plus `model`, `timestamp`, and `cwd` (used as the project name).
Duplicate lines (same `message.id` + `requestId`, with identical usage) are dropped
so totals aren't double-counted.

## Layout

```
Sources/
  CCTokenCore/         pure logic, unit-tested, no UI
    Models.swift         UsageRecord, AggregatedUsage, TimeRange
    JSONLParser.swift    incremental byte-offset parser
    Aggregator.swift     dedupe + filter + group by day/project/model
    PricingTable.swift   model → $ table
    Scanner.swift        locate transcript files
    Formatting.swift     "2.4M" / "$3.20"
  cctoken-cli/         M0 terminal verification tool
  CCTokenDashboard/    the menu bar app (M1–M3)
    App.swift            MenuBarExtra entry point
    UsageStore.swift     state, scanning, notifications
    FSEventsWatcher.swift  filesystem watcher
    PopoverView.swift    SwiftUI card + settings
    LaunchAtLogin.swift  SMAppService toggle
Tests/CCTokenCoreTests/  swift-testing suite
scripts/build-app.sh     assembles the .app bundle
```

See [PRD.md](PRD.md) for the full design and the milestone breakdown (M0–M3).
