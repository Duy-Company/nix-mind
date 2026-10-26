#!/usr/bin/env python3
"""Test signing setup with fake CLI/Keychain tools, never real credentials."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
public_key = plistlib.loads((ROOT / 'NixMind/Info.plist').read_bytes())['SUPublicEDKey']
with tempfile.TemporaryDirectory(prefix='nixmind-config-tests-') as directory:
    temp = Path(directory)
    binary_dir = temp / 'bin'
    binary_dir.mkdir()
    gh = binary_dir / 'gh'
    gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args[:2] == ['auth', 'status']:
    sys.exit(1)  # A stale inactive account must not block the active one.
if args[:2] == ['api', 'user']:
    sys.exit(0 if os.environ['TEST_ACTIVE_AUTH'] == 'valid' else 1)
if args[:2] == ['secret', 'set']:
    body_ok = sys.stdin.read() == 'throwaway-test-key'
    Path(os.environ['TEST_RECORD']).write_text(json.dumps({'args': args, 'body_ok': body_ok}))
    sys.exit(0 if body_ok else 1)
sys.exit(2)
''')
    keys = binary_dir / 'generate_keys'
    keys.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
if '-p' in sys.argv:
    print(os.environ['TEST_PUBLIC_KEY'])
elif '-x' in sys.argv:
    Path(sys.argv[sys.argv.index('-x') + 1]).write_text('throwaway-test-key')
else:
    sys.exit(2)
''')
    gh.chmod(0o755); keys.chmod(0o755)
    record = temp / 'record.json'
    env = dict(os.environ, PATH=str(binary_dir) + os.pathsep + os.environ['PATH'], TMPDIR=str(temp),
               TEST_ACTIVE_AUTH='valid', TEST_PUBLIC_KEY=public_key, TEST_RECORD=str(record))
    command = [str(ROOT / 'scripts/configure-updates.sh'), str(binary_dir)]
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    sent = json.loads(record.read_text())
    assert sent['args'] == ['secret', 'set', 'SPARKLE_PRIVATE_KEY', '--repo', 'Duy-Company/nix-mind'] and sent['body_ok']
    print('✓ Valid active login configures the correct repository despite a stale inactive account')
    assert 'throwaway-test-key' not in result.stdout + result.stderr
    assert not list(temp.glob('nixmind-signing.*'))
    print('✓ Secret body stays out of logs and the temporary export is removed')
    record.unlink()
    result = subprocess.run(command, env=dict(env, TEST_ACTIVE_AUTH='invalid'), capture_output=True, text=True)
    assert result.returncode != 0 and not record.exists()
    print('✓ Invalid active login cannot export or upload a signing key')
    result = subprocess.run(command, env=dict(env, TEST_PUBLIC_KEY='unrelated-key'), capture_output=True, text=True)
    assert result.returncode != 0 and not record.exists()
    print('✓ Mismatched Keychain identity cannot overwrite the repository secret')
print('PASS: 4 update configuration checks')
