- **Menu bar:** new option to show the percent of today's target used.
- **Breakdown:** daily/monthly toggle on the model, project and session views.
- **Fix:** today's spend is now computed from per-day totals, so it rolls over correctly at midnight.

### Install

Download `ClaudePace.zip`, unzip it and move `ClaudePace.app` to `/Applications`. Requires macOS 14 or later.

The app is ad-hoc signed, not notarized, so the first launch needs right-click → Open. Or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/ClaudePace.app
```
