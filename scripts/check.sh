#!/usr/bin/env bash
# Compile-checks everything without signing: Engine tests, then the app + widgets
# for macOS and for iOS. Run after pulling new code.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Engine tests"
swift test --package-path Engine

[ -d Dissolve.xcodeproj ] || xcodegen generate

for dest in "generic/platform=macOS" "generic/platform=iOS"; do
  echo "▸ Building for $dest"
  xcodebuild -project Dissolve.xcodeproj -scheme Dissolve -destination "$dest" \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
done
echo "✓ All checks passed"
