#!/usr/bin/env python3
"""Exercise the real embedded updater and signed feed with throwaway keys/apps."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from threading import Thread
import uuid

ROOT = Path(__file__).resolve().parent.parent


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--sparkle', type=Path, required=True)
    args = parser.parse_args()
    sparkle = args.sparkle.resolve()
    framework = sparkle / 'Sparkle.xcframework/macos-arm64_x86_64'
    cache = ROOT / 'build/test-cache'
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nixmind-updater-tests-') as directory:
        temp = Path(directory)
        host = temp / 'Nix Mind.app'
        shutil.copytree(args.app, host, symlinks=True)
        # The harness replaces the app executable; Xcode Debug preview dylibs are unused.
        shutil.rmtree(host / 'Contents/MacOS')
        (host / 'Contents/MacOS').mkdir()
        binary = host / 'Contents/MacOS/Nix Mind'
        # Compile the actual updater implementation against the pinned package.
        run(['swiftc', '-parse-as-library', '-module-cache-path', cache,
             '-F', framework, '-framework', 'Sparkle',
             '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
             ROOT / 'NixMind/AppUpdater.swift', ROOT / 'Tests/UpdaterTests.swift', '-o', binary])
        key_file = temp / 'test-key'
        key = run([binary, '--create-key', key_file], capture_output=True, text=True).stdout.strip()
        info_path = host / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info.update(CFBundleIdentifier=f'com.nixmind.updater-tests.{uuid.uuid4().hex}',
                    CFBundleVersion='1.0.4', CFBundleShortVersionString='1.0.4',
                    SUPublicEDKey=key, SUEnableAutomaticChecks=False, NixMindUpdatesEnabled=True)
        info_path.write_bytes(plistlib.dumps(info))
        run(['codesign', '--force', '--sign', '-', '--timestamp=none', host / 'Contents/Frameworks/Sparkle.framework'])
        run(['codesign', '--force', '--sign', '-', '--timestamp=none', host])
        # This only launches the temporary test harness; no documents or MCP listener.
        run([binary])
        test_identifier = info['CFBundleIdentifier']
        info['CFBundleIdentifier'] = 'com.nixmind.mac'
        info_path.write_bytes(plistlib.dumps(info))
        run(['codesign', '--force', '--sign', '-', '--timestamp=none', host])
        archive = temp / 'Nix-Mind-1.0.4-macos-universal.zip'
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', host, archive])
        expected_info = temp / 'Expected-Info.plist'
        expected = dict(info, CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)')
        expected_info.write_bytes(plistlib.dumps(expected))
        checksums = temp / 'SHA256SUMS.txt'
        checksums.write_text(f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n')
        notes = temp / 'notes.md'
        notes.write_text('Test update with signed **release notes**.\n')
        feed = temp / 'appcast.xml'
        env = dict(os.environ, SPARKLE_PRIVATE_KEY=key_file.read_text(), RELEASE_TAG='v1.0.4')
        command = ['python3', ROOT / 'scripts/create-appcast.py', '--archive', archive,
                   '--info', expected_info, '--notes', notes, '--tools', sparkle / 'bin', '--output', feed]
        run(command, env=env)
        checks = 2
        print('✓ Signed feed generation resolves the source plist bundle identifier')
        assert checksums.read_text().splitlines()[-1] == f'{hashlib.sha256(feed.read_bytes()).hexdigest()}  appcast.xml'
        print('✓ Published checksums include the signed appcast')
        expected['NixMindUpdatesEnabled'] = False
        expected_info.write_bytes(plistlib.dumps(expected))
        disabled = subprocess.run([str(x) for x in command], env=env, capture_output=True, text=True)
        assert disabled.returncode != 0, 'A disabled updater must not be published as an update target'
        expected['NixMindUpdatesEnabled'] = True
        expected_info.write_bytes(plistlib.dumps(expected))
        checks += 1
        print('✓ Publisher refuses an updater-disabled app configuration')
        # Exercise Sparkle's own feed validation, not only our independent verifier.
        # Only this temporary host permits localhost HTTP; production uses HTTPS.
        info.update(CFBundleIdentifier=test_identifier, CFBundleVersion='1.0.3', CFBundleShortVersionString='1.0.3',
                    NSAppTransportSecurity={'NSAllowsArbitraryLoads': True})
        info_path.write_bytes(plistlib.dumps(info))
        served_feed = feed.read_bytes()

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Type', 'application/xml')
                self.end_headers()
                self.wfile.write(served_feed)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f'http://127.0.0.1:{server.server_port}/appcast.xml'
            run([binary, '--probe', url, '1.0.4'])
            served_feed = served_feed.replace(b'Test update', b'Fake update', 1)
            run([binary, '--probe', url, 'reject'])
            checks += 2
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        info.update(CFBundleVersion='1.0.4', CFBundleShortVersionString='1.0.4')
        info.pop('NSAppTransportSecurity')
        info_path.write_bytes(plistlib.dumps(info))
        verifier = ['swift', '-module-cache-path', cache, ROOT / 'scripts/verify-update.swift', feed, archive, expected_info]

        def rejected(message):
            nonlocal checks
            result = subprocess.run([str(x) for x in verifier], capture_output=True, text=True)
            if result.returncode == 0:
                raise AssertionError(message)
            checks += 1
            print(f'✓ {message}')

        original_feed = feed.read_bytes()
        feed.write_bytes(original_feed.replace(b'Test update', b'Fake update', 1))
        rejected('Modified release notes invalidate the feed signature')
        feed.write_bytes(original_feed)
        with archive.open('ab') as output:
            output.write(b'tampered')
        rejected('Modified downloaded archive is rejected')
        with archive.open('r+b') as output:
            output.truncate(archive.stat().st_size - len(b'tampered'))
        other_key_file = temp / 'other-key'
        other_key = run([binary, '--create-key', other_key_file], capture_output=True, text=True).stdout.strip()
        expected['SUPublicEDKey'] = other_key
        expected_info.write_bytes(plistlib.dumps(expected))
        rejected('Feed signed by a different key is rejected')
        expected['SUPublicEDKey'] = key
        expected_info.write_bytes(plistlib.dumps(expected))
        wrong_env = dict(env, SPARKLE_PRIVATE_KEY=other_key_file.read_text())
        result = subprocess.run([str(x) for x in command], env=wrong_env, capture_output=True, text=True)
        assert result.returncode != 0, 'Signing with an unrelated key must fail'
        checks += 1
        print('✓ Publisher refuses a key that does not match the app')
        feed.write_bytes(b'<rss><channel/></rss>')
        rejected('Unsigned feed is rejected')
        if os.environ.get('CI'):
            missing_env = dict(env)
            missing_env.pop('SPARKLE_PRIVATE_KEY')
            result = subprocess.run([str(x) for x in command], env=missing_env, capture_output=True, text=True)
            assert result.returncode != 0, 'CI must refuse to publish without its signing secret'
            checks += 1
            print('✓ CI refuses to publish without the signing secret')
        print(f'PASS: {checks} updater packaging checks')


if __name__ == '__main__':
    main()
