#!/bin/bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
echo "🔨 Building smooth-computer-use 2.0 ..."
swiftc -O -swift-version 5 \
    -framework Cocoa -framework ApplicationServices -framework CoreGraphics \
    -framework QuartzCore -framework ScreenCaptureKit \
    Sources/*.swift -o smooth-computer-use
chmod +x smooth-computer-use
# restart a running daemon so it picks up the new binary
if [ -S "/tmp/smooth-cu-$(id -u).sock" ]; then ./smooth-computer-use stop >/dev/null 2>&1 || true; fi
echo "✅ Built $DIR/smooth-computer-use"
