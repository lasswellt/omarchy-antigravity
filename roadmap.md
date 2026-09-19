# Roadmap: stub → fully fledged plugin

Research run, 2026-09-18. `findings.md` describes *where Antigravity keeps
data*; this describes *what shape the plugin should take and what's left to
build*. Four conclusions in the original `findings.md` turned out to be wrong;
they're corrected there and summarized in "What changed" below.

## What changed since the first research pass

| Original conclusion | Now |
|---|---|
| Can't hook into the built-in Agents plugin — provider list is hardcoded | **Wrong.** Proven empirically: any JSON record dropped in the usage dir gets a tab |
| No quota/limit API exists — `userTier` always empty | **Wrong.** `RetrieveUserQuotaSummary` exists on the local server; schema extracted in §3 and it fits Omarchy's `limits` contract |
| Protobuf blobs unreadable — no `.proto` shipped | **Wrong.** Descriptors are embedded in `language_server`; extractor checked in at `tools/` |
| `google_accounts.json` tells us if we're signed in | **Wrong.** That's the Gemini CLI's account. Use `GetAuthStatus` (§3a, §6) |

Net effect: the plugin needs far less reverse engineering than the first pass
assumed, and almost no bespoke UI if it goes the collector route.

**Then §0 happened and made most of the hard parts unnecessary.**

## 0. The `agy` CLI is the real target

Antigravity ships a **terminal coding agent**, `agy`, separate from the IDE and
not part of the AUR `antigravity` package. Installed with:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash   # → ~/.local/bin/agy
```

(It appends a commented `PATH` line to `~/.bashrc` and `~/.bash_profile`.)
Version here: **1.2.6**. It picks up existing Google credentials without a
separate sign-in.

This reframes the project. The original `findings.md` reasoning — "Antigravity
is a GUI IDE, not really a CLI coding agent the way Claude/Codex are" — is
exactly wrong for `agy`. It is precisely the shape Omarchy's existing
collectors target.

### Limits come straight out of the CLI as JSON

There's no `usage` subcommand, but slash commands expand in print mode
(hence the `--disable-slash-commands` flag), so:

```bash
agy -p "/usage" --output-format json
```

returns, under `.command.data`:

```json
{ "description": "Within each group, models share a weekly limit and a 5-hour limit…",
  "groups": [
    { "name": "Gemini Models",
      "description": "Models within this group: Gemini Flash, Gemini Pro",
      "buckets": [
        { "id": "gemini-weekly", "name": "Weekly Limit Remaining",
          "description": "You have used some of your weekly limit, it will fully refresh in 6 days, 23 hours.",
          "window": "weekly", "remaining_fraction": 0.9998874664306641,
          "reset_time": "2026-09-25T20:02:08Z" },
        { "id": "gemini-5h", "name": "Five Hour Limit Remaining",
          "window": "5h", "remaining_fraction": 0.99932461977005,
          "reset_time": "2026-09-19T01:02:08Z" } ] },
    { "name": "Claude and GPT models",
      "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
      "buckets": [ { "id": "3p-weekly", … }, { "id": "3p-5h", … } ] } ] }
```

That is field-for-field the `QuotaSummaryBucket` schema carved out of the
binary in §3 — `bucket_id`/`display_name`/`window`/`remaining_fraction`/
`reset_time` — just serialized snake_case by the CLI. The carving work wasn't
wasted; it's what makes this output legible and predicts what the other
variants (`remaining_amount`, `disabled`) will look like when they appear.

**Four buckets: weekly + 5-hour, for Gemini models and for Claude/GPT models.**
Strikingly close to Claude Code's session/weekly pair that Omarchy already
renders.

The call is **free**: `num_turns: 0`, `duration_seconds: 0`, and an all-zero
`usage` block — the slash command never reaches a model. Safe to run on a
refresh timer.

`agy -p "/credits" --output-format json` gives the balance shape:

```json
{ "remaining_credits": 0, "upgrade_uri": "https://antigravity.google/g1-upgrade" }
```

### Local stats: the same SQLite schema, different path

`~/.gemini/antigravity-cli/conversation_summaries.db` — schema **identical**
to the IDE's (verified by diff). So `bin/antigravity-usage`'s existing SQL
works on both with only a path change:

| Surface | Database |
|---|---|
| IDE | `~/.gemini/antigravity/conversation_summaries.db` |
| CLI | `~/.gemini/antigravity-cli/conversation_summaries.db` |

The CLI also keeps `conversations/`, `cache/conversation_metadata.json`,
`log/cli-<timestamp>.log`, and `jetski_state.pbtxt` alongside it.

### And per-run token counts are just there

Every print-mode envelope carries:

```json
"usage": { "input_tokens": 0, "output_tokens": 0, "thinking_tokens": 0,
           "cache_read_tokens": 0, "total_tokens": 0 }
