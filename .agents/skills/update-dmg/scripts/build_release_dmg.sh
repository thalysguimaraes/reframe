#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 /path/to/Reframe.app [output.dmg]" >&2
    exit 1
fi

app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found: $app_path" >&2
    exit 1
fi

app_name="$(basename "$app_path" .app)"
output_path="${2:-$(cd "$(dirname "$app_path")/.." && pwd)/$app_name.dmg}"
volume_name="${VOLUME_NAME:-$app_name}"

tmp_dir="$(mktemp -d)"
staging_dir="$tmp_dir/staging"
mkdir -p "$staging_dir"
trap 'rm -rf "$tmp_dir"' EXIT

echo "==> Preparing DMG staging directory"
ditto "$app_path" "$staging_dir/$app_name.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$output_path"

echo "==> Creating DMG at $output_path"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$output_path"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "==> Signing DMG with $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$output_path"
    codesign --verify --verbose=2 "$output_path"
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "==> Notarizing DMG"
    xcrun notarytool submit "$output_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$output_path"
    xcrun stapler validate "$output_path"
else
    echo "==> Skipping DMG notarization because Apple credentials are not fully set"
fi

hdiutil verify "$output_path"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    spctl --assess --type open --context context:primary-signature --verbose=4 "$output_path"
else
    echo "==> Skipping Gatekeeper assessment because SIGNING_IDENTITY is not set"
fi
echo "==> DMG ready: $output_path"
