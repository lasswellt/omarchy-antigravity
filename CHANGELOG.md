# Changelog

## 0.2.0 — 2026-09-18

First working release. Antigravity now appears in Omarchy's built-in Agents
panel alongside Claude and Codex.

### Added

- `bin/antigravity-usage` — emits the Omarchy agent usage record. Limits come
  from `agy -p "/usage" --output-format json` (four buckets: weekly and
  5-hour, for Gemini and for Claude/GPT); session counts come from
  `conversation_summaries.db` for both the `agy` CLI and the IDE, merged into
  one record because the quota is account-wide.
- `bin/antigravity-usage-update` — validates and atomically publishes that
  record to `~/.local/state/omarchy/agents/usage/antigravity.json`.
- `AntigravityService.qml` — runs the collector on a timer (default 900s,
  `triggeredOnStart`) and answers
  `omarchy-shell lasswellt.antigravity refresh`.
- `tests/smoke` — 42 checks against fixture databases and a stubbed `agy`,
  including a guard that fails if `agy`'s JSON envelope changes shape.
- `tools/` — `carve.py` / `fmt.py` recover Antigravity's embedded protobuf
  schemas from the `language_server` binary; `probe-language-server` calls the
  IDE's local Connect RPCs.
- `roadmap.md` — architecture, the record contract, and the extracted schemas.

### Changed

- **The plugin is now a `service`, not a `bar-widget`.** The Agents panel is
  the display, so a second bar icon would be redundant. `Panel.qml` is kept
  but is no longer an entry point.
- Collector output moved from a bespoke JSON shape to the Omarchy record
  contract.
- Test fixtures now reproduce the exact stored timestamp format (nanosecond
  precision, `+00:00`) instead of a bare `datetime('now')` that Antigravity
  never writes.

### Fixed

- Sign-in state is no longer inferred from `~/.gemini/google_accounts.json`,
  which belongs to the Gemini CLI and reported "signed in" for a signed-out
  Antigravity.
- The collector resolves `agy` itself, falling back to `~/.local/bin/agy`. A
  Quickshell-spawned process does not source the shell profile that puts it on
  `PATH`.

### Known gaps

- Token totals are always zero: `agy` reports usage per run with no cumulative
  store to read.
- The Agents panel looks for its mark in the root-owned first-party assets
  directory, so the shell logs one `Cannot open: …/antigravity.svg` warning
  per draw and falls back to the bar glyph.

## 0.1.0 — 2026-09-18

Scaffold only: manifest, placeholder `Panel.qml`, and the research in
`findings.md`.