```

which is the `modelUsage` bucket shape — including a `thinking_tokens` field
Omarchy's contract has no slot for.

### What this kills

- **No Connect RPC, no port discovery, no dependence on the IDE running**
  (§3's transport work). `tools/probe-language-server` is now IDE-path only.
- **No protobuf decoding for tokens** (§4), if per-run `usage` totals can be
  accumulated.
- **No `sqlite3`-only fallback** as the primary source — limits are first-class.

The collector is now, roughly:

```bash
agy -p "/usage"   --output-format json | jq '.command.data'   # → limits[]
agy -p "/credits" --output-format json | jq '.command.data'   # → balance
sqlite3 ~/.gemini/antigravity-cli/conversation_summaries.db …  # → sessions, activeDates
```

Three commands, `jq`, and `sqlite3`. A plain shell script, exactly like
Omarchy's other collectors.

### Open questions for §0

1. **Does `agy` expose cumulative token/session stats**, or only per-run
   `usage`? If only per-run, `todayTotalTokens` needs the collector to
   accumulate across runs itself — or fall back to step counts.
2. **Should the plugin report one agent or two?** The IDE and the CLI have
   separate databases and (probably) share one quota. Options: a single
   `antigravity` record merging both DBs, or `antigravity` + `antigravity-cli`
   as two tabs. Leaning single record, since the limits are account-wide and
   showing them twice would be misleading.
3. **`--disable-slash-commands` stability.** Slash-commands-in-print-mode is
   the mechanism the whole limits path rests on. Worth a comment in the
   collector and a test that fails loudly if the envelope shape changes.

## 1. The architecture decision (decide this first)

The built-in Agents panel is a pure display over a directory of JSON records.
`omarchy-agent-usage-update:7-10` states the contract outright: "Adding an
agent is adding a collector — the panel picks up any record that appears here."

That is literally true, and I tested it rather than trusting the comment:

- `agents/Main.qml:28` discovers records with
  `find ~/.local/state/omarchy/agents/usage -maxdepth 1 -name '*.json'`. No
  allowlist — the filename *is* the agent id.
- `agents/Main.qml:212-215` — `providerEnabled()` returns `true` for any id
  not mentioned in settings. Unknown providers default to **on**.
- `omarchy-agent-usage-update:55` only globs `$OMARCHY_PATH/bin/omarchy-agent-usage-*`,
  so it never runs a third-party collector — but it also never deletes a
  record it didn't write.

**Experiment:** wrote a synthetic `antigravity.json` into the usage dir and
ran `omarchy-shell omarchy.agents refresh`. The shell logged:

```
WARN scene: QML QQuickImage at .../agents/Panel.qml[423:17]:
  Cannot open: .../agents/assets/antigravity.svg
