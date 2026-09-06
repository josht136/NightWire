# Nightwire (native macOS)

Swift/SwiftUI ping tracker. Double-click `Nightwire.app` on the Desktop to start.

## Rebuild

```bash
cd /Users/jtiller/Projects/pingslut
./build.sh
```

Or from this folder:

```bash
xcodegen generate
xcodebuild -scheme Nightwire -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/Nightwire.app ~/Desktop/Nightwire.app
```

Open `Nightwire.xcodeproj` in Xcode if you prefer a GUI build.

## First launch

macOS may ask to allow network access. Grant it so ICMP pings can run.

The app is **not** App Sandboxed so SOCK_DGRAM ICMP and `/sbin/ping` work without extra privileges. Ad-hoc signed (`CODE_SIGN_IDENTITY=-`) for local use.

## Data

Targets and history live in:

`~/Library/Application Support/Nightwire/history.sqlite`

Defaults if the store is empty: `8.8.8.8` and `1.1.1.1`.

## Updates

A small custom updater (not Sparkle) talks to GitHub Releases. Sparkle needs Developer ID + signed appcasts; this app is ad-hoc signed (`CODE_SIGN_IDENTITY=-`).

- Check: `GET https://api.github.com/repos/josht136/NightWire/releases/latest` compared to `CFBundleShortVersionString` / `CFBundleVersion`.
- Asset name: `Nightwire.app.zip`.
- Launch does a version check only. Download and install each require a click. **Skip this version** is remembered.
- Releases live on the public `josht136/NightWire` repo. An optional GitHub token in Options is only needed if you point the updater at a private repository.

Publish by bumping `MARKETING_VERSION` in `project.yml` and pushing a matching `vX.Y.Z` tag. CI zips the app and creates the Release.
