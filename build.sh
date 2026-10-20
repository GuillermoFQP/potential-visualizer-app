#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Potential Visualizer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos12.0" -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit -framework SceneKit -framework CoreText \
  "$ROOT/Sources/FITS.swift" "$ROOT/Sources/Surface.swift" "$ROOT/Sources/MathAxes.swift" "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/PotentialVisualizer"
cp "$ROOT/Resources/RdBu_r.json" "$APP/Contents/Resources/"
cp "$ROOT/Resources/MathAxes.json" "$ROOT/Resources/cmr10.ttf" "$ROOT/Resources/LICENSE_BAKOMA" "$APP/Contents/Resources/"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
