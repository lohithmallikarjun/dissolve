#!/usr/bin/env bash
# One-time (and after every `git pull`) setup on your Mac:
#   installs XcodeGen if needed, remembers your signing team, generates Dissolve.xcodeproj.
# Usage: scripts/setup-mac.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    echo "Installing XcodeGen with Homebrew…"
    brew install xcodegen
  else
    echo "XcodeGen is missing and Homebrew isn't installed."
    echo "Install Homebrew from https://brew.sh, then run this script again."
    exit 1
  fi
fi

signing=Config/Signing.local.xcconfig
if [ ! -f "$signing" ]; then
  # The Team ID is the OU field of your "Apple Development" certificate.
  team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
  if [ -n "$team" ]; then
    echo "DEVELOPMENT_TEAM = $team" > "$signing"
    echo "Signing team: $team (saved to $signing)"
  else
    echo "No Apple Development certificate found yet."
    echo "Pick your Personal Team in Xcode (see README), build once, then run this script again."
  fi
fi

xcodegen generate
echo "Generated Dissolve.xcodeproj"

if [ "${1:-}" = "--open" ]; then
  open Dissolve.xcodeproj
fi
