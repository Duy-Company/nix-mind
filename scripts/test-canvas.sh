#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/test-cache
sources=(NixMind/*.swift)
sources=(${sources:#NixMind/main.swift})
swiftc -parse-as-library -module-cache-path build/test-cache "${sources[@]}" Tests/CanvasSceneTests.swift -o build/canvas-tests
build/canvas-tests "$@"
