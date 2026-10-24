#!/bin/bash
# Starts only the supplied build on an isolated macOS CI runner.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-'build/release/Build/Products/Release/Nix Mind.app'}
BINARY="$APP/Contents/MacOS/Nix Mind"
[[ -x "$BINARY" ]]
# Never reuse or terminate an existing user's app instance.
python3 - <<'PY'
import os, socket
with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(1)
    try:
        connection.connect(f'/private/tmp/nixmind-{os.getuid()}/app.sock')
    except (ConnectionRefusedError, FileNotFoundError):
        pass
    else:
        raise SystemExit('An existing Nix Mind owns local MCP. Run this harness on an isolated runner instead.')
PY
mkdir -p build
"$BINARY" > build/mcp-gui.log 2>&1 &
APP_PID=$!
cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT
export NIX_MIND_TEST_PID="$APP_PID"
python3 - <<'PY'
import json, os, socket, time
pid = int(os.environ['NIX_MIND_TEST_PID'])
for _ in range(60):
    os.kill(pid, 0)
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(1)
            connection.connect(f'/private/tmp/nixmind-{os.getuid()}/app.sock')
            connection.sendall(b'{"action":"ping"}\n')
            reply = json.loads(connection.makefile().readline())
            if reply.get('result', {}).get('app') == 'Nix Mind':
                break
    except (OSError, ValueError):
        pass
    time.sleep(0.5)
else:
    raise SystemExit('The built app did not start its local MCP listener.')
PY
python3 scripts/test-mcp.py "$BINARY"
