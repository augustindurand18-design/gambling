#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../ios"
source ../scripts/_simulator.sh

DEVICE="$(resolve_simulator)"
echo "Simulateur : $DEVICE"

xcodegen generate
xcodebuild -project Gage.xcodeproj -scheme Gage \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build \
  build | xcbeautify 2>/dev/null || \
xcodebuild -project Gage.xcodeproj -scheme Gage \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build \
  build
