# Findings

Research notes from building the dev scaffold, before any real widget logic
was written. Read this first in a fresh session — it's the reason the
project is shaped the way it is.

## Goal

An [Omarchy](https://omarchy.org) bar widget for Google Antigravity
(`/usr/bin/antigravity`, AUR package `antigravity`, an Electron/VS-Code-fork
IDE), modeled structurally on
[omarchy-tesla](https://github.com/nixfred/omarchy-tesla) and on Omarchy's
own built-in Agents bar plugin (`/usr/share/omarchy/shell/plugins/agents`,
which does this for Claude Code / Codex / Fireworks).

Antigravity was **not** added as a new collector to the built-in Agents
plugin. That plugin's provider list (`claude`, `codex`, `fireworks`) is
hardcoded in its own `manifest.json` defaults and it's first-party
(`/usr/share/omarchy/...`, not user-editable without patching the system
install). Antigravity is also not really "a CLI coding agent" the way
Claude/Codex are — it's a GUI IDE — so a separate, standalone plugin
(`lasswellt.antigravity`) is the right shape, installed the normal
third-party way via `omarchy plugin add`.

## What's installed

- `antigravity` 2.14.0-1, AUR package (`yay -S antigravity`), binary at
  `/usr/bin/antigravity` → symlink to `/opt/Antigravity/antigravity`
  (Electron app, product name `Antigravity`).
- Desktop entry: `Name=Antigravity`, `StartupWMClass=Antigravity`,
  `Icon=antigravity`.

## Where it keeps data

Two separate locations:

- **`~/.config/Antigravity/`** — standard Electron `userData` dir (cache,
  cookies, IndexedDB, etc. — not interesting) plus:
  - `logs/main.log` — Electron/app-level log.
  - `logs/language_server.log` — the interesting one. This is stderr/stdout
    from the Go-based `language_server` backend process
    (`/opt/Antigravity/resources/bin/language_server`), logged at Go's
    `glog`-style verbosity. Very chatty (tens of thousands of lines/session).
  - `app_storage.json` — trivial UI flags (e.g. `ide-install-wizard-shown`).

- **`~/.gemini/`** — **shared with the Gemini CLI**, not Antigravity-specific.
  This is the important one:
  - `oauth_creds.json` — OAuth token (sensitive; never read/print this, and
    never commit anything derived from it).
  - `google_accounts.json` — `{"active": "<email>", "old": []}`. Safe to
    read to check sign-in state without touching the token itself.
  - `settings.json` — `{"security": {"auth": {"selectedType":
    "oauth-personal"}}}`.
  - `antigravity/conversation_summaries.db` — **SQLite, plain schema, no
    reverse engineering needed.** See below.
  - `antigravity/conversations/<uuid>.db` — one SQLite file per conversation.
    Has real structure (`steps`, `gen_metadata`, `executor_metadata`,
    `trajectory_meta`, `battle_mode_infos`, `parent_references`,
    `trajectory_metadata_blob`) but the payload columns (`gen_metadata.data`,
    `steps.metadata`/`step_payload`/etc.) are **raw protobuf blobs with no
    `.proto` schema shipped anywhere in the install**. This is where token
    counts / model names / per-step cost would presumably live, but reading
    them means reverse-engineering an undocumented, versioned wire format.
    Treat as **not accessible** until/unless someone does that RE work.
  - `antigravity/antigravity_state.pbtxt` — another protobuf (text-format
    this time). Didn't investigate contents yet.
  - `antigravity/crashes/` — crash logs, empty in our sessions (clean
    shutdowns both times).
  - `tmp/work/logs.json`, `history/work/` — present but empty (`[]`) in
    testing so far; unclear what populates them.
  - `config/projects/`, `config/mcp_config.json`, `config/sidecars` — project
    trust and MCP config, not usage data.

## `conversation_summaries.db` schema (the usable part)

```sql
CREATE TABLE `conversation_summaries` (
  `conversation_id` text,
  `title` text NOT NULL DEFAULT "",
  `preview` text NOT NULL DEFAULT "",
  `step_count` integer NOT NULL DEFAULT 0,
  `last_modified_time` datetime NOT NULL,
  `workspace_uris` text NOT NULL,
  `status` text NOT NULL DEFAULT "",
  `source` text NOT NULL DEFAULT "",
  `project_id` text NOT NULL DEFAULT "",
  `agent_name` text NOT NULL DEFAULT "",
  `parent_conversation_id` text NOT NULL DEFAULT "",
  `nesting_depth` integer NOT NULL DEFAULT 0,
  `battle_id` text NOT NULL DEFAULT "",
  `winning_conversation_id` text NOT NULL DEFAULT "",
  `not_fully_idle` numeric NOT NULL DEFAULT false,
  `killed` numeric NOT NULL DEFAULT false,
  `last_user_input_time` datetime NOT NULL,
  `last_user_input_step_index` integer NOT NULL DEFAULT -1,
  `app_data_dir` text NOT NULL DEFAULT "",
  `raw_summary` blob,
  `group_id` text NOT NULL DEFAULT "",
  PRIMARY KEY (`conversation_id`)
);
CREATE INDEX idx_conversation_summaries_last_user_input_time
  ON conversation_summaries(last_user_input_time);
CREATE INDEX idx_conversation_summaries_last_modified_time
  ON conversation_summaries(last_modified_time);
```

`raw_summary` is itself a blob (probably protobuf too — not decoded), but
every other column is plain text/int/datetime and queryable with vanilla
SQL. This is enough for a Claude-style "local stats" tab: conversation
counts (today / last 7 days / all-time), last-active timestamp, titles,
workspace paths, step counts as a rough activity proxy.

## Auth / tier signal

`language_server.log` shows the backend talks to Google's **Cloud Code /
Code Assist API** (the same backend behind Gemini Code Assist and Gemini
CLI), not a bespoke Antigravity API:

```
--api_server_url https://generativelanguage.googleapis.com
--cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com
```

There's an explicit tier concept in the auth code:

```
[AuthProvider] SetUserTier called with userTier: "", tierDisplayName: ""
```

This is the closest analog to Claude's "Max 20x" / "Pro" plan label. **In
both test sessions so far it came back empty** — never observed a populated
value. Unconfirmed whether:

- it populates after a longer/warmer session,
- Code Assist exposes any numeric quota/rate-limit data at all (Claude Code
  has a documented-enough OAuth usage endpoint; nothing equivalent has been
  found here yet), or
- it's only ever a plan *name*, no percentage/limit meter like Claude's.

**Before building a quota meter, re-check this field after a longer signed-in
session**, and grep `language_server.log` for `SetUserTier` again — if it's
still always empty, a Claude-style limits meter is probably not buildable
and the widget should stick to activity stats + a static "signed in as
X" line.

## Scope recommendation

1. **Buildable now, high confidence:** an activity tab reading
   `conversation_summaries.db` directly (session counts, last active,
   recent conversation titles/workspaces) — same spirit as Claude's local
   transcript fallback, no reverse engineering required.
2. **Stretch, unconfirmed:** a real usage/limit meter like Claude's. Blocked
   on either (a) `userTier` ever populating with something meaningful, or
   (b) finding a Code Assist quota endpoint. Don't build UI for this until
   one of those is confirmed — check `language_server.log` again first.
3. **Out of scope / avoid:** decoding the protobuf blobs in
   `gen_metadata`/`steps` for token-level counts. No `.proto` source is
   shipped; this is real reverse-engineering effort against an undocumented,
   unversioned format that WILL break on Antigravity updates. Not worth it
   unless (1) and (2) both turn out insufficient and someone explicitly
   decides it's worth the maintenance burden.

## Reference: how the built-in Agents plugin does it (for comparison)

`/usr/share/omarchy/bin/omarchy-agent-usage-claude` (905 lines, Python) is
the gold-standard example of a rich collector: reads
`~/.claude/projects` transcripts (plain JSONL) for local stats, *and* hits
`https://api.anthropic.com/api/oauth/usage` (real OAuth endpoint, real
numeric rate-limit percentages) for authoritative limits. Ours can't match
the second half yet — see "Auth / tier signal" above.

## Dev environment / plugin mechanics (how Omarchy plugins work)

- Plugin dir: `~/.config/omarchy/plugins/<id>/`, one `manifest.json`
  (schemaVersion 1, `id`, `name`, `version`, `kinds`, `entryPoints`) per
  plugin. `id` must not start with `omarchy.` (reserved) and must match
  `^[A-Za-z0-9][A-Za-z0-9._-]*$`.
- `omarchy plugin add <git-or-local-path> [--enable] [--yes]` — clones (git
  clone works fine with a local filesystem path as the "url", no GitHub
  remote required) into the plugins dir, runs `omarchy-plugin-validate`,
  then enables it. The installed copy is itself a live git checkout.
- `omarchy plugin update <id> [--yes]` — pulls the plugin's git remote (or
  local path) into the installed copy. **This is the dev loop**: edit in
  `~/Projects/omarchy-antigravity`, commit, `omarchy plugin update
  lasswellt.antigravity --yes`, the running shell hot-reloads
  (`omarchy-shell shell rescanPlugins` under the hood; confirmed via
  `journalctl --user _PID=<quickshell-pid>` showing `Local plugin changed,
  reloading: lasswellt.antigravity` with no QML errors).
- `omarchy-plugin-validate <dir>` — checks manifest schema, that entry
  points exist and are relative/safe, and that **no symlinks** exist
  anywhere inside the plugin folder (`.git` excluded). Run this before every
  `plugin add`/`update` if unsure.
- QML plugins import `qs.Commons` / `qs.Ui` and extend the shared `Panel`
  base component (`/usr/share/omarchy/shell/Ui/Panel.qml`) — this works
  identically for third-party plugins, confirmed by both the built-in
  Agents plugin and the external Tesla plugin using the same imports.
  Useful base widgets: `WidgetButton`, `BarIconButton`, `KeyboardPanel`
  (`/usr/share/omarchy/shell/Ui/*.qml`).
- The live shell process is `quickshell` (find its pid with `pgrep -a
  quickshell`); its logs go to the systemd user journal
  (`journalctl --user _PID=<pid>`), not a plain log file — useful for
  catching QML load errors after every `plugin update`.

## Next steps (for the new session)

1. Re-check `SetUserTier` after a real signed-in-and-working session (see
   "Auth / tier signal") to settle whether a quota meter is possible at all.
2. Implement `bin/antigravity-usage` fully against
   `conversation_summaries.db` (schema above) — a start is already scaffolded.
3. Wire `Panel.qml` to spawn that script (Quickshell `Process`, same pattern
   as Tesla's `bin/tesla`) and render real content instead of the "AG"
   placeholder.
4. Add `tests/` fixtures (a tiny fixture SQLite DB with fake rows, no real
   conversation content) so the collector's SQL logic is tested without
   touching the user's real database.
