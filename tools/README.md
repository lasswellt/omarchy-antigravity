# tools/

Research tooling, not part of the plugin. Nothing here runs at widget runtime;
it exists to re-derive the Antigravity schemas in `roadmap.md` when a new
Antigravity release changes them.

## `probe-language-server`

> **Mostly obsolete — see `roadmap.md` §0.** The `agy` CLI returns the same
> quota data with `agy -p "/usage" --output-format json`, no transport work
> and no running IDE required. This script is now only for the IDE path: a
> machine that runs Antigravity the editor but not the CLI.

Calls the live local server and dumps the responses the collector will be
built on. **Antigravity must be running and signed in** — the server only
listens while the IDE is open, and takes a fresh random port every launch
(the script rediscovers it from the log each run).

```bash
./tools/probe-language-server            # GetAuthStatus, HasAuthToken,
                                         # RetrieveUserQuotaSummary, GetUserAnalyticsSummary
./tools/probe-language-server --redact   # scrub project id / location when printing
./tools/probe-language-server --force-refresh --days 30
```

Needs only `curl` and `jq`. Antigravity's backend serves its RPCs with
[connectrpc.com/connect](https://connectrpc.com), and Connect's unary protocol
is an ordinary HTTP/1.1 `POST` with a JSON body:

```
POST /exa.language_server_pb.LanguageServerService/GetAuthStatus
Content-Type: application/json
Connect-Protocol-Version: 1

{}
```

so no protobuf encoding, `grpcurl`, or descriptor set is involved. (The same
port also speaks `application/grpc`, `grpc-web` and `connect+proto`; JSON is
just the easiest to read.) Field names in JSON are protojson lowerCamelCase —
`force_refresh` is `forceRefresh`, `time_zone` is `timeZone`.

**This is the finding that shapes the collector**: it can stay a plain shell
script like Omarchy's other collectors, with no protobuf dependency at
runtime.

Output lands in `probe-out/`, which is gitignored — raw responses can carry
the account's project id and account-specific error strings.

## Extracting protobuf schemas from `language_server`

Antigravity ships no `.proto` files, but its Go backend embeds a
`FileDescriptorProto` for every compiled message. `carve.py` locates one in the
binary and carves out its bytes; `fmt.py` turns `protoc`'s decode of those
bytes back into readable `.proto`-ish source.

```bash
BIN=/opt/Antigravity/resources/bin/language_server

# list every embedded descriptor (628 of them as of Antigravity 2.14.0)
strings -n 8 $BIN | grep -E '\.proto$' | sed 's/^[^a-z]*//' | sort -u

# carve one out and read it
./tools/carve.py $BIN google/internal/cloud/code/v1internal/quota_summary.proto /tmp/q.bin
protoc --decode=google.protobuf.FileDescriptorProto google/protobuf/descriptor.proto \
  < /tmp/q.bin | ./tools/fmt.py
```

Requires `protoc` (any recent version — `libprotoc 36.1` here) and Python 3.
No Go toolchain and no third-party Python packages needed.

### Known limitation

`carve.py` finds the descriptor's start exactly (the `0x0a <len> <path>` tag
that opens field 1, `name`) but has to *guess* its end, by walking the wire
format until it stops looking like a plausible top-level field. When a
descriptor is followed in the data section by bytes that happen to parse, the
carve overruns and you get extra messages that belong to a neighboring
descriptor.

This is visible and harmless — `credits.proto` carves as `Credits` followed by
an obvious tail of `UsageRestriction`, the `*Value` wrapper types, and
`ProjectContext`, none of which are part of it. **Trust messages up to the
first one that looks out of place, and cross-check anything load-bearing**
against the `strings` output for that message name. Large files carve cleanly
(`language_server.proto` is 482 KB and correct throughout).

A rigorous fix would read Go's `rawDesc` slice headers out of the data section
to get exact lengths. Not worth it unless the guessing starts costing real
time.
