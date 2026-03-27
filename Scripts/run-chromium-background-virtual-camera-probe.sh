#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli_path="${CLI_PATH:-$repo_root/build/cli/Build/Products/Debug/reframe}"
browser_app="${BROWSER_APP:-/Applications/Dia.app}"
browser_name="$(basename "$browser_app" .app)"
browser_executable="${BROWSER_EXECUTABLE:-$browser_app/Contents/MacOS/$browser_name}"
browser_port="${BROWSER_PORT:-9333}"
browser_profile_dir="${BROWSER_PROFILE_DIR:-$repo_root/build/chromium-probe-profile}"
app_path="${APP_PATH:-/Applications/Reframe.app}"
app_process_name="${APP_PROCESS_NAME:-Reframe}"
artifacts_dir="${ARTIFACTS_DIR:-$repo_root/build/chromium-background-probe}"
probe_duration_ms="${PROBE_DURATION_MS:-8000}"

mkdir -p "$artifacts_dir" "$browser_profile_dir"

if [[ ! -x "$cli_path" ]]; then
  echo "CLI binary not found at $cli_path" >&2
  exit 1
fi

if [[ ! -x "$browser_executable" ]]; then
  echo "Browser executable not found at $browser_executable" >&2
  exit 1
fi

if [[ ! -d "$app_path" ]]; then
  echo "Installed app not found at $app_path" >&2
  exit 1
fi

artifact_stamp="$(date +%Y%m%d-%H%M%S)"
output_path="$artifacts_dir/chromium-probe-$artifact_stamp.json"

pkill -x "$app_process_name" >/dev/null 2>&1 || true
pkill -f "$browser_executable.*remote-debugging-port=$browser_port" >/dev/null 2>&1 || true
rm -rf "$browser_profile_dir"
mkdir -p "$browser_profile_dir"
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
  echo "Expected zero visible Reframe windows after hiding the main window, got $window_count." >&2
  exit 1
fi

"$browser_executable" \
  --user-data-dir="$browser_profile_dir" \
  --remote-debugging-port="$browser_port" \
  --use-fake-ui-for-media-stream \
  --autoplay-policy=no-user-gesture-required \
  about:blank >/dev/null 2>&1 &
browser_pid=$!
trap 'kill "$browser_pid" >/dev/null 2>&1 || true' EXIT

for _ in {1..40}; do
  if curl -sf "http://127.0.0.1:$browser_port/json/version" >/dev/null; then
    break
  fi
  sleep 0.25
done

if ! curl -sf "http://127.0.0.1:$browser_port/json/version" >/dev/null; then
  echo "Chromium CDP endpoint did not come up on port $browser_port." >&2
  exit 1
fi

CDP_URL="http://127.0.0.1:$browser_port" \
DURATION_MS="$probe_duration_ms" \
node "$repo_root/Scripts/chromium-webrtc-probe.mjs" | tee "$output_path"

echo
echo "Artifact:"
echo "  chromium probe: $output_path"
