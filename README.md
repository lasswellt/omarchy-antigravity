# Antigravity (Omarchy plugin)

Google Antigravity usage and limits in [Omarchy](https://omarchy.org),
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

- **The plugin is a `service` first.** `AntigravityService.qml` runs `bin/antigravity-usage-update` on a timer
  (default 900s, `triggeredOnStart`), publishing the record to
  `~/.local/state/omarchy/agents/usage/antigravity.json`. The built-in Agents
  panel discovers it by filename, so **Antigravity shows up in that panel next
  to Claude and Codex** — no UI of our own, no second bar icon.

  Force a refresh:
  ```bash
  omarchy-shell lasswellt.antigravity refresh   # or: bin/antigravity-usage-update
  ```
  (The bar widget, when enabled, answers on `lasswellt.antigravity.panel` —
  two IpcHandlers cannot share one target.)

- **Known cosmetic gap:** the Agents panel resolves marks from
  `$OMARCHY_PATH/shell/plugins/agents/assets/<id>.svg` with no record-driven
  path, and that directory is root-owned. So while *our* panel shows the mark
  in `assets/`, the Agents panel logs one `Cannot open: …/antigravity.svg`
  warning per draw and falls back to the bar glyph. Harmless, and not fixable
  from a third-party plugin.

- **An optional bar widget** (`Panel.qml`) gives Antigravity its own icon and
  panel: the four limit meters with reset countdowns, conversation counts, and
  a seven-day chart with today bolded. It reads the same published record, so
  its numbers cannot drift from the Agents panel's.

  It is **not** in the default layout, because the Agents panel already shows
  this data. To use it instead:

  ```bash
  # add the icon (the layout lives in ~/.config/omarchy/shell.json)
  omarchy bar put lasswellt.antigravity --section right

  # then hide the duplicate tab in the built-in Agents panel
  omarchy bar set omarchy.agents providers '{"antigravity": {"enabled": false}}' --json
  ```

  `omarchy bar put` is a no-op if the plugin is already referenced anywhere in
  `shell.json` (its service entry counts), in which case add
  `{"id": "lasswellt.antigravity"}` to `bar.layout.right` by hand.

  Panel keys: `j`/`k` scroll, `r` refresh, Tab to the neighbouring panel, Esc
  close. Middle-click the icon to refresh without opening it.

## Layout

```
manifest.json    plugin manifest (id lasswellt.antigravity)
AntigravityService.qml   service entry point — publishes the record on a timer
Panel.qml        optional bar widget entry point
bin/
  antigravity-usage   prints the Omarchy agent usage record
findings.md      research notes — read this first
roadmap.md       architecture decision + what's left to build
tools/           research tooling (not shipped behaviour) — see tools/README.md
assets/
  antigravity.svg, antigravity-light.svg   panel mark (dark/light surfaces)
tests/
  smoke                fixture-based tests for bin/antigravity-usage
  qml                  qmllint over both QML entry points, plus assets
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
tests/smoke && tests/qml                         # run tests first
git add -A && git commit -m "..."
omarchy plugin update lasswellt.antigravity --yes # pushes the change live
```

Check `journalctl --user _PID=$(pgrep -x quickshell)` afterward for QML errors.

Two things that cost time the first time round:

- **Adding a *new* QML file needs `omarchy restart shell`, not just
  `plugin update`.** Qt caches the plugin directory listing, so a file that
  did not exist when the shell started is reported as
  `File name case mismatch` — which has nothing to do with case. Editing an
  existing file hot-reloads fine.
- **The first collection after a cold boot can take 15s+.** Each `agy` call
  spawns a 218 MB binary; steady state is ~4s. Don't conclude the service is
  dead because the record hasn't appeared yet.
- **`omarchy restart shell` refuses while the session is locked**, and says so
  only on stderr — every restart silently becomes a no-op. Unlock first.
- **A already-open panel keeps its old QML** across `plugin update`. Restart
  the shell before judging a layout change; twice I "fixed" a layout that had
  simply not reloaded.
- **Don't rewrite history on a branch the installed clone tracks.** A squashed
  commit it had already pulled orphans its HEAD and breaks `plugin update`
  with "cannot fast-forward". Recover with
  `git -C ~/.config/omarchy/plugins/<id> fetch && git reset --hard origin/master`.

## Install (fresh machine)

```bash
omarchy plugin add https://github.com/lasswellt/omarchy-antigravity.git --enable
```

Needs `jq`, `sqlite3`, and the [Antigravity CLI](https://antigravity.google/docs/cli/install):

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

Without `agy` the plugin still reports local activity from
`conversation_summaries.db`; it just has no limits to show.
