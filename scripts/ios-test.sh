#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../ios"
source ../scripts/_simulator.sh

DEVICE="$(resolve_simulator)"
echo "Simulateur : $DEVICE"

xcodegen generate
rm -rf build/TestResults.xcresult
xcodebuild test -project Gage.xcodeproj -scheme Gage \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build \
  -resultBundlePath build/TestResults.xcresult
