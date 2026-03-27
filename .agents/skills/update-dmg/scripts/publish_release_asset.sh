#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <tag> <asset-path>" >&2
    exit 1
fi

tag="$1"
asset_path="$2"

if [[ ! -f "$asset_path" ]]; then
    echo "Asset not found: $asset_path" >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required but not installed." >&2
    exit 1
fi

if gh release view "$tag" >/dev/null 2>&1; then
    echo "==> Uploading $asset_path to existing release $tag"
    gh release upload "$tag" "$asset_path" --clobber
else
    echo "==> Creating release $tag with $asset_path"
    gh release create "$tag" "$asset_path" --generate-notes
fi

echo "==> Release asset synced for $tag"
