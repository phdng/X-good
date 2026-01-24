#!/bin/sh

# WeaponX Debug Script for Rootful iOS 12+
ROOT_PREFIX=""

echo "=== WeaponX Debug Tool ==="
echo ""

# Check daemon status
echo "1. Checking WeaponXDaemon..."
if [ -f "/Library/WeaponX/WeaponXDaemon" ]; then
    echo "   ✅ Daemon binary exists"
    ls -la "/Library/WeaponX/WeaponXDaemon"
else
    echo "   ❌ Daemon binary NOT found"
fi

echo ""
echo "2. Checking LaunchDaemon plist..."
if [ -f "/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist" ]; then
    echo "   ✅ LaunchDaemon plist exists"
    ls -la "/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist"
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
if [ -d "/Library/WeaponX/Guardian" ]; then
    echo "   ✅ Guardian directory exists"
    ls -la "/Library/WeaponX/Guardian/"
else
    echo "   ❌ Guardian directory NOT found"
fi

echo ""
echo "6. Checking recent daemon logs..."
if [ -f "/Library/WeaponX/Guardian/daemon.log" ]; then
    echo "   Last 20 lines of daemon.log:"
    tail -20 "/Library/WeaponX/Guardian/daemon.log"
else
    echo "   ❌ daemon.log NOT found"
fi

echo ""
echo "7. Checking stderr log..."
if [ -f "/Library/WeaponX/Guardian/guardian-stderr.log" ]; then
    echo "   Last 10 lines of guardian-stderr.log:"
    tail -10 "/Library/WeaponX/Guardian/guardian-stderr.log"
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
if [ -d "/var/mobile/Library/WeaponX" ]; then
    echo "   ✅ WeaponX user directory exists"
    ls -la "/var/mobile/Library/WeaponX/"
else
    echo "   ❌ WeaponX user directory NOT found"
fi

echo ""
echo "10. Checking Profiles..."
if [ -d "/var/mobile/Library/WeaponX/Profiles" ]; then
    echo "   ✅ Profiles directory exists"
    ls -la "/var/mobile/Library/WeaponX/Profiles/"
else
    echo "   ❌ Profiles directory NOT found"
fi

echo ""
echo "11. Checking tweak..."
if [ -f "/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.dylib" ]; then
    echo "   ✅ Tweak dylib exists"
    ls -la "/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak."*
else
    echo "   ❌ Tweak dylib NOT found"
fi

echo ""
echo "=== Debug Complete ==="