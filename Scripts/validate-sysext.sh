#!/bin/bash
# Validates the built app bundle for system extension correctness.
# Run after building: ./Scripts/validate-sysext.sh [path-to-app]
set -euo pipefail

APP="${1:-$(find ~/Library/Developer/Xcode/DerivedData/AutoFrameCam-*/Build/Products/Debug -name "AutoFrame Cam.app" -maxdepth 1 2>/dev/null | head -1)}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "FAIL: App bundle not found. Build first or pass path as argument."
    exit 1
fi

SYSEXT="${SYSEXT:-$(find "$APP/Contents/Library/SystemExtensions" -maxdepth 1 -name "*.systemextension" -type d 2>/dev/null | head -1)}"
PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (got '$actual', expected '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

check_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Validating: $APP ==="
echo ""

# --- App bundle structure ---
echo "[App Bundle Structure]"
check "App bundle exists" test -d "$APP"
check "App executable exists" test -f "$APP/Contents/MacOS/AutoFrame Cam"
check "App Info.plist exists" test -f "$APP/Contents/Info.plist"
check "SystemExtensions dir exists" test -d "$APP/Contents/Library/SystemExtensions"
check "Extension bundle exists" test -d "$SYSEXT"
check "Extension executable dir exists" test -d "$SYSEXT/Contents/MacOS"
check "Extension Info.plist exists" test -f "$SYSEXT/Contents/Info.plist"
check "Extension provisioning profile exists" test -f "$SYSEXT/Contents/embedded.provisionprofile"
echo ""

# --- Extension Info.plist ---
echo "[Extension Info.plist]"
EXT_PLIST=$(plutil -convert json -o - "$SYSEXT/Contents/Info.plist" 2>/dev/null || echo "{}")

PKG_TYPE=$(echo "$EXT_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CFBundlePackageType','MISSING'))" 2>/dev/null)
check_eq "CFBundlePackageType is SYSX" "$PKG_TYPE" "SYSX"

BUNDLE_ID=$(echo "$EXT_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CFBundleIdentifier','MISSING'))" 2>/dev/null)
check_eq "CFBundleIdentifier" "$BUNDLE_ID" "dev.autoframe.AutoFrameCam.CameraExtension"

MACH_SVC=$(echo "$EXT_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CMIOExtension',{}).get('CMIOExtensionMachServiceName','MISSING'))" 2>/dev/null)

HAS_EXEC=$(echo "$EXT_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CFBundleExecutable','MISSING'))" 2>/dev/null)
check "CFBundleExecutable is set" test "$HAS_EXEC" != "MISSING"
check "CFBundleExecutable exists on disk" test -f "$SYSEXT/Contents/MacOS/$HAS_EXEC"
echo ""

# --- App Info.plist ---
echo "[App Info.plist]"
APP_PLIST=$(plutil -convert json -o - "$APP/Contents/Info.plist" 2>/dev/null || echo "{}")

APP_PKG=$(echo "$APP_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CFBundlePackageType','MISSING'))" 2>/dev/null)
check_eq "App CFBundlePackageType is APPL" "$APP_PKG" "APPL"

SYSEXT_DESC=$(echo "$APP_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('NSSystemExtensionUsageDescription','MISSING'))" 2>/dev/null)
check "App has NSSystemExtensionUsageDescription" test "$SYSEXT_DESC" != "MISSING"

EXPECTED_APP_GROUP=$(echo "$APP_PLIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('AutoFrameAppGroupID','group.dev.autoframe.cam'))" 2>/dev/null)
check "App config declares AutoFrameAppGroupID" test "$EXPECTED_APP_GROUP" != ""
check_eq "CMIOExtensionMachServiceName matches shared app group" "$MACH_SVC" "$EXPECTED_APP_GROUP"
echo ""

# --- Code Signing ---
echo "[Code Signing]"
check "App signature valid (deep strict)" codesign --verify --deep --strict "$APP"

APP_SIGN_INFO=$(codesign -dvvv "$APP" 2>&1)
check_contains "App and extension same team" "$APP_SIGN_INFO" "TeamIdentifier=B27B4ED4CL"

EXT_SIGN_INFO=$(codesign -dvvv "$SYSEXT" 2>&1)
check_contains "Extension signed by same team" "$EXT_SIGN_INFO" "TeamIdentifier=B27B4ED4CL"
echo ""

# --- Entitlements ---
echo "[Entitlements]"
APP_ENT=$(codesign -d --entitlements - "$APP" 2>&1)
check_contains "App has system-extension.install entitlement" "$APP_ENT" "com.apple.developer.system-extension.install"
check_contains "App has app-sandbox entitlement" "$APP_ENT" "com.apple.security.app-sandbox"
check_contains "App has camera entitlement" "$APP_ENT" "com.apple.security.device.camera"
check_contains "App has app-groups entitlement" "$APP_ENT" "com.apple.security.application-groups"

EXT_ENT=$(codesign -d --entitlements - "$SYSEXT" 2>&1)
check_contains "Extension has app-sandbox entitlement" "$EXT_ENT" "com.apple.security.app-sandbox"
check_contains "Extension has app-groups entitlement" "$EXT_ENT" "com.apple.security.application-groups"
echo ""

# --- Provisioning Profiles ---
echo "[Provisioning Profiles]"
APP_PROFILE=$(security cms -D -i "$APP/Contents/embedded.provisionprofile" 2>/dev/null || echo "")
APP_PROFILE_NAME=$(echo "$APP_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
print(data.get('Name','MISSING'))
" 2>/dev/null || echo "MISSING")
check "App has provisioning profile" test "$APP_PROFILE_NAME" != "MISSING"
echo "  INFO: App profile: $APP_PROFILE_NAME"

APP_PROFILE_SYSEXT=$(echo "$APP_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
ents = data.get('Entitlements', {})
print('YES' if ents.get('com.apple.developer.system-extension.install') else 'NO')
" 2>/dev/null || echo "NO")
check_eq "App profile has system-extension.install" "$APP_PROFILE_SYSEXT" "YES"

APP_PROFILE_GROUPS=$(echo "$APP_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
ents = data.get('Entitlements', {})
groups = ents.get('com.apple.security.application-groups', [])
print('\\n'.join(groups))
" 2>/dev/null || echo "")
check_contains "App profile includes expected app group" "$APP_PROFILE_GROUPS" "$EXPECTED_APP_GROUP"

EXT_PROFILE=$(security cms -D -i "$SYSEXT/Contents/embedded.provisionprofile" 2>/dev/null || echo "")
EXT_PROFILE_NAME=$(echo "$EXT_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
print(data.get('Name','MISSING'))
" 2>/dev/null || echo "MISSING")
check "Extension has provisioning profile" test "$EXT_PROFILE_NAME" != "MISSING"
echo "  INFO: Extension profile: $EXT_PROFILE_NAME"

EXT_PROFILE_APPID=$(echo "$EXT_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
ents = data.get('Entitlements', {})
print(ents.get('com.apple.application-identifier', 'MISSING'))
" 2>/dev/null || echo "MISSING")
echo "  INFO: Extension profile app ID: $EXT_PROFILE_APPID"

IS_WILDCARD="NO"
if echo "$EXT_PROFILE_APPID" | grep -q '\*'; then
    IS_WILDCARD="YES"
fi
check_eq "Extension profile is NOT wildcard" "$IS_WILDCARD" "NO"

# Check extension profile has app-groups
EXT_PROFILE_GROUPS=$(echo "$EXT_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
ents = data.get('Entitlements', {})
groups = ents.get('com.apple.security.application-groups', [])
print('YES' if groups else 'NO')
" 2>/dev/null || echo "NO")
check_eq "Extension profile has app-groups capability" "$EXT_PROFILE_GROUPS" "YES"

EXT_PROFILE_GROUP_LIST=$(echo "$EXT_PROFILE" | python3 -c "
import sys, plistlib
data = plistlib.loads(sys.stdin.buffer.read())
ents = data.get('Entitlements', {})
groups = ents.get('com.apple.security.application-groups', [])
print('\\n'.join(groups))
" 2>/dev/null || echo "")
check_contains "Extension profile includes expected app group" "$EXT_PROFILE_GROUP_LIST" "$EXPECTED_APP_GROUP"
echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
