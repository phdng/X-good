#import "PXScope.h"
#import <CoreFoundation/CoreFoundation.h>

static id PXReadSecuritySettingObject(NSString *key) {
    if (!key.length) return nil;
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
        @"/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:[NSDictionary class]] && dict[key] != nil) {
            return dict[key];
        }
    }
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    return [securitySettings objectForKey:key];
}

static BOOL PXReadSecuritySettingHasKey(NSString *key) {
    if (!key.length) return NO;
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
        @"/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:[NSDictionary class]] && dict[key] != nil) {
            return YES;
        }
    }
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    return ([securitySettings objectForKey:key] != nil);
}

static BOOL PXReadSecuritySettingBool(NSString *key) {
    id v = PXReadSecuritySettingObject(key);
    return v ? [v boolValue] : NO;
}

// Small cache to avoid disk reads on hot paths.
static NSTimeInterval gLastSettingsRead = 0;
static BOOL gCachedDeviceSpoofEnabled = NO;
static BOOL gCachedSafariStackEnabled = NO;
static BOOL gCacheValid = NO;

static void PXInvalidateScopeCache(void) {
    gCacheValid = NO;
}

static void PXScopeNotify(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    PXInvalidateScopeCache();
}

static void PXEnsureScopeCache(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gCacheValid && (now - gLastSettingsRead) < 1.0) {
        return;
    }
    gLastSettingsRead = now;

    BOOL deviceEnabled = PXReadSecuritySettingBool(@"deviceSpoofingEnabled");

    // Default behavior: if safariStackSpoofEnabled is absent, follow deviceSpoofingEnabled.
    BOOL safariEnabled = deviceEnabled;
    if (PXReadSecuritySettingHasKey(@"safariStackSpoofEnabled")) {
        safariEnabled = deviceEnabled && PXReadSecuritySettingBool(@"safariStackSpoofEnabled");
    }

    gCachedDeviceSpoofEnabled = deviceEnabled;
    gCachedSafariStackEnabled = safariEnabled;
    gCacheValid = YES;
}

__attribute__((constructor))
static void PXScopeInit(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (!center) return;
    CFNotificationCenterAddObserver(center, NULL, PXScopeNotify, CFSTR("com.hydra.projectx.settings.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, PXScopeNotify, CFSTR("com.hydra.projectx.profileChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, PXScopeNotify, CFSTR("com.hydra.projectx.safariStackSpoofToggleChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

BOOL PXDeviceSpoofingEnabled(void) {
    PXEnsureScopeCache();
    return gCachedDeviceSpoofEnabled;
}

BOOL PXSafariStackSpoofEnabled(void) {
    PXEnsureScopeCache();
    return gCachedSafariStackEnabled;
}

BOOL PXIsSafariStackProcess(NSString *bundleID, NSString *processName) {
    if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) {
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) return YES;
        if ([bundleID isEqualToString:@"com.apple.webapp"]) return YES;
        if ([bundleID isEqualToString:@"com.apple.SafariViewService"]) return YES;
        if ([bundleID hasPrefix:@"com.apple.WebKit"]) return YES;
    }
    if ([processName isKindOfClass:[NSString class]] && processName.length) {
        if ([processName containsString:@"SafariViewService"]) return YES;
        if ([processName containsString:@"WebKit"]) return YES;
        if ([processName containsString:@"WebContent"]) return YES;
        if ([processName containsString:@"Networking"]) return YES;
        if ([processName containsString:@"GPU"]) return YES;
        if ([processName containsString:@"Safari"]) return YES;
    }
    return NO;
}

BOOL PXAllowUnscopedSafariStack(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [NSProcessInfo processInfo].processName;
    return PXSafariStackSpoofEnabled() && PXIsSafariStackProcess(bundleID, processName);
}
