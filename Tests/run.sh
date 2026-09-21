#!/bin/sh
# Runs the model-layer tests: no Xcode project, no simulator, no app data.
#
#   Tests/run.sh                 # self-contained fixtures
#   Tests/run.sh path/to/cards.json   # also check that a real file still decodes
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/Tests/.build"
mkdir -p "$out"
swiftc -O "$root/DayDeck/Models.swift" "$root/DayDeck/Sync.swift" "$root/Tests/main.swift" -o "$out/tests"
"$out/tests" "$@"
