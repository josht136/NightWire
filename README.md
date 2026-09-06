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

## Updates

Nightwire checks GitHub Releases on launch (`josht136/NightWire`, asset `Nightwire.app.zip`). It never downloads or installs until you agree.

Releases are public on `josht136/NightWire`, so no GitHub token is required. An optional token in Nightwire → Options is only needed if you point the updater at a private repository.

### Publish a version

1. Set `MARKETING_VERSION` in `macos/Nightwire/project.yml` to the new version (for example `1.0.1`) and bump `CURRENT_PROJECT_VERSION`.
2. Commit, then tag and push `v1.0.1` (tag must match `MARKETING_VERSION`).
3. `.github/workflows/release-nightwire.yml` builds the app, zips `Nightwire.app`, and creates the GitHub Release the updater reads.
