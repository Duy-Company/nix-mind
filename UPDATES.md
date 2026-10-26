# Maintaining in-app updates

**Status:** enabled via `NixMindUpdatesEnabled = true`; the production signing key is configured as the encrypted `SPARKLE_PRIVATE_KEY` repository secret. Version 1.0.5 is the first updater-enabled release and publishes the signed public feed. Existing 1.0.4 downloads remain unchanged and need a one-time manual upgrade to 1.0.5. Branch pushes continue to run Debug CI only.

Nix Mind uses Sparkle 2.10.0. The app's **Check for Updates…** menu checks a signed feed at:

`https://github.com/Duy-Company/nix-mind/releases/latest/download/appcast.xml`

The feed points to an immutable universal ZIP in the corresponding versioned GitHub release. Both the feed (including embedded release notes) and archive are signed with Ed25519. The app verifies the feed and verifies the archive before extraction. Automatic checks default to daily; installation remains user initiated. No update checks run in MCP stdio mode.

## One-time signing setup

The signing identity's public key is in `NixMind/Info.plist` as `SUPublicEDKey`. Its private key was generated in the maintainer's macOS login Keychain under the Sparkle account **com.nixmind.mac**. Do not regenerate or replace this identity after distributing an updater-enabled app. Back up the key securely; ad-hoc signing does not provide a Developer ID fallback for key rotation.

After building the app and signing in to GitHub CLI with repository secrets access:

```sh
gh auth login
./scripts/configure-updates.sh
```

This checks that the Keychain public key matches the app, exports the private key into an owner-only temporary directory, sends it directly to the repository's encrypted **SPARKLE_PRIVATE_KEY** Actions secret, and removes the temporary export. It does not print the private key or add it to Git. On a new machine, restore the backed-up key using Sparkle's `generate_keys --account com.nixmind.mac -f /secure/path/key` before running the setup script.

For a Debug build with a different derived-data folder, pass the tools directory explicitly, for example:

```sh
./scripts/configure-updates.sh build/updater-debug/SourcePackages/artifacts/sparkle/Sparkle/bin
```

The source configuration is now enabled. The setup command is only needed again when deliberately restoring the same identity on another machine or updating the repository secret; regular releases reuse it automatically.

## Publishing a version

1. Set `CFBundleShortVersionString` **and** `CFBundleVersion` to the same increasing release version. Keep the MCP response versions, export metadata, and MCP regression expectation in sync.
2. Write `release-notes/vVERSION.md` and run the relevant tests.
3. Push the commit and matching version tag when a release is requested.

The tag workflow requires the signing secret, builds and signs the universal app, tests MCP and updater packaging, and runs `scripts/create-appcast.py`. That script reads the secret through standard input to Sparkle's tool, embeds release notes, and independently verifies the feed and ZIP against the app's public key using CryptoKit. A mismatched or missing key fails publication. It includes only the current ZIP, so older files in a local `dist/` cannot accidentally become update entries.

The release stays a draft until ZIP, DMG, checksums, and `appcast.xml` are uploaded. Publishing it as latest switches the feed endpoint. Keep `appcast.xml` attached to every future stable release; do not promote a historical release without a signed feed to latest. Do not modify a published feed, archive, or release notes without regenerating its signatures.

To generate a feed locally after packaging, using the Keychain identity:

```sh
python3 scripts/create-appcast.py
```

This does not upload or publish anything. CI reads `SPARKLE_PRIVATE_KEY`; local generation defaults to the dedicated Keychain account. A source checkout's Debug bundle can be tested with:

```sh
./scripts/test-updater.sh 'build/updater-debug/Build/Products/Debug/Nix Mind.app' \
  build/updater-debug/SourcePackages/artifacts/sparkle/Sparkle
```

The test uses temporary app copies and throwaway signing keys. It never replaces the installed app, starts MCP, or edits user documents. A real production upgrade between two published updater-enabled versions still needs an end-to-end check when those versions exist.

## Signing distinction

Sparkle update signatures authenticate downloads and feed metadata. They are separate from Apple's Developer ID signing and notarization. Releases remain ad-hoc signed until that distribution setup is configured. The first updater-enabled app must be installed manually. Versions through 1.0.3 have no updater, and 1.0.4 includes the framework with update checks disabled.
