# CodexBar — Omarchy widget

One bar icon and one panel that show the usage, limits, credits, and resets
for **every AI provider CodexBar tracks** — Codex, Claude, OpenCode Go, Gemini,
Copilot, Grok, OpenRouter, and more — in the same Omarchy surface as the
native Model Usage widget.

The widget is a thin **wrapper around [CodexBar](https://github.com/steipete/CodexBar)**.
All provider logic — authentication, cookies, workspace lookup, quota parsing,
and refresh — is delegated to the `codexbar` CLI. The plugin runs
`codexbar usage` and `codexbar cost` directly via `Process` (no `codexbar serve`
daemon), normalizes the payloads, and renders a panel in the native
Model Usage style. It never reads provider databases or guesses usage itself.

## Requirements

- `codexbar-cli` on `PATH` (Arch: `yay -S codexbar-cli`)
- Providers enabled in CodexBar's config (`codexbar config providers`,
  Settings, or `codexbar config enable --provider <id>`). On Linux, browser
  cookie sources are macOS-only; use API keys, local CLIs, or manual cookies
  where a provider supports them. See the
  [CodexBar OpenCode doc](https://github.com/steipete/CodexBar/blob/main/docs/opencode.md)
  for the OpenCode Go `cookieHeader` setup if you want web-sourced usage.

## Install

Setup › Plugins › **Add**, paste this repo's URL, then **Enable** (it lands in
the `right` section):

```bash
omarchy plugin add https://github.com/felixzsh/omarchy-codexbar.git --enable
```

## What it shows

The panel mirrors the native Model Usage widget's layout:

- **Hero** per provider — brand mark, plan, source, and a **dropdown selector**
  on the right to switch between every provider that reports usable data.
- **Limits** — the provider's windows (5-Hour, Weekly, Monthly) as meters with
  the percentage used and a "resets in X" countdown.
- **Credits** — balance when the provider exposes one.
- **Tokens by day** — only when CodexBar reports a daily token history. That
  history comes from `codexbar cost` (local Codex/Claude logs); providers
  without it simply hide the section. There is no per-model token split in
  CodexBar, so that chart is not shown.

Percentages, reset times, and token counts are CodexBar's, never recomputed.
Providers with no usable data are excluded from the panel and the selector.

## Interactions

- Bar icon: left = panel, right = refresh.
- Panel: `j`/`k` scroll, `r` or Enter refresh, Tab moves to the neighboring bar
  panel, Esc closes.
- IPC: `omarchy shell local.codexbar <open|close|toggle|refresh|status>`.
  `status` returns a JSON snapshot of the server, the widget state, and every
  valid provider — the first thing to check when the widget does not show up.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`:

```bash
omarchy bar set local.codexbar codexbarBin /usr/bin/codexbar --json
```

| Key | Default | What it does |
|---|---|---|
| `codexbarBin` | `codexbar` | Command name or path to the codexbar CLI |
| `refreshIntervalSec` | `120` | Background poll interval for usage (opens the panel to force a fetch) |

## Troubleshooting

```bash
omarchy shell local.codexbar status   # binary, version, widget + providers at a glance
```

- `usageStatusText` says `failed to run (exit N)` — the `codexbar` binary was not
  found or crashed. Check `codexbar --version` and the `codexbarBin` setting.
- `usageStatusText` says `no parseable usage` — run `codexbar usage --format json`
  manually to see the error.
- No providers — no enabled CodexBar provider returned usable data. Enable one
  in CodexBar and check `codexbar usage --format json`.
- The widget is always visible once placed; opening the panel explains any
  failure instead of hiding the icon.

The shell caches compiled plugin QML, so after updating the plugin code the
widget can keep running the old version until the shell restarts:

```bash
omarchy restart shell
```

The widget coexists with the native Model Usage widget; they have independent
plugin ids and IPC targets.
