# ClaudePace

<img src="docs/screenshot.png" alt="ClaudePace popover" width="300" align="right">

macOS menu bar app that tracks your Claude Code spend against a monthly budget. The menu bar shows, per your choice in settings, how many days ahead (`+2d`) or behind (`−1d`) you are, or what's left of today's target as a percentage (`42%`) or in dollars (`$62`).

The popup is laid out like a native macOS menu:

- Pace-aware "left today": what's left of the budget spread over the remaining days, so past over/underspend carries forward.
- Month progress bar with the reserve and where spend should be by today.
- Pace (days ahead or behind), spent this month, today and remaining.
- Daily spend sparkline against the daily allowance, with last month's daily spend as a grey line and a % change vs the same point last month. Hover a day to see its spend next to last month's.
- Breakdown by model, project, or session (the costliest sessions this month, by session name).  Switch between monthly and daily (today only). Click a row to expand today's spend, messages, tokens or the session's project and duration.
- A toolbar for settings (budget, reserve, menu bar mode), refresh (⌘R), export and quit (⌘Q).
- Export this month's usage as JSON or CSV (by day, model, project or session): the share button copies it to the clipboard, or run `make export FORMAT=json` / `make export FORMAT=csv BY=session`.

## How it works

- Reads Claude Code's session logs (`~/.claude/projects/**/*.jsonl`, `~/.config/claude/projects`, or `$CLAUDE_CONFIG_DIR`) and prices each response's tokens, the same way ccusage does. No API key needed.
- Prices come from LiteLLM's public price list (refreshed daily, cached in `~/Library/Caches/dev.meain.claudepace`), with a built-in table as fallback.
- Claude Code logs a response several times while streaming; the costliest copy per `message.id` + `requestId` is counted.
- Usable budget = budget × (1 − reserve%). Daily allowance = usable ÷ days in month.
- Expected spend = daily allowance × completed days (day 3 → 2 days).
- Days ahead = (expected − spent) ÷ daily allowance; the menu bar truncates it toward zero.
- Today's target = (usable − spent before today) ÷ days left including today. "Left today" (and the `%`/`$` menu bar modes) = target − spent today.
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
