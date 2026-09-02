#!/usr/bin/env bash
# Resout un simulateur iPhone disponible. Les noms de modeles changent a chaque
# version de Xcode : on ne code jamais "iPhone 16" en dur.
resolve_simulator() {
  xcrun simctl list devices available \
    | grep -E '^\s+iPhone' \
    | tail -1 \
    | sed -E 's/^[[:space:]]*(.*) \([0-9A-F-]{36}\).*/\1/'
}
