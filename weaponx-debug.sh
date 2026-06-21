#!/bin/sh

# WeaponX Debug Script for rootful/rootless layouts

first_existing_dir() {
    for p in "$@"; do
        if [ -d "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    echo "$1"
}

first_existing_file() {
    fallback="$1"
    for p in "$@"; do
        if [ -f "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    echo "$fallback"
}

MOBILE_LIBRARY="$(first_existing_dir "/var/mobile/Library" "/private/var/mobile/Library" "/var/jb/var/mobile/Library" "/private/var/jb/var/mobile/Library")"
WEAPONX_BASE="$MOBILE_LIBRARY/WeaponX"
PROFILES_DIR="$WEAPONX_BASE/Profiles"
PREFS_DIR="$MOBILE_LIBRARY/Preferences"
CURRENT_PROFILE_INFO="$PROFILES_DIR/current_profile_info.plist"
LEGACY_ACTIVE_PROFILE_INFO="$WEAPONX_BASE/active_profile_info.plist"
SETTINGS_PLIST="$PREFS_DIR/com.hydra.projectx.settings.plist"
GLOBAL_SCOPE_PLIST="$PREFS_DIR/com.hydra.projectx.global_scope.plist"
SECURITY_SETTINGS_PLIST="$PREFS_DIR/com.weaponx.securitySettings.plist"

LIBRARY_BASE="$(first_existing_dir "/Library" "/var/jb/Library" "/private/var/jb/Library")"
DAEMON_PATH="$(first_existing_file "$LIBRARY_BASE/WeaponX/WeaponXDaemon" "/Library/WeaponX/WeaponXDaemon" "/var/jb/Library/WeaponX/WeaponXDaemon" "/private/var/jb/Library/WeaponX/WeaponXDaemon")"
LAUNCH_DAEMON_PLIST="$(first_existing_file "$LIBRARY_BASE/LaunchDaemons/com.hydra.weaponx.guardian.plist" "/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist" "/var/jb/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist" "/private/var/jb/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist")"
GUARDIAN_DIR="$(first_existing_dir "$LIBRARY_BASE/WeaponX/Guardian" "/Library/WeaponX/Guardian" "/var/jb/Library/WeaponX/Guardian" "/private/var/jb/Library/WeaponX/Guardian")"
TWEAK_DIR="$(first_existing_dir "/Library/MobileSubstrate/DynamicLibraries" "/var/jb/Library/MobileSubstrate/DynamicLibraries" "/private/var/jb/Library/MobileSubstrate/DynamicLibraries")"

echo "=== WeaponX Debug Tool ==="
echo ""

echo "0. Resolved paths..."
echo "   Mobile Library: $MOBILE_LIBRARY"
echo "   WeaponX Base: $WEAPONX_BASE"
echo "   Profiles Dir: $PROFILES_DIR"
echo "   Preferences Dir: $PREFS_DIR"
echo "   Library Base: $LIBRARY_BASE"
echo ""

# Check daemon status
echo "1. Checking WeaponXDaemon..."
if [ -f "$DAEMON_PATH" ]; then
    echo "   ✅ Daemon binary exists"
    ls -la "$DAEMON_PATH"
else
    echo "   ❌ Daemon binary NOT found"
fi

echo ""
echo "2. Checking LaunchDaemon plist..."
if [ -f "$LAUNCH_DAEMON_PLIST" ]; then
    echo "   ✅ LaunchDaemon plist exists"
    ls -la "$LAUNCH_DAEMON_PLIST"
else
    echo "   ❌ LaunchDaemon plist NOT found"
fi

echo ""
echo "3. Checking if daemon is loaded..."
if launchctl list | grep -q "com.hydra.weaponx.guardian"; then
    echo "   ✅ Daemon is loaded in launchctl"
    launchctl list | grep "com.hydra.weaponx.guardian"
else
    echo "   ❌ Daemon is NOT loaded"
fi

echo ""
echo "4. Checking if daemon process is running..."
if ps aux | grep -v grep | grep WeaponXDaemon > /dev/null; then
    echo "   ✅ Daemon process is running"
    ps aux | grep -v grep | grep WeaponXDaemon
else
    echo "   ❌ Daemon process is NOT running"
fi

echo ""
echo "5. Checking Guardian log directory..."
if [ -d "$GUARDIAN_DIR" ]; then
    echo "   ✅ Guardian directory exists"
    ls -la "$GUARDIAN_DIR/"
else
    echo "   ❌ Guardian directory NOT found"
fi

echo ""
echo "6. Checking recent daemon logs..."
if [ -f "$GUARDIAN_DIR/daemon.log" ]; then
    echo "   Last 20 lines of daemon.log:"
    tail -20 "$GUARDIAN_DIR/daemon.log"
else
    echo "   ❌ daemon.log NOT found"
fi

echo ""
echo "7. Checking stderr log..."
if [ -f "$GUARDIAN_DIR/guardian-stderr.log" ]; then
    echo "   Last 10 lines of guardian-stderr.log:"
    tail -10 "$GUARDIAN_DIR/guardian-stderr.log"
else
    echo "   ❌ guardian-stderr.log NOT found"
fi

echo ""
echo "8. Checking ProjectX app..."
if [ -d "/Applications/ProjectX.app" ]; then
    echo "   ✅ ProjectX.app exists"
    ls -la "/Applications/ProjectX.app/"
else
    echo "   ❌ ProjectX.app NOT found"
fi

echo ""
echo "9. Checking WeaponX user data..."
if [ -d "$WEAPONX_BASE" ]; then
    echo "   ✅ WeaponX user directory exists"
    ls -la "$WEAPONX_BASE/"
else
    echo "   ❌ WeaponX user directory NOT found"
fi

echo ""
echo "10. Checking Profiles..."
if [ -d "$PROFILES_DIR" ]; then
    echo "   ✅ Profiles directory exists"
    ls -la "$PROFILES_DIR/"
else
    echo "   ❌ Profiles directory NOT found"
fi

echo ""
echo "11. Checking tweak..."
if [ -f "$TWEAK_DIR/ProjectXTweak.dylib" ]; then
    echo "   ✅ Tweak dylib exists"
    ls -la "$TWEAK_DIR/ProjectXTweak."*
else
    echo "   ❌ Tweak dylib NOT found"
fi

echo ""
echo "12. Checking profile source of truth..."
if [ -f "$CURRENT_PROFILE_INFO" ]; then
    echo "   ✅ current_profile_info.plist exists: $CURRENT_PROFILE_INFO"
    plutil -p "$CURRENT_PROFILE_INFO" 2>/dev/null || cat "$CURRENT_PROFILE_INFO" 2>/dev/null
elif [ -f "$LEGACY_ACTIVE_PROFILE_INFO" ]; then
    echo "   ⚠️ current profile missing, legacy active profile exists: $LEGACY_ACTIVE_PROFILE_INFO"
    plutil -p "$LEGACY_ACTIVE_PROFILE_INFO" 2>/dev/null || cat "$LEGACY_ACTIVE_PROFILE_INFO" 2>/dev/null
else
    echo "   ❌ No current or legacy active profile info found"
fi

echo ""
echo "13. Checking settings/scope plists..."
for p in "$SETTINGS_PLIST" "$GLOBAL_SCOPE_PLIST" "$SECURITY_SETTINGS_PLIST"; do
    if [ -f "$p" ]; then
        echo "   ✅ $p"
        ls -la "$p"
    else
        echo "   ⚠️ Missing $p"
    fi
done

echo ""
echo "14. Pre-hook readiness checks..."
if [ -f "$CURRENT_PROFILE_INFO" ] && [ -f "$GLOBAL_SCOPE_PLIST" ]; then
    echo "   ✅ Profile and scope files are present"
else
    echo "   ⚠️ Resolve profile/scope state before enabling path hooks"
fi

if [ -f "$TWEAK_DIR/ProjectXTweak.dylib" ]; then
    echo "   ✅ Runtime tweak installed"
else
    echo "   ⚠️ Runtime tweak not installed; hook validation cannot run"
fi

echo ""
echo "=== Debug Complete ==="
