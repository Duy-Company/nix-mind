#!/bin/bash
# One-time setup: transfer the existing Keychain signing key to GitHub Actions.
# Never prints the private key or stores it inside the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS=${1:-build/release/SourcePackages/artifacts/sparkle/Sparkle/bin}
# `gh auth status` also checks inactive accounts and can fail even when the
# active account is authenticated. Verify the account this script will use.
gh api user --silent >/dev/null 2>&1 || { echo 'Sign in with gh auth login first (repository secrets access is required).' >&2; exit 1; }
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' NixMind/Info.plist)
ACTUAL=$("$TOOLS/generate_keys" --account com.nixmind.mac -p)
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Keychain public key does not match this app. Do not replace the published signing identity.' >&2; exit 1; }
umask 077
KEY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nixmind-signing.XXXXXX")
trap 'rm -rf "$KEY_DIR"' EXIT
"$TOOLS/generate_keys" --account com.nixmind.mac -x "$KEY_DIR/key"
gh secret set SPARKLE_PRIVATE_KEY --repo Duy-Company/nix-mind < "$KEY_DIR/key"
echo 'GitHub Actions update signing configured. Keep a secure backup of the Keychain key.'
