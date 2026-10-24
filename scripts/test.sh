#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/test-cache
swiftc -module-cache-path build/test-cache NixMind/MCPConfiguration.swift NixMind/NodeAppearance.swift NixMind/MindMap.swift NixMind/MapFormats.swift NixMind/AIMap.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
