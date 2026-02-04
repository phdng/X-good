// AppVersionHooks.h

#import <Foundation/Foundation.h>

// Master toggle is stored in com.weaponx.securitySettings.
BOOL PXAppVersionSpoofMasterEnabled(void);

// Returns YES if per-app spoofing is enabled and at least one of version/build is available.
// Only provides values for the passed bundleID; caller decides scope (main-bundle-only, etc.).
BOOL PXGetSpoofedAppVersionForBundle(NSString *bundleID, NSString **outVersion, NSString **outBuild);

// Invalidate cached plist reads.
void PXAppVersionHooksInvalidateCache(void);