```

The panel adopted the record, built the tab, and went looking for our mark.
The record also survived the `usage-update` run untouched. (Test record
removed afterward; the usage dir is back to claude/codex/fireworks.)

So there are three routes, not one:

**Route A — collector only.** Ship `bin/omarchy-agent-usage-antigravity` that
prints the record contract, plus something to run it on a timer. We inherit
the entire Agents panel for free: hero, tier line, limit meters with reset
countdowns, tokens-by-day, tokens-by-model, subscription switching, keyboard
nav, IPC, and cross-device sync. Roughly 1,700 lines of UI we don't write.

- *Cost:* no bar mark. `assets/<id>.svg` lives in the root-owned first-party
  plugin dir, so we can't install one; the panel falls back to the bar glyph
  (that's the warning above — cosmetic, not fatal).
- *Cost:* nothing schedules our collector. `usage-update`'s timer won't touch
  it, so the plugin must run it itself.
- *Cost:* users who disable `omarchy.agents` lose Antigravity too.

**Route B — standalone bar widget.** The current path. Full control of icon,
panel, and layout; we build all of it. The reference is `agents/Panel.qml`
(942 lines) + `Main.qml` (748) + `Agent.qml` (34).

**Route C — both, from one collector.** Ship the plugin with a `service` kind
(or a timer in the bar widget) that runs our collector, writes
`~/.local/state/omarchy/agents/usage/antigravity.json`, *and* feeds our own
`Panel.qml`. One data path, two surfaces: Antigravity shows up in the Agents
panel alongside Claude and Codex for people who use it, and our standalone
widget gives it a proper mark and a dedicated panel.

**Recommendation: C, built in A-order.** Write the collector to the record
contract first — it's the same work either way, it's testable against fixtures
with no QML in the loop, and it produces something visibly working in the
Agents panel on day one. The standalone panel then becomes a presentation
layer over a data format that's already proven.

## 2. The record contract

Taken from the three live records in `~/.local/state/omarchy/agents/usage/`
and the reader in `agents/Main.qml`. Everything here is what a collector
prints on stdout as one JSON object.

```jsonc
{
  "schemaVersion": 1,
  "id": "antigravity",            // must match the filename
  "name": "Antigravity",          // display name in the hero
  "updatedAt": "<ISO8601>",
  "ready": true,                  // false → panel shows usageStatusText
  "hasLocalStats": true,
  "hasPromptStats": false,        // we have sessions, not prompts — see below
  "scope": "account",             // optional; merges by max, not sum, when synced

  "todayPrompts": 0,
  "todaySessions": 3,
  "todayTotalTokens": 0,
  "todayTokensByModel": {},

  "recentDays": [{ "date": "2026-09-18", "messageCount": 12 }],

  "totalPrompts": 0,
  "totalSessions": 3,
  "activeDays": 1,
  "activeDates": ["2026-09-18"],

  "modelUsage": {                 // per model: the four token buckets
    "<model-id>": { "inputTokens": 0, "outputTokens": 0,
                    "cacheCreationInputTokens": 0, "cacheReadInputTokens": 0 }
  },

  "limits": [                     // the meters; empty = no meter drawn
    { "label": "Session (5-hour)", "percent": 0.05, "resetsAt": "<ISO8601>" }
  ],

  "tierLabel": "",                // "Max 20x" equivalent
  "usageStatusText": "",          // shown in place of the tier line on error
  "authHelpText": "…",            // the "run X to sign in" line
  "retryAdvised": false           // endpoint unreachable → one retry in 30s
}
```

Two contract details worth knowing:

- **The tab only appears with data.** `providerHasData()`
  (`agents/Main.qml:219-224`) requires one of `totalPrompts`, `totalSessions`,
  `activeDays`, `todayPrompts`, `todaySessions`, a non-empty `limits`, or a
  `balance`. A record of all zeros draws nothing — which is the correct
  behavior for a machine that has Antigravity installed but unused.
- **`hasPromptStats: false` is the escape hatch** for our situation. Fireworks
  sets it because it has token totals but no prompt counts; we're the mirror
  case — conversation/step counts but no tokens (until §4 lands). Verify which
  panel rows it actually suppresses before relying on it.

Mapping what we can read today onto this: `conversation_summaries` rows →
`totalSessions`, rows grouped by `date(last_modified_time)` → `activeDates` /
`recentDays`, `step_count` summed per day → `messageCount`. Tokens and limits
stay zero/empty until §3 and §4.

## 3. Limits via the IDE — the fallback path

> **Superseded by §0 for the CLI.** `agy -p "/usage"` returns this same data as
> JSON with no transport work at all. Keep this section for the case where the
> plugin also wants to report on the IDE on a machine with no `agy` installed;
> the schema below is what made §0's output readable in the first place.


This is the big correction. `findings.md` concluded a Claude-style limits meter
was probably not buildable because `SetUserTier` always logged empty. The
empty tier has a much simpler explanation, and the quota API exists.

**Why the tier was empty.** The log says so 91 times:

```
error getting token source: You are not logged into Antigravity.
failed to get load code assist response: …
```

Antigravity was never signed in during either test session. `~/.gemini/oauth_creds.json`
and `google_accounts.json` belong to the **Gemini CLI**, which is signed in as
a separate thing. `SetUserTier("")` is what an unauthenticated session looks
like, not proof that the field is always empty. **Re-check after actually
signing into the IDE** — that's still the one blocking unknown.

This also means `bin/antigravity-usage` currently reports `signedIn: true`
when Antigravity is signed *out*. It's reading the wrong file. See §6.

**The API.** `strings` over `/opt/Antigravity/resources/bin/language_server`
turns up a real quota surface on Google's Code Assist internal API:

- `PredictionService.RetrieveUserQuota` and `.RetrieveUserQuotaSummary`
- REST form: `POST /v1internal:retrieveUserQuotaSummary`
- Hosts: `cloudcode-pa.googleapis.com` (prod), `daily-cloudcode-pa.googleapis.com`
  (what this install is configured against)
- `RetrieveUserQuotaSummaryResponse` has `buckets`, `groups`, `description`
- `RetrieveUserQuotaResponse` has nested `BucketInfo` (with a `Remaining`
  oneof) and `TokenType`
- Descriptors: `google/internal/cloud/code/v1internal/quota_summary.proto`,
  `entitlement.proto`, `credits.proto`

**The good part: it's also served locally.** The binary registers
`exa.language_server_pb.RetrieveUserQuotaSummaryRequest/Response` and
`_LanguageServerService_RetrieveUserQuotaSummary_Handler` — the local
language server proxies the same RPC. And the server announces its ports on
startup:

```
Language server will attempt to listen on host localhost
Language server listening on random port at 45881 for HTTPS (gRPC)
Language server listening on random port at 38149 for HTTP
```

**This matters a lot for design.** Talking to the local server means we never
touch `oauth_creds.json`, never refresh or transmit the user's token, and
never make a network call ourselves — the IDE does it, with its own auth, and
we read the answer. That is a far better security posture than the Claude
collector's (which does hold an OAuth token). Ports are random per launch, so
discovery is: parse the two port lines out of
`~/.config/Antigravity/logs/language_server.log`, newest first.

### The quota schema, extracted

Pulled out of the binary with `tools/carve.py` (see `tools/README.md`). This
is the real thing, not inference:

```proto
message RetrieveUserQuotaSummaryResponse {
  repeated QuotaSummaryBucket buckets = 1;
  repeated QuotaSummaryGroup  groups  = 2;
  string                      description = 3;
}

