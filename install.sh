#!/bin/bash

for req in git swift; do
    if ! command -v "$req" &>/dev/null; then
        echo "Error: $req is not installed or not in PATH." >&2
        exit 1
    fi
done

REPO_URL="https://github.com/MEGAToster/sketchybar-toggle"
TARGET_DIR="/tmp/sketchybar-toggle"

rm -rf "$TARGET_DIR"

git clone "$REPO_URL" "$TARGET_DIR" || exit 1

cd "$TARGET_DIR" || exit 1

echo "Building release..."
swift build -c release || exit 1
echo "Copying bin to /usr/local/bin/sketchybar-toggle (requires sudo)"

sudo cp .build/release/sketchybar-toggle /usr/local/bin/ || exit 1

echo 'Installation complete. Add the following to the bottom of your sketchybarrc:'
echo 'pkill -x sketchybar-toggle && sketchybar-toggle &'
