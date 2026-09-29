# ClaudePace

<img src="docs/screenshot.png" alt="ClaudePace popover" width="300" align="right">

macOS menu bar app that shows how many days ahead (`+2d`) or behind (`−1d`) you are on your monthly Claude budget.

- Pace-aware "left today": what's left of the budget spread over the remaining days, so past over/underspend carries forward.
- Month progress bar with the reserve and where spend should be by today.
- Daily spend sparkline against the daily allowance.
- Breakdown by model (cost, today's spend, messages, tokens), project, or session (the costliest sessions this month, by session name with the project underneath).
- Last month's daily spend as a grey line on the sparkline, with a % change vs the same point last month.
- Export this month's usage as JSON or CSV (by day, model, project or session): the share button in the popup copies it to the clipboard, or run `make export FORMAT=json` / `make export FORMAT=csv BY=session`.

## How it works

- Reads Claude Code's session logs (`~/.claude/projects/**/*.jsonl`, `~/.config/claude/projects`, or `$CLAUDE_CONFIG_DIR`) and prices each response's tokens, the same way ccusage does. No API key needed.
- Prices come from LiteLLM's public price list (refreshed daily, cached in `~/Library/Caches/dev.meain.claudepace`), with a built-in table as fallback.
- Claude Code logs a response several times while streaming; the costliest copy per `message.id` + `requestId` is counted.
- Usable budget = budget × (1 − reserve%). Daily allowance = usable ÷ days in month.
- Expected spend = daily allowance × completed days (day 3 → 2 days).
- Label = (expected − spent) ÷ daily allowance, truncated toward zero.
- Months follow your local time zone. Refreshes every 5 minutes; unchanged log files aren't re-parsed.

Only covers Claude Code on this machine, at list prices.

## Build

```sh
make link    # build ClaudePace.app and symlink it into /Applications
make install # or copy it there instead
make check   # budget math checks
make scan    # this month's spend by model
make export FORMAT=json # or FORMAT=csv BY=day|model|project|session
make screenshot # render the popup to docs/screenshot.png (TAB=models|projects|sessions)
make help    # all targets
```

Builds with Command Line Tools only (no Xcode), which is why it uses `--build-system native` and avoids SwiftUI macros like `@State`.
