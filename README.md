# Antigravity (Omarchy plugin) — scaffold

An [Omarchy](https://omarchy.org) bar widget for Google Antigravity,
modeled structurally on
[omarchy-tesla](https://github.com/nixfred/omarchy-tesla) and on Omarchy's
own built-in Agents bar plugin.

**Read [`findings.md`](findings.md) first.** It has everything learned
about where Antigravity keeps local state, what's actually readable
without reverse engineering, and what is explicitly out of scope. This
README is just structure and the dev loop.

## Status

- `Panel.qml` renders a placeholder "AG" bar icon. Not yet wired to real
  data — that's the next step (see `findings.md`, "Next steps").
- `bin/antigravity-usage` works today: it queries
  `~/.gemini/antigravity/conversation_summaries.db` directly and prints a
  JSON record (conversation counts, last-active time, recent conversations).
  Run it directly to see current output:
  ```bash
  bin/antigravity-usage | jq .
  ```
- `tests/smoke` exercises that script against a fixture DB
  (`tests/fixtures/conversation_summaries.sql`), never the user's real one.

## Layout

```
manifest.json    plugin manifest (id lasswellt.antigravity)
Panel.qml        bar widget entry point (placeholder content)
bin/
  antigravity-usage   reads conversation_summaries.db, prints JSON
findings.md      research notes — read this first
tests/
  smoke                fixture-based test for bin/antigravity-usage
  fixtures/
    conversation_summaries.sql   fake rows, real schema
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
