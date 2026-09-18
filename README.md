# Antigravity (Omarchy plugin) — scaffold

An [Omarchy](https://omarchy.org) bar widget for Google Antigravity,
modeled structurally on
[omarchy-tesla](https://github.com/nixfred/omarchy-tesla) and on Omarchy's
own built-in Agents bar plugin.

**Read [`findings.md`](findings.md) first** for where Antigravity keeps local
state and what's readable, then [`roadmap.md`](roadmap.md) for the plugin
architecture decision, the Agents record contract, and the order of work.
`roadmap.md` also corrects four conclusions in `findings.md` that a second
research pass overturned. This README is just structure and the dev loop.

## Status

- `bin/antigravity-usage` is **done**. It prints one Omarchy agent usage
  record (`roadmap.md` §2) covering both the `agy` CLI and the IDE:

  ```bash
  bin/antigravity-usage | jq .
  ```

  Limits come from `agy -p "/usage" --output-format json` — four buckets
  (weekly + 5-hour, for Gemini and for Claude/GPT). Session counts come from
  `conversation_summaries.db` for both surfaces, merged into one record
  because the quota is account-wide. Requires `jq` and `sqlite3`; degrades
  to local stats when `agy` is missing or signed out.

- `tests/smoke` — 42 checks against fixture databases and a stubbed `agy`
  (`tests/fixtures/agy-stub`), never the real `~/.gemini`. Includes a guard
  that fails loudly if `agy`'s JSON envelope changes shape, since the whole
  limits path rests on slash commands expanding in print mode.

- **Next:** have the plugin write that record to
  `~/.local/state/omarchy/agents/usage/antigravity.json` on a timer. The
  built-in Agents panel adopts it by filename, so Antigravity appears
  alongside Claude and Codex with no UI work (`roadmap.md` §1).

- `Panel.qml` still renders a placeholder "AG" bar icon — the standalone
  panel comes after the collector is wired up.

## Layout

```
manifest.json    plugin manifest (id lasswellt.antigravity)
Panel.qml        bar widget entry point (placeholder content)
bin/
  antigravity-usage   prints the Omarchy agent usage record
findings.md      research notes — read this first
roadmap.md       architecture decision + what's left to build
tools/           research tooling (not shipped behaviour) — see tools/README.md
tests/
  smoke                fixture-based tests for bin/antigravity-usage
  fixtures/
    conversation_summaries.sql   fake rows, real schema + real timestamp format
    agy-usage.json               captured `agy -p "/usage"` envelope
    agy-credits.json             captured `agy -p "/credits"` envelope
    agy-stub                     stand-in for the agy binary
```

## Dev loop

This directory is the source of truth. The installed copy at
`~/.config/omarchy/plugins/lasswellt.antigravity` is a separate git clone
pulling from this repo (or its remote, once pushed).

```bash
# after editing here
cd ~/Projects/omarchy-antigravity
tests/smoke                                      # run tests first
git add -A && git commit -m "..."
omarchy plugin update lasswellt.antigravity --yes # pushes the change live
```

The running shell hot-reloads on `plugin update`; check
`journalctl --user _PID=$(pgrep -x quickshell)` afterward for QML errors if
the bar icon doesn't look right.

## Install (fresh machine)

```bash
omarchy plugin add ~/Projects/omarchy-antigravity --enable
```
