#!/usr/bin/env bash
# CI only: picks an Xcode on the GitHub macOS runner and exports DEPLOY_OVERRIDE.
# Prefers Xcode 27 (the real target). Otherwise uses the Xcode 26.x that matches the newest
# installed iOS simulator runtime, and lowers this CI build's deployment target to 26.0.
set -uo pipefail

newest() { sort -V | tail -1; }

ls -d /Applications/Xcode*.app
XC=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | newest)

if [ -n "$XC" ]; then
  echo "DEPLOY_OVERRIDE=" >> "$GITHUB_ENV"
else
  IOS=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r["version"] for r in json.load(sys.stdin)["runtimes"]
      if r.get("platform") == "iOS" and r.get("isAvailable") and r["version"].startswith("26.")]
if rs:
    v = sorted(rs, key=lambda v: [int(x) for x in v.split(".")])[-1]
    print(".".join(v.split(".")[:2]))')
  echo "Newest iOS 26 simulator runtime: ${IOS:-none}"
  [ -n "$IOS" ] && XC=$(ls -d /Applications/Xcode_"$IOS"*.app 2>/dev/null | newest)
  [ -n "$XC" ] || XC=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | newest)
  [ -n "$XC" ] || { echo "::error::No usable Xcode found"; exit 1; }
  echo "::warning::No Xcode 27 on the runner; CI builds with $(basename "$XC") and a 26.0 deployment target."
  echo "DEPLOY_OVERRIDE=IPHONEOS_DEPLOYMENT_TARGET=26.0 MACOSX_DEPLOYMENT_TARGET=26.0" >> "$GITHUB_ENV"
fi

sudo xcode-select -s "$XC"
xcodebuild -version
