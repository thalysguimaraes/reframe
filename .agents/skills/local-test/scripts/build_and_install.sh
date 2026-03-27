#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"

configuration="${CONFIGURATION:-Release}"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/build/local-test}"
install_path="${INSTALL_PATH:-/Applications/Reframe.app}"
launch_after_install="${LAUNCH_AFTER_INSTALL:-0}"
project_path="${PROJECT_PATH:-$repo_root/Reframe.xcodeproj}"
scheme="${SCHEME:-Reframe}"
bundle_name="$(basename "$install_path")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required but not installed." >&2
    exit 1
fi

cd "$repo_root"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building $scheme ($configuration)"
xcodebuild \
    -project "$project_path" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data_path" \
    build

built_app="$derived_data_path/Build/Products/$configuration/$bundle_name"
if [[ ! -d "$built_app" ]]; then
    echo "Built app not found at $built_app" >&2
    exit 1
fi

echo "==> Validating built app bundle"
"$repo_root/Scripts/validate-sysext.sh" "$built_app"

echo "==> Stopping any running Reframe instance"
osascript -e 'tell application id "dev.autoframe.AutoFrameCam" to quit' >/dev/null 2>&1 || true
pkill -x Reframe >/dev/null 2>&1 || true

for _ in {1..20}; do
    if ! pgrep -x Reframe >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if pgrep -x Reframe >/dev/null 2>&1; then
    echo "Reframe is still running; refusing to replace the installed app." >&2
    exit 1
fi

backup_path=""
restore_backup() {
    if [[ -n "$backup_path" && -d "$backup_path" && ! -d "$install_path" ]]; then
        mv "$backup_path" "$install_path"
    fi
}
trap restore_backup ERR

echo "==> Installing to $install_path"
if [[ -d "$install_path" ]]; then
    backup_path="${install_path}.codex-backup-$$"
    rm -rf "$backup_path"
    mv "$install_path" "$backup_path"
fi

ditto "$built_app" "$install_path"
codesign --verify --deep --strict "$install_path"

if [[ -n "$backup_path" && -d "$backup_path" ]]; then
    rm -rf "$backup_path"
fi
trap - ERR

short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$install_path/Contents/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$install_path/Contents/Info.plist")"

echo "==> Installed $install_path"
echo "Version: $short_version ($build_version)"

echo "==> Activating embedded system extension"
"$install_path/Contents/MacOS/Reframe" --activate-extension

if [[ "$launch_after_install" == "1" ]]; then
    echo "==> Launching $install_path"
    open "$install_path"
fi