message QuotaSummaryBucket {
  string    bucket_id    = 1;
  string    display_name = 2;
  string    description  = 7;
  string    window       = 3;
  oneof remaining {
    float   remaining_fraction = 4;
    int64   remaining_amount   = 5;
  }
  bool      disabled     = 8;
  Timestamp reset_time   = 6;
}

message QuotaSummaryGroup {
  repeated QuotaSummaryBucket buckets = 1;
  string display_name = 2;
  string description  = 3;
}
```

**It maps onto Omarchy's `limits` contract almost field for field:**

| Omarchy `limits[]` | Antigravity |
|---|---|
| `label` | `display_name` (optionally `+ window`) |
| `percent` | `1.0 - remaining_fraction` — note Omarchy shows the fraction **used**, Antigravity reports what's **left** |
| `resetsAt` | `reset_time` |
| *(skip the bucket)* | `disabled == true` |

`remaining_amount` is the prepaid-style alternative to a fraction; if it shows
up instead, that's the `balance` shape in the Agents contract rather than a
meter. `Credits { credit_type, credit_amount, minimum_credit_amount_for_usage }`
exists in `credits.proto` with a `GOOGLE_ONE_AI` credit type, which suggests
Google One AI subscribers get the amount form.

The local wrapper is a thin passthrough, and it hands us a cache-bypass for
free — which lines up exactly with the collector's `--force` flag:

```proto
// exa.language_server_pb
message RetrieveUserQuotaSummaryRequest {
  google.internal.cloud.code.v1internal.RetrieveUserQuotaSummaryRequest request = 1;
  bool force_refresh = 2;
}
```

**Conclusion: a Claude-style limits meter is buildable.** The data model is
there and it fits the contract. What's left is transport, not schema.

### Transport: it's Connect, so the collector stays a shell script

The backend serves its RPCs with [connectrpc.com/connect](https://connectrpc.com)
(`Connect-Protocol-Version`, `Connect-Timeout-Ms` et al. are all in the
binary). It advertises `application/grpc`, `application/grpc-web`,
`application/connect+proto` **and `application/connect+json`** on the same
port, and Connect's unary protocol is an ordinary HTTP/1.1 POST:

```
POST /exa.language_server_pb.LanguageServerService/GetAuthStatus
Content-Type: application/json
Connect-Protocol-Version: 1

