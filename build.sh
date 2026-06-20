#!/bin/bash
set -euo pipefail

echo "Installing dependencies..."
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

echo "Building PingSlut.app..."
python3 setup.py py2app

echo "Build complete: dist/PingSlut.app"
