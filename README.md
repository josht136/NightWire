# PingSlut

macOS ping tracker with live charts and SQLite history.

## Setup

```bash
python3 -m pip install -r requirements.txt
python3 pingslut.py
```

## Build macOS app

```bash
chmod +x build.sh
./build.sh
```

The app bundle is written to `dist/PingSlut.app`.

## Default targets

- `8.8.8.8` (Google DNS)
- `1.1.1.1` (Cloudflare DNS)

Edit `addresses_to_track` in `pingslut.py` to change targets.
