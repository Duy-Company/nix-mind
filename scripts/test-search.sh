#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/test-cache
sources=(NixMind/*.swift)
sources=(${sources:#NixMind/main.swift})
swiftc -parse-as-library -module-cache-path build/test-cache "${sources[@]}" Tests/SearchTests.swift -o build/search-tests
build/search-tests "$@"
