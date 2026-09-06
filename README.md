# Nightwire

Native macOS ping tracker (Swift/SwiftUI). Live neon latency chart, add/remove hosts, hide a series without stopping pings.

The Python matplotlib app (`pingslut.py`) is legacy. Use the Mac app.

## Launch

Double-click `Nightwire.app` on the Desktop.

## Rebuild

```bash
./build.sh
```

This writes `/Users/jtiller/Desktop/Nightwire.app` and keeps the Xcode project in `macos/Nightwire/`.

## First launch

Allow network access if macOS prompts. ICMP is outgoing; no root required.

History: `~/Library/Application Support/Nightwire/history.sqlite`

## Defaults

- `8.8.8.8`
- `1.1.1.1`
