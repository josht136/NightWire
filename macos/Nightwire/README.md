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
