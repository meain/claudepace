First release of ClaudePace, a macOS menu bar app that tracks your Claude Code spend against a monthly budget, so you know whether you're ahead of or behind pace.

- **Menu bar:** days ahead/behind (`+2d` / `−1d`), or what's left of today's target as a percentage or in dollars.
- **Pace-aware "left today":** the remaining budget is spread over the remaining days, so earlier over- or underspend carries forward.
- **Popup:** month progress, spent/today/remaining, and a daily sparkline against your allowance with last month overlaid.
- **Breakdowns:** by model, project or session, with click-to-expand details.
- **Export:** this month's usage as JSON or CSV.
- **No API key:** it reads Claude Code's local session logs and prices tokens the same way ccusage does, using LiteLLM's price list.

### Install

Download `ClaudePace.zip`, unzip it and move `ClaudePace.app` to `/Applications`. Requires macOS 14 or later.

The app is ad-hoc signed, not notarized, so the first launch needs right-click → Open. Or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/ClaudePace.app
```

Only covers Claude Code on the machine it runs on, at list prices.