{}
```

JSON in, JSON out, field names in protojson lowerCamelCase. **No protobuf
encoding at runtime, no `grpcurl`, no descriptor set, no HTTP/2.** The
collector can be a plain bash script with `curl` and `jq`, exactly like
Omarchy's other collectors — the carved descriptors stay a research artifact
rather than a runtime dependency.

(There's no gRPC reflection in the binary, so if you ever do want `grpcurl`,
it has to be fed a descriptor set from `tools/carve.py`. For JSON over
Connect it's unnecessary.)

`tools/probe-language-server` implements all of this. It rediscovers the port
from the log on each run, since the server takes a fresh random one per launch
and only listens while the IDE is open.

**Still unverified — needs a running, signed-in Antigravity:**
1. Does the local RPC need auth or metadata of its own, or is localhost enough?
   `GetUserAnalyticsSummaryRequest` has a `Metadata metadata = 1` field that
   may be required.
2. What buckets actually come back, and on what windows?
3. Does `remaining` arrive as `remainingFraction` (meter) or `remainingAmount`
   (balance)?

## 3a. Two more RPCs worth having

Extracting the service definition turned up two things I wasn't looking for.

**`GetAuthStatus` / `HasAuthToken` — the correct sign-in check** (see §6):

```proto
message HasAuthTokenResponse {
  bool has_token = 1; bool is_gcp_tos = 2;
  string project_id = 3; string location = 4; string wif_provider = 5;
}
message AuthResult {                    // GetAuthStatusResponse.auth_result
  bool   has_valid_auth = 1;
  string ui_message     = 2;            // → authHelpText / usageStatusText
  oneof failure_details { IneligibleInfo ineligible = 3; VerificationRequired …;
                          LicenseRequiredInfo license_required = 13; … }
  repeated string granted_scopes = 8;
}
```

`has_valid_auth` is the authoritative answer, and `ui_message` is a
ready-made string for the panel's error card.

**`GetUserAnalyticsSummary` — activity stats without touching the blobs:**

```proto
message GetUserAnalyticsSummaryRequest {
  Metadata metadata = 1; string time_zone = 2;
  Timestamp start_timestamp = 3; Timestamp end_timestamp = 4;
}
message GetUserAnalyticsSummaryResponse {
  CompletionStatistics          completion_statistics  = 1;
  repeated CompletionByDateEntry completions_by_day    = 2;   // → recentDays
  repeated CompletionByLanguageEntry completions_by_language = 3;
  repeated ChatStatsByModelEntry chats_by_model        = 4;   // → per-model
}
message CompletionStatistics {
  uint32 num_acceptances = 1; num_rejections = 2; num_lines_accepted = 3;
  uint32 num_bytes_accepted = 4; num_users = 5;
  uint32 active_developer_days = 6;    // → activeDays
  uint32 active_developer_hours = 7;
}
message ChatStats { uint64 chats_sent = 1; chats_received = 2; chats_accepted = 3; … }
```

It takes an explicit date range and timezone, so "today" and "last 7 days" are
a direct query rather than something we derive from row timestamps.

**Read the nuance carefully: there are no token counts in here.**
`CompletionStatistics` is autocomplete acceptance metrics and `ChatStats` is
chat/action counts. So this fills `todayPrompts`, `totalPrompts`, `activeDays`,
`recentDays`, and gives us real model ids — but `todayTotalTokens` and the
four token buckets in `modelUsage` stay zero. It reduces the value of §4; it
does not replace it.

## 4. Tokens: the protos are shipped after all

`findings.md` put protobuf decoding out of scope because "no `.proto` source is
shipped anywhere in the install." That's true of the filesystem but not of the
binary. `language_server` is Go, and Go's protobuf runtime embeds a
`FileDescriptorProto` for every compiled message:

```
$ strings -n 8 /opt/Antigravity/resources/bin/language_server | grep -E '\.proto$' | sort -u | wc -l
628
```

Visible in there, with `…_rawDescGZIP` symbols next to them:

- `third_party/jetski/product_api_pb/v1/conversation.proto` — the conversation
  storage format, i.e. exactly the blobs in `conversations/<uuid>.db`
- `third_party/gemini_coder/proto/trajectory.proto`,
  `cider/proto/trajectory_steps.proto` — the `steps` table
- `devtools/jetski/telemetry/extensions/cortex_trajectory{,_step}.proto`,
  `cortex_metrics.proto`
- `google/cloud/aiplatform/*/usage_metadata.proto` — Vertex's token counts
  (`promptTokenCount` / `candidatesTokenCount`), which is where per-step
  tokens most likely live

("jetski" is the internal codename; `codeium_common_pb` in the same tree dates
it to the Codeium → Windsurf lineage Google acquired.)

**Extraction is done and checked in.** `tools/carve.py` + `tools/fmt.py`
recover any of those descriptors as readable `.proto`; that's where the quota
and auth schemas in §3 and §3a came from. No Go toolchain needed, just
`protoc` and Python 3. `tools/README.md` documents the one sharp edge (the
carve guesses where a descriptor ends and can overrun into its neighbor).

So the remaining path for tokens is: carve
`jetski/product_api_pb/v1/conversation.proto` and the trajectory protos →
build a descriptor set → `protoc --decode` the `gen_metadata.data` and
`steps.metadata` blobs from `conversations/<uuid>.db`.

**Still the last thing to build.** The original reasoning for deferring holds —
undocumented internal format, drifts across releases, the only part of the
plugin needing re-derivation on upgrade — and §3a weakened the case further:
`GetUserAnalyticsSummary` already supplies prompt counts, active days, and
per-model breakdown from a supported RPC. Tokens are the *only* thing left
that requires blob decoding. Do it if and only if the token rows in the panel
are worth that maintenance burden.

## 5. Gap analysis: what "fully fledged" actually requires

Measured against `omarchy.agents` and `nixfred.infomarchy` as the two
reference points for a complete plugin.

### Manifest (`manifest.json`)
- [ ] `activation: "on-demand"` — agents sets it; we don't
- [ ] `barWidget.aliases` — e.g. `["antigravity", "ag"]`, for bar commands
- [ ] `barWidget.defaults` + `schema` — currently both empty. Needs at minimum
      `refreshIntervalSec`. Only `string` and `integer` appear in first-party
      manifests; agents also uses `enum` and `path`, so those are live. There's
      no published type list — `services/PluginRegistry.qml` holds the schema.
- [ ] `keepLoaded` if a `service` kind is added for the collector timer (§1, Route C)
- [ ] Bump `version` off `0.1.0` and drop "Stub: no real data wired up yet"
      from both description fields

### Data
- [ ] Collector emits the §2 record contract (currently a bespoke JSON shape)
- [ ] Correct sign-in detection (§6)
- [ ] Timer that runs the collector — QML `Timer` + `Process`, mirroring
      `agents/Main.qml:120-126`
- [ ] `retryAdvised` on transient failure
- [ ] Limits, once §3 is verified
- [ ] Tokens, once §4 is decoded

### Panel (Route B/C only)
The `Ui/Panel.qml` base gives us `open`/`close`/`toggle`/`switchPanel`,
`setting(name, fallback)`, and an `IpcHandler` wired to `ipcTarget` for free
(`Ui/Panel.qml:12-56`). Building on that:
- [ ] Hero: mark, "Antigravity", tier or status line
- [ ] Limit meters with reset countdown (if §3 lands)
- [ ] Activity: conversations by day, recent titles + workspaces
- [ ] Error/auth card when signed out
- [ ] Self-hide when there's no data, the way agents does — a machine with
      Antigravity installed but unused should draw nothing
- [ ] Keyboard: `j`/`k` scroll, `r`/Enter refresh, Tab to neighbor, Esc close
- [ ] Bar icon: left opens panel, right launches Antigravity, middle → ?

### Assets
- [ ] An SVG mark, plus a `-light` twin for light themes (the convention in
      `agents/assets/`). The AUR package ships an `antigravity` icon —
      check its license before vendoring.
- [ ] `preview.png` — infomarchy ships one; useful for a README and any future
      catalog listing.

### Tests
`tests/smoke` is a good start. To match infomarchy's bar (it ships ~20 `.test.ts`
files including `qml-syntax.test.ts` and `qml-resolve.test.ts`):
- [ ] Record-contract validation — assert collector output against the §2 shape
- [ ] Fixtures for: no DB, empty DB, signed-out, malformed rows, DB locked
      while Antigravity is running (WAL — worth confirming we can read it
      concurrently)
- [ ] QML syntax/resolve check in CI
- [ ] `omarchy-plugin-validate .` as a test step — it enforces schemaVersion
      `1` exactly, required fields, id not in the `omarchy.*` namespace, entry
      points relative/existing/no `..`, a `defaultSection` of left|center|right,
      and **no symlinks anywhere in the folder** (`.git` excepted)

### Docs & distribution
- [ ] README rewritten from "scaffold" to usage + settings table + screenshot
- [ ] `CHANGELOG.md` (infomarchy has one)
- [ ] `THIRD_PARTY_NOTICES.md` if the icon or anything else is vendored
- [ ] Push to the GitHub remote already declared in `manifest.json.homepage`,
      so `omarchy plugin add https://github.com/lasswellt/omarchy-antigravity.git`
      works for anyone else
- [ ] There is no plugin registry to submit to — `omarchy-plugin-catalog` only
      walks local dirs. Distribution is just a public git URL.

## 6. Bug in the current collector

`bin/antigravity-usage:33-35,81` derives `signedIn` from
`~/.gemini/google_accounts.json`. That file is the **Gemini CLI's** active
account. On this machine it reported a signed-in Google account while the
Antigravity language server logged "You are not logged into Antigravity" 91
times in the same session — so the collector claims signed-in for a signed-out
IDE, and would keep doing so for a user who has only ever used the Gemini CLI.

**Answered (§3a).** `LanguageServerService` has two purpose-built RPCs:
`HasAuthToken` → `has_token`, and `GetAuthStatus` → `AuthResult.has_valid_auth`
plus a `ui_message` string that drops straight into `authHelpText`. Use
`GetAuthStatus` — `has_valid_auth` distinguishes "has a token" from "that token
works", and the failure oneof names the reason (ineligible, license required,
ToS, verification).

Fallback when the server isn't running (it only runs while the IDE is open):
grep a recent slice of `language_server.log` for `error getting token source`.
Either way it's derived from Antigravity's own state, and neither path reads
`oauth_creds.json`.

## 7. Suggested order

**Steps 1–4 are done and running.** Antigravity appears in the built-in Agents
panel next to Claude and Codex; the service has refreshed on its 900s timer
continuously since 2026-09-18. What follows 4 is polish.

- [x] 1. **Settle §0's open questions.** Decided: one merged `antigravity`
      record, because the quota is account-wide and two tabs would draw the
      same limits twice. Token totals stay zero — `agy` reports usage per run
      with no cumulative store, so `hasPromptStats: false` and step counts
      carry the activity signal.
- [x] 2. **Collector rewritten to the record contract** (`bin/antigravity-usage`).
- [x] 3. **Tested** — 42 checks, fixtures plus a stubbed `agy`, including the
      envelope guard. Mutation-tested to confirm the checks bite.
- [x] 4. **Published on a timer** — `AntigravityService.qml` runs
      `bin/antigravity-usage-update`; the plugin is a `service`, not a bar
      widget, since the Agents panel is the display.
- [ ] 5. Standalone `Panel.qml` over the same record.
- [ ] 6. Manifest polish, an SVG mark, docs (§5 checklist).
- [ ] 7. *Optional:* the IDE path via §3's local RPC.

<details>
<summary>Original step detail, kept for the rebuild</summary>

2. **Rewrite `bin/antigravity-usage` to the §2 record contract**, sourcing:
   `agy -p "/usage"` → `limits[]` (percent = `1 - remaining_fraction`,
   label from group + bucket name, `resetsAt` from `reset_time`),
   `agy -p "/credits"` → `balance`, and
   `~/.gemini/antigravity-cli/conversation_summaries.db` → sessions and
   `activeDates`. Degrade cleanly when `agy` is absent or signed out.
3. **Test it against fixtures**, including captured `agy` JSON envelopes — the
   whole limits path rests on slash-command expansion in print mode, so a test
   should fail loudly if that envelope shape changes.
4. **Have the plugin write the record to the usage dir on a timer.**
   Antigravity appears in the built-in Agents panel at this point, next to
   Claude and Codex, and everything after is polish.
5. Build the standalone `Panel.qml` over the same record.
6. Fill in the manifest, assets, tests, and docs from §5.
7. *Optional, low priority:* extend to the IDE via §3's local RPC for machines
   that run the IDE but not the CLI. Decoding the conversation protos (§4) is
   now almost certainly never worth it.

</details>

### Traps found while wiring it up

Both cost real time and are easy to hit again:

- **A brand-new QML file needs `omarchy restart shell`, not just
  `omarchy plugin update`.** Qt caches the plugin directory listing, so a file
  that did not exist when the shell started is reported as
  `File name case mismatch` — nothing to do with case. Editing an existing
  file hot-reloads fine.
- **`omarchy restart shell` refuses while the session is locked**, and says so
  only on stderr. A locked session silently turns every restart into a no-op.
- **The first collection after a cold boot can exceed 15s**, because each `agy`
  call spawns a 218 MB binary. Steady state is ~4s. An absent record is not
  proof the service is dead.
- **Don't rewrite git history on a branch an installed plugin tracks.** The
  installed copy is a real clone; a squashed commit it had already pulled
  orphans its HEAD and breaks `plugin update` with "cannot fast-forward".
  Recover with `git -C <plugin-dir> fetch && git reset --hard origin/master`.

## Appendix: how to redo the binary research

```bash
BIN=/opt/Antigravity/resources/bin/language_server

# every embedded proto descriptor filename
strings -n 8 $BIN | grep -E '\.proto$' | sed 's/^[^a-z]*//' | sort -u

