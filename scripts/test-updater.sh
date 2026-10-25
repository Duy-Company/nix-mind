#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-'build/release/Build/Products/Release/Nix Mind.app'}
SPARKLE=${2:-build/release/SourcePackages/artifacts/sparkle/Sparkle}
python3 Tests/UpdaterPackagingTests.py --app "$APP" --sparkle "$SPARKLE"
