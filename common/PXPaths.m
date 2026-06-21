#import "PXPaths.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *PXFirstExistingPath(NSArray<NSString *> *paths, NSString *fallback) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if (path.length && [fm fileExistsAtPath:path]) {
            return path;
        }
    }
    return fallback;
}

NSString *PXMobileLibraryPath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = PXFirstExistingPath(@[
            @"/var/mobile/Library",
            @"/private/var/mobile/Library",
            @"/var/jb/var/mobile/Library",
            @"/private/var/jb/var/mobile/Library"
        ], @"/var/mobile/Library");
    });
    return path;
}

NSString *PXPreferencesPath(void) {
    return [PXMobileLibraryPath() stringByAppendingPathComponent:@"Preferences"];
}

NSString *PXWeaponXBasePath(void) {
    return [PXMobileLibraryPath() stringByAppendingPathComponent:@"WeaponX"];
}

NSString *PXProfilesPath(void) {
    return [PXWeaponXBasePath() stringByAppendingPathComponent:@"Profiles"];
}

NSString *PXCurrentProfileInfoPath(void) {
    return [PXProfilesPath() stringByAppendingPathComponent:@"current_profile_info.plist"];
}

NSString *PXLegacyActiveProfileInfoPath(void) {
    return [PXWeaponXBasePath() stringByAppendingPathComponent:@"active_profile_info.plist"];
}

NSString *PXProjectXSettingsPath(void) {
    return [PXPreferencesPath() stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
}

NSString *PXGlobalScopePath(void) {
    return [PXPreferencesPath() stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
}

NSString *PXSecuritySettingsPath(void) {
    return [PXPreferencesPath() stringByAppendingPathComponent:@"com.weaponx.securitySettings.plist"];
}

void PXPostSettingsChangedNotification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.hydra.projectx.settings.changed"),
                                         NULL,
                                         NULL,
                                         true);
}
