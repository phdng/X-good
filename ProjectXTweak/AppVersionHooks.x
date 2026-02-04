// AppVersionHooks.x

#import <Foundation/Foundation.h>

#import "AppVersionHooks.h"

static NSString *const kSecuritySettingsPlist1 = @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
static NSString *const kSecuritySettingsPlist2 = @"/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";

static NSString *const kVersionSpoofPlist1 = @"/var/mobile/Library/Preferences/com.hydra.projectx.version_spoof.plist";
static NSString *const kVersionSpoofPlist2 = @"/private/var/mobile/Library/Preferences/com.hydra.projectx.version_spoof.plist";

static NSString *const kProfilesBase1 = @"/var/mobile/Library/WeaponX/Profiles";
static NSString *const kProfilesBase2 = @"/private/var/mobile/Library/WeaponX/Profiles";

static NSDictionary *gCachedVersionSpoofPlist = nil;
static NSDate *gCachedVersionSpoofMTime = nil;
static NSString *gCachedVersionSpoofPath = nil;

static NSMutableDictionary<NSString *, NSDictionary *> *gCachedProfileVersionPlists = nil;
static NSMutableDictionary<NSString *, NSDate *> *gCachedProfileVersionMTime = nil;

static NSDate *PXFileMTime(NSString *path) {
    if (!path.length) return nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [attrs isKindOfClass:[NSDictionary class]] ? attrs[NSFileModificationDate] : nil;
}

static NSDictionary *PXReadPlist(NSString *path) {
    if (!path.length) return nil;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

static NSString *PXResolveExistingPath(NSArray<NSString *> *candidates) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in candidates) {
        if (p.length && [fm fileExistsAtPath:p]) {
            return p;
        }
    }
    return candidates.firstObject;
}

BOOL PXAppVersionSpoofMasterEnabled(void) {
    NSDictionary *s = PXReadPlist(PXResolveExistingPath(@[kSecuritySettingsPlist1, kSecuritySettingsPlist2]));
    return [s[@"appVersionSpoofingEnabled"] boolValue];
}

static NSDictionary *PXLoadVersionSpoofPlistCached(void) {
    NSString *path = PXResolveExistingPath(@[kVersionSpoofPlist1, kVersionSpoofPlist2]);
    NSDate *mtime = PXFileMTime(path);

    if (gCachedVersionSpoofPlist && gCachedVersionSpoofMTime && [path isEqualToString:gCachedVersionSpoofPath]) {
        if ((!mtime && !gCachedVersionSpoofMTime) || (mtime && [mtime isEqualToDate:gCachedVersionSpoofMTime])) {
            return gCachedVersionSpoofPlist;
        }
    }

    NSDictionary *d = PXReadPlist(path);
    gCachedVersionSpoofPlist = d;
    gCachedVersionSpoofMTime = mtime;
    gCachedVersionSpoofPath = path;
    return d;
}

static NSString *PXReadActiveProfileId(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *bases = @[kProfilesBase1, kProfilesBase2];
    for (NSString *base in bases) {
        if (![fm fileExistsAtPath:base]) continue;
        NSString *p = [base stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:p];
        NSString *pid = [info[@"ProfileId"] isKindOfClass:[NSString class]] ? info[@"ProfileId"] : nil;
        if (pid.length) return pid;
    }

    // Legacy file (outside Profiles directory)
    NSDictionary *legacy1 = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/WeaponX/active_profile_info.plist"];
    NSString *pid2 = [legacy1[@"ProfileId"] isKindOfClass:[NSString class]] ? legacy1[@"ProfileId"] : nil;
    if (pid2.length) return pid2;

    NSDictionary *legacy2 = [NSDictionary dictionaryWithContentsOfFile:@"/private/var/mobile/Library/WeaponX/active_profile_info.plist"];
    NSString *pid3 = [legacy2[@"ProfileId"] isKindOfClass:[NSString class]] ? legacy2[@"ProfileId"] : nil;
    return pid3.length ? pid3 : nil;
}

