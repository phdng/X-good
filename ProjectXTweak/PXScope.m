#import "PXScope.h"
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>

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
static BOOL gCachedFullSpoofTestModeEnabled = NO;
static BOOL gCachedDisplayUIScaleEnabled = YES;
static BOOL gCachedDisplayPixelMetricsEnabled = YES;
static BOOL gCachedDisplayWebScreenEnabled = YES;
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

    // Full spoof test mode: force Safari/Auth stack spoofing ON (for failure testing).
    BOOL fullTest = PXReadSecuritySettingBool(@"fullSpoofTestModeEnabled");

    // Default behavior: if safariStackSpoofEnabled is absent, follow deviceSpoofingEnabled.
    BOOL safariEnabled = deviceEnabled;
    if (PXReadSecuritySettingHasKey(@"safariStackSpoofEnabled")) {
        safariEnabled = deviceEnabled && PXReadSecuritySettingBool(@"safariStackSpoofEnabled");
    }
    // In test mode, always allow Safari/Auth stack spoofing when global spoofing is enabled.
    if (deviceEnabled && fullTest) {
        safariEnabled = YES;
    }

    // Display spoof controls. Defaults are ON when keys are absent.
    BOOL uiScaleEnabled = deviceEnabled;
    if (PXReadSecuritySettingHasKey(@"displayUIScaleSpoofEnabled")) {
        uiScaleEnabled = deviceEnabled && PXReadSecuritySettingBool(@"displayUIScaleSpoofEnabled");
    }

    BOOL pixelMetricsEnabled = deviceEnabled;
    if (PXReadSecuritySettingHasKey(@"displayPixelMetricsSpoofEnabled")) {
        pixelMetricsEnabled = deviceEnabled && PXReadSecuritySettingBool(@"displayPixelMetricsSpoofEnabled");
    }

    BOOL webScreenEnabled = deviceEnabled;
    if (PXReadSecuritySettingHasKey(@"displayWebScreenSpoofEnabled")) {
        webScreenEnabled = deviceEnabled && PXReadSecuritySettingBool(@"displayWebScreenSpoofEnabled");
    }

    gCachedDeviceSpoofEnabled = deviceEnabled;
    gCachedFullSpoofTestModeEnabled = (deviceEnabled && fullTest);
    gCachedSafariStackEnabled = safariEnabled;
    gCachedDisplayUIScaleEnabled = uiScaleEnabled;
    gCachedDisplayPixelMetricsEnabled = pixelMetricsEnabled;
    gCachedDisplayWebScreenEnabled = webScreenEnabled;
    gCacheValid = YES;
}

__attribute__((constructor))
static void PXScopeInit(void) {
    // MB Bank is extremely sensitive to early Foundation/CF initialization.
    // Avoid installing these observers there; MB Bank uses MBBankMinimalInit.x.
    extern const char *__progname;
    if (__progname && strcmp(__progname, "MB Bank") == 0) {
        return;
    }

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

BOOL PXFullSpoofTestModeEnabled(void) {
    PXEnsureScopeCache();
    return gCachedFullSpoofTestModeEnabled;
}

BOOL PXDisplayUIScaleSpoofEnabled(void) {
    PXEnsureScopeCache();
    return gCachedDisplayUIScaleEnabled;
}

BOOL PXDisplayPixelMetricsSpoofEnabled(void) {
    PXEnsureScopeCache();
    return gCachedDisplayPixelMetricsEnabled;
}

BOOL PXDisplayWebScreenSpoofEnabled(void) {
    PXEnsureScopeCache();
    return gCachedDisplayWebScreenEnabled;
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
