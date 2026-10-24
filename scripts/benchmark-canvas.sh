#!/bin/zsh
# Compile a standalone test executable, never an app or release package.
set -eu
cd "$(dirname "$0")/.."
fixture=${1:?Pass the path of a .nixmap fixture}
source_dir=${2:-NixMind}
label=${3:-current}
mkdir -p build/test-cache
sources=($source_dir/*.swift)
sources=(${sources:#$source_dir/main.swift})
swiftc -O -parse-as-library -module-cache-path build/test-cache "${sources[@]}" Tests/CanvasPerformanceTests.swift -o "build/canvas-benchmark-$label"
"build/canvas-benchmark-$label" "$fixture"
