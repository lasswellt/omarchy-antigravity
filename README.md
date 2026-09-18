# Antigravity (Omarchy plugin) — stub

An early scaffold for an [Omarchy](https://omarchy.org) bar widget for
Google Antigravity, modeled on the structure of
[omarchy-tesla](https://github.com/nixfred/omarchy-tesla) (manifest,
`Panel.qml`, `bin/` collector scripts, tests).

Right now this only proves the plugin loads and shows a placeholder "AG"
icon in the bar. No real data yet.

## Open questions before building the real thing

- Does Antigravity write any local session/usage state to disk, and where?
- Is there a usage/rate-limit API comparable to Anthropic's OAuth usage
  endpoint that Claude's collector reads, or is Antigravity local-only?
- If neither exists, the widget may only ever be able to show
  installed/running status, not real usage meters.

## Dev loop

This directory is the source of truth. The installed copy at
`~/.config/omarchy/plugins/lasswellt.antigravity` is a separate git clone
pulling from this repo (or its remote, once pushed).

```bash
# after editing here
cd ~/Projects/omarchy-antigravity
git add -A && git commit -m "..."
omarchy plugin update lasswellt.antigravity --yes
```

## Install

```bash
omarchy plugin add ~/Projects/omarchy-antigravity --enable
```
