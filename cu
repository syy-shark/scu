#!/bin/bash
# Smooth Computer Use launcher: builds the native binary on first use (or when
# sources changed), then runs it. Agents call this instead of the binary.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN="$DIR/smooth-computer-use"
if [ ! -x "$BIN" ] || [ -n "$(find "$DIR/Sources" -name '*.swift' -newer "$BIN" 2>/dev/null | head -1)" ]; then
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "❌ swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
  (cd "$DIR" && ./build.sh >&2) || { echo "❌ build failed" >&2; exit 1; }
fi
exec "$BIN" "$@"
