#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli_path="${CLI_PATH:-$repo_root/build/cli/Build/Products/Debug/reframe}"
app_path="${APP_PATH:-/Applications/Reframe.app}"
app_bundle_id="${APP_BUNDLE_ID:-dev.autoframe.AutoFrameCam}"
app_process_name="${APP_PROCESS_NAME:-Reframe}"
probe_duration="${PROBE_DURATION:-8}"
artifacts_dir="${ARTIFACTS_DIR:-$repo_root/build/background-probe}"
bootstrap_log_source="${BOOTSTRAP_LOG_SOURCE:-$HOME/Library/Group Containers/group.dev.autoframe.cam/camera-extension-bootstrap.log}"

mkdir -p "$artifacts_dir"

if [[ ! -x "$cli_path" ]]; then
    echo "CLI binary not found at $cli_path" >&2
    exit 1
fi

if [[ ! -d "$app_path" ]]; then
    echo "Installed app not found at $app_path" >&2
    exit 1
fi

log_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
artifact_stamp="$(date +%Y%m%d-%H%M%S)"
probe_output_path="$artifacts_dir/probe-$artifact_stamp.txt"
logs_output_path="$artifacts_dir/logs-$artifact_stamp.txt"
bootstrap_output_path="$artifacts_dir/bootstrap-$artifact_stamp.txt"

pkill -x "$app_process_name" >/dev/null 2>&1 || true
rm -f "$bootstrap_log_source"
sleep 1

open -a "$app_path"
sleep 3

osascript -e "tell application \"$(basename "$app_path" .app)\" to activate" >/dev/null 2>&1 || true
sleep 1

window_count="$(osascript -e "tell application \"System Events\" to tell process \"$app_process_name\" to count windows")"
if [[ "$window_count" -gt 0 ]]; then
    osascript -e "tell application \"System Events\" to tell process \"$app_process_name\" to click button 1 of window 1" >/dev/null
    sleep 1
fi

window_count="$(osascript -e "tell application \"System Events\" to tell process \"$app_process_name\" to count windows")"
if [[ "$window_count" != "0" ]]; then
    echo "Expected zero visible windows after hiding the main window, got $window_count." >&2
    exit 1
fi

"$cli_path" probe-virtual-camera --duration "$probe_duration" | tee "$probe_output_path"

/usr/bin/log show \
    --style compact \
    --start "$log_start_time" \
    --info \
    --debug \
    --predicate '(subsystem == "dev.autoframe.reframe.app" && category == "capture-demand") || subsystem == "dev.autoframe.reframe.camera-extension"' \
    >"$logs_output_path"

if [[ -f "$bootstrap_log_source" ]]; then
    cp "$bootstrap_log_source" "$bootstrap_output_path"
fi

echo
echo "Artifacts:"
echo "  probe: $probe_output_path"
echo "  logs:  $logs_output_path"
if [[ -f "$bootstrap_output_path" ]]; then
    echo "  boot:  $bootstrap_output_path"
fi