static NSString *PXSafeBundleFilename(NSString *bundleID) {
    if (!bundleID.length) return nil;
    NSString *safe = [bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    return [safe stringByAppendingString:@"_version.plist"];
}

static NSDictionary *PXLoadProfileAppVersionPlist(NSString *bundleID) {
    if (!bundleID.length) return nil;

    if (!gCachedProfileVersionPlists) {
        gCachedProfileVersionPlists = [NSMutableDictionary dictionary];
        gCachedProfileVersionMTime = [NSMutableDictionary dictionary];
    }

    NSString *profileId = PXReadActiveProfileId();
    if (!profileId.length) return nil;

    NSString *fileName = PXSafeBundleFilename(bundleID);
    if (!fileName.length) return nil;

    NSArray *bases = @[kProfilesBase1, kProfilesBase2];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *foundPath = nil;
    for (NSString *base in bases) {
        if (![fm fileExistsAtPath:base]) continue;
        NSString *p = [[base stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"app_versions"];
        p = [p stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:p]) {
            foundPath = p;
            break;
        }
    }
    if (!foundPath.length) return nil;

    NSDate *mtime = PXFileMTime(foundPath);
    NSDictionary *cached = gCachedProfileVersionPlists[foundPath];
    NSDate *cachedMTime = gCachedProfileVersionMTime[foundPath];
    if (cached && cachedMTime && mtime && [cachedMTime isEqualToDate:mtime]) {
        return cached;
    }

    NSDictionary *d = PXReadPlist(foundPath);
    if (d) {
        gCachedProfileVersionPlists[foundPath] = d;
        if (mtime) gCachedProfileVersionMTime[foundPath] = mtime;
    }
    return d;
}

BOOL PXGetSpoofedAppVersionForBundle(NSString *bundleID, NSString **outVersion, NSString **outBuild) {
    if (outVersion) *outVersion = nil;
    if (outBuild) *outBuild = nil;
    if (!bundleID.length) return NO;

    if (!PXAppVersionSpoofMasterEnabled()) {
        return NO;
    }

    NSDictionary *global = PXLoadVersionSpoofPlistCached();
    NSDictionary *spoofedVersions = [global[@"SpoofedVersions"] isKindOfClass:[NSDictionary class]] ? global[@"SpoofedVersions"] : nil;
    NSDictionary *entry = [spoofedVersions[bundleID] isKindOfClass:[NSDictionary class]] ? spoofedVersions[bundleID] : nil;
    BOOL enabled = entry ? [entry[@"spoofingEnabled"] boolValue] : NO;

    NSString *ver = [entry[@"spoofedVersion"] isKindOfClass:[NSString class]] ? entry[@"spoofedVersion"] : nil;
    NSString *bld = [entry[@"spoofedBuild"] isKindOfClass:[NSString class]] ? entry[@"spoofedBuild"] : nil;

    if (enabled && (!ver.length || !bld.length)) {
        NSDictionary *profilePlist = PXLoadProfileAppVersionPlist(bundleID);
        if (profilePlist) {
            if (!ver.length) {
                ver = [profilePlist[@"spoofedVersion"] isKindOfClass:[NSString class]] ? profilePlist[@"spoofedVersion"] : ver;
            }
            if (!bld.length) {
                bld = [profilePlist[@"spoofedBuild"] isKindOfClass:[NSString class]] ? profilePlist[@"spoofedBuild"] : bld;
            }
        }
    }

    if (!enabled) return NO;
    if (!ver.length && !bld.length) return NO;

    if (outVersion && ver.length) *outVersion = ver;
    if (outBuild && bld.length) *outBuild = bld;
    return YES;
}

void PXAppVersionHooksInvalidateCache(void) {
    gCachedVersionSpoofPlist = nil;
    gCachedVersionSpoofMTime = nil;
    gCachedVersionSpoofPath = nil;
    [gCachedProfileVersionPlists removeAllObjects];
    [gCachedProfileVersionMTime removeAllObjects];
}