# the Code Assist RPC surface
strings -n 10 $BIN | grep -oE '/google\.internal\.cloud\.code\.v1internal\.[A-Za-z]+/[A-Za-z]+' | sort -u
strings -n 8 $BIN | grep -oE 'v1internal:[a-zA-Z]+' | sort -u

# which hosts it talks to
strings -n 10 $BIN | grep -oE 'https://[a-z0-9.-]*googleapis\.com' | sort -u

# local server ports (random per launch, newest last)
grep -E 'listening on random port' ~/.config/Antigravity/logs/language_server.log

# is the IDE actually signed in?
grep -c 'not logged into Antigravity' ~/.config/Antigravity/logs/language_server.log

# read any embedded schema as .proto (see tools/README.md)
./tools/carve.py $BIN google/internal/cloud/code/v1internal/quota_summary.proto /tmp/q.bin
protoc --decode=google.protobuf.FileDescriptorProto google/protobuf/descriptor.proto \
  < /tmp/q.bin | ./tools/fmt.py

# the whole local RPC surface
./tools/carve.py $BIN third_party/jetski/language_server_pb/language_server.proto /tmp/ls.bin
protoc --decode=google.protobuf.FileDescriptorProto google/protobuf/descriptor.proto \
  < /tmp/ls.bin | ./tools/fmt.py | grep -E '^service |  rpc '
```
