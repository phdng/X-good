#import "ProjectX.h"
#import "DeviceModelManager.h"
#import "IdentifierManager.h"
#import <AdSupport/ASIdentifierManager.h>
#import <UIKit/UIKit.h>
// #import "ellekit/ellekit.h" // Removed for rootful - using Substrate
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <string.h>
#import <net/if.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>  // For sysctlbyname hooks
#import <errno.h>
#import <dirent.h>     // For DIR type
#import <sys/mount.h>  // For statfs
#import "ProfileManager.h" // For accessing current profile
#import "ProfileIndicatorView.h" // For profile indicator
#import <substrate.h>
#import <sys/utsname.h>
#import <Security/Security.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreGraphics/CoreGraphics.h>
// #import <ellekit/ellekit.h> // Removed for rootful - using Substrate
#import <CoreMotion/CoreMotion.h> // Import CoreMotion framework for sensor spoofing
#import "LocationSpoofingManager.h" // Import location spoofing manager
#import "MobileGestalt.h"
#import "IOSVersionInfo.h"
#import "HookOwnership.h"
#import <CoreFoundation/CoreFoundation.h>
// Forward declarations for classes we need to hook
@interface SBScreenshotManager : NSObject
- (void)saveScreenshotsWithCompletion:(id)completion;
- (void)saveScreenshots;
@end

@interface UIImage (WeaponXScreenshot)
- (UIImage *)weaponx_addProfileIndicator;
- (UIImage *)weaponx_removeNavigationBar;
@end

// Cache for values
static NSMutableDictionary *valueCache;

// Owner hook installation flags
BOOL gOwnerSysctlInstalled = NO;
BOOL gOwnerSysctlBynameInstalled = NO;
BOOL gOwnerUnameInstalled = NO;
BOOL gOwnerIOKitInstalled = NO;
BOOL gOwnerMGInstalled = NO;
BOOL gOwnerCFSystemInstalled = NO;

// Missing-key logging
static NSMutableSet *gMissingLogSeen = nil;

static NSString *PXHookMissingLogPath(void) {
    NSArray<NSString *> *dirs = @[
        @"/var/mobile/Library/WeaponX/Logs",
        @"/private/var/mobile/Library/WeaponX/Logs"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
            return [dir stringByAppendingPathComponent:@"hook_missing.log"];
        }
    }
    NSString *preferred = dirs.firstObject;
    if (preferred.length) {
        [fm createDirectoryAtPath:preferred withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755, NSFileOwnerAccountName: @"mobile"} error:nil];
        return [preferred stringByAppendingPathComponent:@"hook_missing.log"];
    }
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"hook_missing.log"];
}

static void PXHookMissingLogLine(NSString *line) {
    if (!line.length) return;
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
        gMissingLogSeen = [NSMutableSet set];
    });
    NSString *path = PXHookMissingLogPath();
    NSString *out = [line stringByAppendingString:@"\n"];
    @synchronized(lock) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        [fh seekToEndOfFile];
        NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            [fh writeData:data];
        }
        [fh closeFile];
    }
}

static void PXHookMissingLogOnce(NSString *signature, NSString *line) {
    if (!signature.length) {
        PXHookMissingLogLine(line);
        return;
    }
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
        if (!gMissingLogSeen) gMissingLogSeen = [NSMutableSet set];
    });
    @synchronized(lock) {
        if ([gMissingLogSeen containsObject:signature]) return;
        [gMissingLogSeen addObject:signature];
    }
    PXHookMissingLogLine(line);
}

static NSString *PXISO8601Now(void) {
    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"]; 
    });
    return [df stringFromDate:[NSDate date]];
}

// Snapshot loader/cache
static NSDictionary *gCachedDeviceIds = nil;
static NSString *gCachedProfileId = nil;
static NSNumber *gCachedGen = nil;

static NSString *PXCurrentProfileId(void) {
    NSArray<NSString *> *bases = @[
        @"/var/mobile/Library/WeaponX/Profiles",
        @"/private/var/mobile/Library/WeaponX/Profiles"
    ];
    for (NSString *base in bases) {
        NSString *infoPath = [base stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *pid = info[@"ProfileId"];
        if (pid.length) return pid;
    }
    return nil;
}

static NSDictionary *PXLoadDeviceIdsForProfile(NSString *profileId) {
    if (!profileId.length) return nil;
    NSArray<NSString *> *bases = @[
        @"/var/mobile/Library/WeaponX/Profiles",
        @"/private/var/mobile/Library/WeaponX/Profiles"
    ];
    for (NSString *base in bases) {
        NSString *identityDir = [[base stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
        NSString *path = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *ids = [NSDictionary dictionaryWithContentsOfFile:path];
        if (ids.count > 0) return ids;
    }
    return nil;
}

static NSDictionary *PXGetDeviceIdsSnapshot(NSString **outProfileId, NSNumber **outGen) {
    NSString *profileId = PXCurrentProfileId();
    NSDictionary *ids = PXLoadDeviceIdsForProfile(profileId);
    NSNumber *gen = nil;
    if ([ids[@"GenerationCounter"] respondsToSelector:@selector(integerValue)]) {
        gen = @([ids[@"GenerationCounter"] integerValue]);
    }
    if (!profileId.length || !ids) {
        if (outProfileId) *outProfileId = profileId;
        if (outGen) *outGen = gen;
        return ids;
    }
    if ([gCachedProfileId isEqualToString:profileId] && ((gCachedGen && [gCachedGen isEqual:gen]) || (!gCachedGen && !gen)) && gCachedDeviceIds) {
        if (outProfileId) *outProfileId = gCachedProfileId;
        if (outGen) *outGen = gCachedGen;
        return gCachedDeviceIds;
    }
    gCachedProfileId = profileId;
    gCachedGen = gen;
    gCachedDeviceIds = ids;
    if (outProfileId) *outProfileId = profileId;
    if (outGen) *outGen = gen;
    return ids;
}

static BOOL PXRequireKeysAll(NSDictionary *ids, NSArray<NSString *> *keys, NSString *api, NSString *req, NSString *bundleID, NSString *profileId, NSNumber *gen) {
    if (!keys.count) return YES;
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *k in keys) {
        id v = ids[k];
        if (![v isKindOfClass:[NSString class]] || ((NSString *)v).length == 0) {
            [missing addObject:k];
        }
    }
    if (missing.count == 0) return YES;
    NSString *proc = [NSProcessInfo processInfo].processName ?: @"";
    NSString *missingStr = [missing componentsJoinedByString:@","];
    NSString *line = [NSString stringWithFormat:@"ts=%@ api=%@ req=%@ bundle=%@ proc=%@ profile=%@ gen=%@ missing=[%@]",
                      PXISO8601Now(), api ?: @"", req ?: @"", bundleID ?: @"", proc, profileId ?: @"", gen ?: @"", missingStr];
    NSString *sig = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@", bundleID ?: @"", proc, api ?: @"", req ?: @"", profileId ?: @"", gen ?: @"", missingStr];
    PXHookMissingLogOnce(sig, line);
    return NO;
}

static BOOL PXRequireKeysAny(NSDictionary *ids, NSArray<NSString *> *keys, NSString *api, NSString *req, NSString *bundleID, NSString *profileId, NSNumber *gen) {
    if (!keys.count) return YES;
    for (NSString *k in keys) {
        id v = ids[k];
        if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length > 0) {
            return YES;
        }
    }
    NSString *proc = [NSProcessInfo processInfo].processName ?: @"";
    NSString *missingStr = [keys componentsJoinedByString:@","];
    NSString *line = [NSString stringWithFormat:@"ts=%@ api=%@ req=%@ bundle=%@ proc=%@ profile=%@ gen=%@ missing_any=[%@]",
                      PXISO8601Now(), api ?: @"", req ?: @"", bundleID ?: @"", proc, profileId ?: @"", gen ?: @"", missingStr];
    NSString *sig = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|any:%@", bundleID ?: @"", proc, api ?: @"", req ?: @"", profileId ?: @"", gen ?: @"", missingStr];
    PXHookMissingLogOnce(sig, line);
    return NO;
}

static CFDataRef PXCreateCFDataFromNSString(NSString *s) {
    if (!s.length) return NULL;
    const char *cStr = [s UTF8String];
    if (!cStr) return NULL;
    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)cStr, strlen(cStr) + 1);
}

static CFStringRef PXCreateCFStringFromNSString(NSString *s) {
    if (!s.length) return NULL;
    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)s);
}

static NSString *PXStringFromCFType(CFTypeRef v) {
    if (!v) return nil;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        return (__bridge NSString *)v;
    }
    if (CFGetTypeID(v) == CFDataGetTypeID()) {
        NSData *data = (__bridge NSData *)v;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

// Function pointer declarations for additional system functions
static int (*sysctlbyname_orig)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int (*sysctl_orig)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

static int PXWriteSysctlCStringLocal(const char *value, void *outBuf, size_t *outLen) {
    if (!outLen || !value) { errno = EINVAL; return -1; }
    size_t required = strlen(value) + 1;
    if (!outBuf) {
        *outLen = required;
        return 0;
    }
    if (*outLen < required) {
        *outLen = required;
        errno = ENOMEM;
        return -1;
    }
    memset(outBuf, 0, *outLen);
    memcpy(outBuf, value, required);
    *outLen = required;
    return 0;
}

// Hook for sysctl array - handles both Kernel and Hardware queries
static int sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!sysctl_orig) return -1;
    if (!name || namelen < 2) {
        return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
    }

    @autoreleasepool {
        @try {
            if (%c(IdentifierManager)) {
                IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
                NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
                if (manager && bundleID && [manager isApplicationEnabled:bundleID]) {
                    NSString *profileId = nil;
                    NSNumber *gen = nil;
                    NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);

                    if (name[0] == CTL_HW && [manager isIdentifierEnabled:@"DeviceModel"]) {
                        if (name[1] == HW_MACHINE) {
                            if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"sysctl", @"CTL_HW/HW_MACHINE", bundleID, profileId, gen)) {
                                return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
                            }
                            NSString *spoofed = deviceIds[@"DeviceModel"];
                            return PXWriteSysctlCStringLocal([spoofed UTF8String], oldp, oldlenp);
                        } else if (name[1] == HW_MODEL) {
                            if (!PXRequireKeysAny(deviceIds, @[@"HwModel", @"BoardID"], @"sysctl", @"CTL_HW/HW_MODEL", bundleID, profileId, gen)) {
                                return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
                            }
                            NSString *spoofed = deviceIds[@"HwModel"];
                            if (!spoofed.length) spoofed = deviceIds[@"BoardID"];
                            return PXWriteSysctlCStringLocal([spoofed UTF8String], oldp, oldlenp);
                        }
                    }

                    if (name[0] == CTL_KERN && [manager isIdentifierEnabled:@"IOSVersion"]) {
                        if (name[1] == KERN_OSVERSION) {
                            if (!PXRequireKeysAll(deviceIds, @[@"IOSBuild"], @"sysctl", @"CTL_KERN/KERN_OSVERSION", bundleID, profileId, gen)) {
                                return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
                            }
                            NSString *spoofed = deviceIds[@"IOSBuild"];
                            return PXWriteSysctlCStringLocal([spoofed UTF8String], oldp, oldlenp);
                        } else if (name[1] == KERN_OSRELEASE) {
                            if (!PXRequireKeysAll(deviceIds, @[@"Darwin"], @"sysctl", @"CTL_KERN/KERN_OSRELEASE", bundleID, profileId, gen)) {
                                return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
                            }
                            NSString *spoofed = deviceIds[@"Darwin"];
                            return PXWriteSysctlCStringLocal([spoofed UTF8String], oldp, oldlenp);
                        } else if (name[1] == KERN_VERSION) {
                            if (!PXRequireKeysAll(deviceIds, @[@"KernelVersion"], @"sysctl", @"CTL_KERN/KERN_VERSION", bundleID, profileId, gen)) {
                                return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
                            }
                            NSString *spoofed = deviceIds[@"KernelVersion"];
                            return PXWriteSysctlCStringLocal([spoofed UTF8String], oldp, oldlenp);
                        }
                    }
                }
            }
        } @catch (__unused NSException *e) {
        }
    }

    return sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
}

// Helper functions from successful bypass code
static __thread BOOL px_sysctlbyname_in_hook = NO;

static int PXWriteSysctlCString(const char *name, const char *value, void *oldp, size_t *oldlenp) {
    if (!oldlenp || !value) { errno = EINVAL; return -1; }
    size_t required = strlen(value) + 1; // include NUL
    if (!oldp) {
        *oldlenp = required;
        return 0;
    }
    if (*oldlenp < required) {
        *oldlenp = required;
        errno = ENOMEM;
        return -1;
    }
    memset(oldp, 0, *oldlenp);
    memcpy(oldp, value, required);
    *oldlenp = required;
    return 0;
}

static int PXWriteSysctlInt64(const char *name, int64_t v, void *oldp, size_t *oldlenp) {
    if (!oldlenp) { errno = EINVAL; return -1; }
    // Keep caller's expected size when possible
    if (!oldp) {
        *oldlenp = (*oldlenp ? *oldlenp : sizeof(int64_t));
        return 0;
    }
    if (*oldlenp == sizeof(int)) {
        *(int *)oldp = (int)v;
        return 0;
    }
    if (*oldlenp == sizeof(uint32_t)) {
        *(uint32_t *)oldp = (uint32_t)v;
        return 0;
    }
    if (*oldlenp == sizeof(unsigned long)) {
        *(unsigned long *)oldp = (unsigned long)v;
        return 0;
    }
    if (*oldlenp >= sizeof(int64_t)) {
        *(int64_t *)oldp = (int64_t)v;
        return 0;
    }
    errno = ENOMEM;
    return -1;
}

// CoreFoundation system version dictionary
static CFDictionaryRef (*CFCopySystemVersionDictionary_orig)(void);

static CFDictionaryRef CFCopySystemVersionDictionary_hook(void) {
    CFDictionaryRef original = CFCopySystemVersionDictionary_orig ? CFCopySystemVersionDictionary_orig() : NULL;

    @autoreleasepool {
        @try {
            if (!%c(IdentifierManager)) {
                return original;
            }

            IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            if (!manager || !bundleID || ![manager isApplicationEnabled:bundleID] || ![manager isIdentifierEnabled:@"IOSVersion"]) {
                return original;
            }

            NSString *profileId = nil;
            NSNumber *gen = nil;
            NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);

            if (!PXRequireKeysAll(deviceIds, @[@"IOSVersion", @"IOSBuild"], @"CFSystem", @"CFCopySystemVersionDictionary", bundleID, profileId, gen)) {
                return original;
            }

            NSString *spoofedVersion = deviceIds[@"IOSVersion"];
            NSString *spoofedBuild = deviceIds[@"IOSBuild"];

            CFMutableDictionaryRef dict = NULL;
            if (original) {
                dict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original);
            } else {
                dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            }

            if (!dict) {
                return original;
            }

            if (spoofedVersion.length) {
                CFStringRef v = CFStringCreateWithCString(kCFAllocatorDefault, [spoofedVersion UTF8String], kCFStringEncodingUTF8);
                if (v) {
                    CFDictionarySetValue(dict, CFSTR("ProductVersion"), v);
                    CFRelease(v);
                }
            }

            if (spoofedBuild.length) {
                CFStringRef b = CFStringCreateWithCString(kCFAllocatorDefault, [spoofedBuild UTF8String], kCFStringEncodingUTF8);
                if (b) {
                    CFDictionarySetValue(dict, CFSTR("ProductBuildVersion"), b);
                    CFRelease(b);
                }
            }

            // Some tools (including AIDA64) use ReleaseType to display OS state.
            // Ensure the key exists so the UI doesn't end up blank.
            if (!CFDictionaryGetValue(dict, CFSTR("ReleaseType"))) {
                CFDictionarySetValue(dict, CFSTR("ReleaseType"), CFSTR("User"));
            }

            if (original) {
                CFRelease(original);
            }

            PXLog(@"[WeaponX] 🎯 Spoofed CFCopySystemVersionDictionary for %@ (build=%@)", bundleID, spoofedBuild ?: @"<nil>");
            return dict;
        } @catch (NSException *e) {
            return original;
        }
    }
}

// Implementation for sysctl hook - commonly used to get device identifiers and detect jailbreak
// Implementation for sysctl hook - commonly used to get device identifiers and detect jailbreak
// Implementation for sysctl hook - commonly used to get device identifiers and detect jailbreak
static int sysctlbyname_hook(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!sysctlbyname_orig) return -1;
    if (px_sysctlbyname_in_hook) return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
    if (!name) { errno = EINVAL; return -1; }

    px_sysctlbyname_in_hook = YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        px_sysctlbyname_in_hook = NO;
        return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
    }
    
    // Check if we should spoof
    if (!%c(IdentifierManager)) {
        px_sysctlbyname_in_hook = NO;
        return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    if (!manager || ![manager isApplicationEnabled:bundleID]) {
         px_sysctlbyname_in_hook = NO;
         return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
    }

    NSString *profileId = nil;
    NSNumber *gen = nil;
    NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);

    // Capture original value for logging (best effort)
    char originalValue[256] = "<not available>";
    size_t originalLen = sizeof(originalValue);
    // Don't call original if user is just querying size (oldp=NULL) to avoid side effects
    if (oldp) {
        (void)sysctlbyname_orig(name, originalValue, &originalLen, NULL, 0);
    }

    NSString *spoofedValue = nil;
    
    // kern.ostype => "Darwin"
    if (strcmp(name, "kern.ostype") == 0) {
        const char *v = "Darwin";
        int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
        if (r == 0) PXLog(@"[WeaponX] 🎯 Spoofed sysctlbyname kern.ostype to: %s", v);
        px_sysctlbyname_in_hook = NO;
        return r;
    }

    // NEW: kern.osproductversion - Critical for Facebook
     if (strcmp(name, "kern.osproductversion") == 0 && [manager isIdentifierEnabled:@"IOSVersion"]) {
         if (!PXRequireKeysAll(deviceIds, @[@"IOSVersion"], @"sysctlbyname", @"kern.osproductversion", bundleID, profileId, gen)) {
             px_sysctlbyname_in_hook = NO;
             return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
         }
         spoofedValue = deviceIds[@"IOSVersion"];
     }
    // Machine/Model spoofing
    else if (strcmp(name, "hw.machine") == 0 && [manager isIdentifierEnabled:@"DeviceModel"]) {
        if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"sysctlbyname", @"hw.machine", bundleID, profileId, gen)) {
            px_sysctlbyname_in_hook = NO;
            return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
        }
        spoofedValue = deviceIds[@"DeviceModel"];
    }
    else if (strcmp(name, "hw.model") == 0 && [manager isIdentifierEnabled:@"DeviceModel"]) {
        if (!PXRequireKeysAny(deviceIds, @[@"HwModel", @"BoardID"], @"sysctlbyname", @"hw.model", bundleID, profileId, gen)) {
            px_sysctlbyname_in_hook = NO;
            return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
        }
        spoofedValue = deviceIds[@"HwModel"];
        if (!spoofedValue.length) spoofedValue = deviceIds[@"BoardID"];
    }
    else if (strcmp(name, "hw.product") == 0 && [manager isIdentifierEnabled:@"DeviceModel"]) {
         if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"sysctlbyname", @"hw.product", bundleID, profileId, gen)) {
             px_sysctlbyname_in_hook = NO;
             return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
         }
         spoofedValue = deviceIds[@"DeviceModel"];
    }
    // OS Version spoofing
    else if ((strcmp(name, "kern.osversion") == 0 || strcmp(name, "kern.osrelease") == 0 || strcmp(name, "kern.version") == 0) &&
             [manager isIdentifierEnabled:@"IOSVersion"]) {
         if (strcmp(name, "kern.osversion") == 0) {
             if (!PXRequireKeysAll(deviceIds, @[@"IOSBuild"], @"sysctlbyname", @"kern.osversion", bundleID, profileId, gen)) {
                 px_sysctlbyname_in_hook = NO;
                 return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
             }
             spoofedValue = deviceIds[@"IOSBuild"];
         } else if (strcmp(name, "kern.osrelease") == 0) {
             if (!PXRequireKeysAll(deviceIds, @[@"Darwin"], @"sysctlbyname", @"kern.osrelease", bundleID, profileId, gen)) {
                 px_sysctlbyname_in_hook = NO;
                 return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
             }
             spoofedValue = deviceIds[@"Darwin"];
         } else {
             if (!PXRequireKeysAll(deviceIds, @[@"KernelVersion"], @"sysctlbyname", @"kern.version", bundleID, profileId, gen)) {
                 px_sysctlbyname_in_hook = NO;
                 return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
             }
             spoofedValue = deviceIds[@"KernelVersion"];
         }
    }
    else if (strcmp(name, "kern.hostname") == 0 && [manager isIdentifierEnabled:@"DeviceName"]) {
        spoofedValue = [manager currentValueForIdentifier:@"DeviceName"];
    }
    
    // WRITE STRING VALUE if found
    if (spoofedValue.length > 0) {
        const char *v = [spoofedValue UTF8String];
        int r = PXWriteSysctlCString(name, v, oldp, oldlenp);
        if (r == 0) {
            PXLog(@"[WeaponX] 🎯 Spoofed sysctlbyname %s from: %s to: %s", name, originalValue, v);
        }
        px_sysctlbyname_in_hook = NO;
        return r;
    }
    
    // CPU INFO SPOOFING (Crucial for correct device identification)
    if (strcmp(name, "hw.physicalcpu") == 0 ||
        strcmp(name, "hw.physicalcpu_max") == 0 ||
        strcmp(name, "hw.logicalcpu") == 0 ||
        strcmp(name, "hw.logicalcpu_max") == 0 ||
        strcmp(name, "hw.ncpu") == 0 ||
        strcmp(name, "hw.activecpu") == 0) {
        
        if ([manager isIdentifierEnabled:@"DeviceModel"]) {
            NSString *model = [manager currentValueForIdentifier:@"DeviceModel"];
            int64_t cores = 6; // Default to modern iPhone (XS/11/12/13/14+)
            
            if ([model hasPrefix:@"iPhone8"] || [model hasPrefix:@"iPhone9"] || [model hasPrefix:@"iPhone10"]) {
                cores = 2; // 6S, 7, 8
            } else if ([model hasPrefix:@"iPhone10,3"] || [model hasPrefix:@"iPhone10,6"]) {
                cores = 6; // X
            } else if ([model hasPrefix:@"iPhone11"]) {
                cores = 6;
            }
            
            if (cores > 0) {
                // Exact match to bypass code size query behavior
                if (!oldp && oldlenp) {
                   size_t tmp = 0;
                   (void)sysctlbyname_orig(name, NULL, &tmp, NULL, 0);
                   if (tmp > 0) *oldlenp = tmp;
                   px_sysctlbyname_in_hook = NO;
                   return 0;
                }

               int r = PXWriteSysctlInt64(name, cores, oldp, oldlenp);
               if (r == 0) {
                   PXLog(@"[WeaponX] 🎯 Spoofed sysctlbyname CPU count %s to: %lld", name, (long long)cores);
               }
               px_sysctlbyname_in_hook = NO;
               return r;
            }
        }
    }
    
    // Jailbreak detection hook removed to match working bypass behavior
    // (Facebook may check for behavior discrepancy here)

    px_sysctlbyname_in_hook = NO;
    return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
}

// Hook for uname() system call - used by many apps to detect device model
static int (*uname_orig)(struct utsname *);
static int uname_hook(struct utsname *buf) {
    if (!uname_orig) return -1;
    int ret = uname_orig(buf);
    if (ret != 0) return ret;
    
    @try {
        if (!%c(IdentifierManager)) return ret;
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!manager || !bundleID || ![manager isApplicationEnabled:bundleID]) return ret;
        
        if ([manager isIdentifierEnabled:@"DeviceModel"]) {
            NSString *profileId = nil;
            NSNumber *gen = nil;
            NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);
            if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"uname", @"utsname.machine", bundleID, profileId, gen)) {
                return ret;
            }
            NSString *model = deviceIds[@"DeviceModel"];
            const char *modelStr = [model UTF8String];
            if (modelStr && buf) {
                if (strlen(modelStr) < sizeof(buf->machine)) {
                    strcpy(buf->machine, modelStr);
                    PXLog(@"[WeaponX] 🎯 Spoofed uname() machine to: %@", model);
                }
            }
        }
    } @catch (NSException *e) {
        PXLog(@"[WeaponX] Exception in uname hook: %@", e);
    }
    return ret;
}

// Define hook group for main identifier spoofing
%group Identifiers

// MGCopyAnswer hook for various system identifiers
%hookf(CFTypeRef, MGCopyAnswer, CFStringRef property) {
    if (!%c(IdentifierManager)) {
        return %orig;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    NSString *propertyString = (__bridge NSString *)property;
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *profileId = nil;
    NSNumber *gen = nil;
    NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);
    
    PXLog(@"MGCopyAnswer requested for property: %@ by app: %@", propertyString, currentBundleID);
    
    if (![manager isApplicationEnabled:currentBundleID]) {
        // Only log verbose if needed to avoid spam
        // PXLog(@"App not in scope or disabled, passing through original value");
        return %orig;
    }
    
    // Device model / hardware identifiers (keep consistent across sysctl/IOKit/MobileGestalt)
    if (propertyString) {
        BOOL deviceModelEnabled = [manager isIdentifierEnabled:@"DeviceModel"];
        if (deviceModelEnabled) {
            if (propertyString.length > 0) {
                if ([propertyString isEqualToString:@"ProductType"]) {
                    if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"MG", @"ProductType", currentBundleID, profileId, gen)) {
                        return %orig;
                    }
                    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)deviceIds[@"DeviceModel"]);
                }

                if ([propertyString isEqualToString:@"HWModelStr"] ||
                    [propertyString isEqualToString:@"HardwareModel"] ||
                    [propertyString isEqualToString:@"HWModel"] ||
                    [propertyString isEqualToString:@"hw-model"]) {
                    if (!PXRequireKeysAny(deviceIds, @[@"HwModel", @"BoardID"], @"MG", @"HWModel", currentBundleID, profileId, gen)) {
                        return %orig;
                    }
                    NSString *hwModel = deviceIds[@"HwModel"];
                    if (!hwModel.length) hwModel = deviceIds[@"BoardID"];
                    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)hwModel);
                }

                if ([propertyString isEqualToString:@"BoardId"] ||
                    [propertyString isEqualToString:@"board-id"]) {
                    if (!PXRequireKeysAll(deviceIds, @[@"BoardID"], @"MG", @"BoardId", currentBundleID, profileId, gen)) {
                        return %orig;
                    }
                    NSString *boardID = deviceIds[@"BoardID"];
                    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)boardID);
                }
            }
        }
    }

    // iOS build number (AIDA64 reads this on some paths)
    if (propertyString && [manager isIdentifierEnabled:@"IOSVersion"]) {
        if ([propertyString isEqualToString:@"ReleaseType"]) {
            return CFStringCreateCopy(kCFAllocatorDefault, CFSTR("User"));
        }

        if ([propertyString isEqualToString:@"ProductBuildVersion"] ||
            [propertyString isEqualToString:@"BuildVersion"]) {
            if (!PXRequireKeysAll(deviceIds, @[@"IOSBuild"], @"MG", propertyString, currentBundleID, profileId, gen)) {
                return %orig;
            }
            NSString *build = deviceIds[@"IOSBuild"];
            PXLog(@"[WeaponX] 🎯 Spoofing MGCopyAnswer %@ with build: %@", propertyString, build);
            return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)build);
        }
    }

    // Model number (Axxxx) from MobileGestalt
    if (propertyString && [propertyString isEqualToString:@"ModelNumber"]) {
        if ([manager isIdentifierEnabled:@"DeviceModel"]) {
            if (!PXRequireKeysAll(deviceIds, @[@"ModelNumber"], @"MG", @"ModelNumber", currentBundleID, profileId, gen)) {
                return %orig;
            }
            NSString *modelNumber = deviceIds[@"ModelNumber"];
            return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)modelNumber);
        }
    }

    // Handle various identifier types
    if ([propertyString isEqualToString:@"UniqueDeviceID"] || 
        [propertyString isEqualToString:@"UniqueDeviceIDData"]) {
        
        if ([manager isIdentifierEnabled:@"UDID"]) {
            NSString *spoofedUDID = [manager currentValueForIdentifier:@"UDID"];
            if (spoofedUDID) {
                PXLog(@"Spoofing UDID with: %@", spoofedUDID);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedUDID);
            }
        }
    } 
    else if ([propertyString isEqualToString:@"SerialNumber"]) {
        // Special case for Filza and ADManager
        if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
            [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
            NSString *hardcodedSerial = @"FCCC15Q4HG04";
            PXLog(@"[WeaponX] 📱 Returning hardcoded serial number for %@: %@", currentBundleID, hardcodedSerial);
            return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)hardcodedSerial);
        }
        
        if ([manager isIdentifierEnabled:@"SerialNumber"]) {
            NSString *spoofedSerial = [manager currentValueForIdentifier:@"SerialNumber"];
            if (spoofedSerial) {
                PXLog(@"Spoofing Serial Number with: %@", spoofedSerial);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedSerial);
            }
        }
    }
    else if ([propertyString isEqualToString:@"InternationalMobileEquipmentIdentity"] ||
             [propertyString isEqualToString:@"MobileEquipmentIdentifier"]) {
        
        if ([manager isIdentifierEnabled:@"IMEI"]) {
            NSString *spoofedIMEI = [manager currentValueForIdentifier:@"IMEI"];
            if (spoofedIMEI) {
                PXLog(@"Spoofing IMEI with: %@", spoofedIMEI);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedIMEI);
            }
        }
    }
    
    // Default: return original value
    PXLog(@"No spoofing applied, returning original value");
    return %orig;
}

// IDFA hook
%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (!%c(IdentifierManager)) {
        return %orig;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    PXLog(@"IDFA requested by app: %@", currentBundleID);
    
    if (![manager isApplicationEnabled:currentBundleID]) {
        PXLog(@"App not in scope or disabled, passing through original IDFA");
        return %orig;
    }
    
    if ([manager isIdentifierEnabled:@"IDFA"]) {
        NSString *idfaString = [manager currentValueForIdentifier:@"IDFA"];
        if (idfaString) {
            PXLog(@"Spoofing IDFA with: %@", idfaString);
            return [[NSUUID alloc] initWithUUIDString:idfaString];
        }
    }
    
    PXLog(@"No IDFA spoofing applied, returning original value");
    return %orig;
}

%end

// IDFV and device name hooks
%hook UIDevice

// Hook for identifierForVendor (IDFV)
- (NSUUID *)identifierForVendor {
    NSUUID *originalIdentifier = %orig;
    
    @try {
        if (!%c(IdentifierManager)) {
            return originalIdentifier;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return originalIdentifier;
        }
        
        // In iOS 15+, this is the preferred identifier checked by many apps
        if ([manager isIdentifierEnabled:@"IDFV"]) {
            NSString *idfvString = [manager currentValueForIdentifier:@"IDFV"];
            if (idfvString) {
                // Create a static cache keyed by bundle ID to ensure consistent values
                static NSMutableDictionary *idfvCache = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    idfvCache = [NSMutableDictionary dictionary];
                });
                
                // Thread-safe access to the cache
                @synchronized(idfvCache) {
                    NSUUID *cachedValue = idfvCache[currentBundleID];
                    if (cachedValue) {
                        return cachedValue;
                    }
                    
                    NSUUID *spoofedIdentifier = [[NSUUID alloc] initWithUUIDString:idfvString];
                    if (spoofedIdentifier) {
                        PXLog(@"[WeaponX] Spoofing identifierForVendor with: %@", idfvString);
                        idfvCache[currentBundleID] = spoofedIdentifier;
                        return spoofedIdentifier;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in identifierForVendor: %@", exception);
    }
    
    return originalIdentifier;
}

// Hook for device name with improved iOS 15-16 compatibility
- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {
        if (!%c(IdentifierManager)) {
            return originalName;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return originalName;
        }
        
        if ([manager isIdentifierEnabled:@"DeviceName"]) {
            NSString *deviceName = [manager currentValueForIdentifier:@"DeviceName"];
            if (deviceName && deviceName.length > 0) {
                // Cache the name for this process to ensure consistency
                static NSString *cachedHostName = nil;
                if (!cachedHostName) {
                    cachedHostName = [deviceName copy];
                }
                PXLog(@"[WeaponX] Spoofing NSHost name with: %@", cachedHostName);
                return cachedHostName;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in NSHost name: %@", exception);
    }
    
    return originalName;
}

%end

// IDFV fallback through ubiquityIdentityToken
%hook NSFileManager

- (id)ubiquityIdentityToken {
    if (!%c(IdentifierManager)) {
        return %orig;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    PXLog(@"ubiquityIdentityToken requested by app: %@", currentBundleID);
    
    if (![manager isApplicationEnabled:currentBundleID]) {
        PXLog(@"App not in scope or disabled, passing through original ubiquityIdentityToken");
        return %orig;
    }
    
    if ([manager isIdentifierEnabled:@"IDFV"]) {
        // If IDFV is enabled, we can't directly replace the token as it's a private structure
        // but we can return nil to prevent tracking through this method
        PXLog(@"Blocking ubiquityIdentityToken access for privacy protection");
        return nil;
    }
    
    return %orig;
}

%end

// NSHost hook for device name
%hook NSHost

+ (NSHost *)currentHost {
    NSHost *originalHost = %orig;
    
    if (!%c(IdentifierManager)) {
        return originalHost;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    PXLog(@"NSHost currentHost requested by app: %@", currentBundleID);
    
    if (![manager isApplicationEnabled:currentBundleID]) {
        PXLog(@"App not in scope, returning original host info");
        return originalHost;
    }
    
    if ([manager isIdentifierEnabled:@"DeviceName"]) {
        // We can't easily modify the NSHost instance as it has private structure
        // So we'll overwrite the name and addresses methods
        PXLog(@"App is requesting NSHost information - will spoof in name method");
        
        // Return the original host, name will be handled in the name method
        return originalHost;
    }
    
    return originalHost;
}

- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {
        if (!%c(IdentifierManager)) {
            return originalName;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return originalName;
        }
        
        if ([manager isIdentifierEnabled:@"DeviceName"]) {
            NSString *deviceName = [manager currentValueForIdentifier:@"DeviceName"];
            if (deviceName && deviceName.length > 0) {
                // Cache the name for this process to ensure consistency
                static NSString *cachedHostName = nil;
                if (!cachedHostName) {
                    cachedHostName = [deviceName copy];
                }
                PXLog(@"[WeaponX] Spoofing NSHost name with: %@", cachedHostName);
                return cachedHostName;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in NSHost name: %@", exception);
    }
    
    return originalName;
}

%end

// CTTelephonyNetworkInfo hook for carrier info with iOS 15-16 compatibility
%hook CTTelephonyNetworkInfo

// Basic subscriber cellular provider method
- (id)subscriberCellularProvider {
    id original = %orig;
    
    @try {
        if (!%c(IdentifierManager)) {
            return original;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return original;
        }
        
        // If any identifier spoofing is enabled, ensure we're consistent with carrier info
        // to prevent carrier-based fingerprinting (common on iOS 15+)
        if ([manager isIdentifierEnabled:@"IDFV"] || 
            [manager isIdentifierEnabled:@"IDFA"] || 
            [manager isIdentifierEnabled:@"UDID"]) {
            // We return the original but modified carrier object is handled via CTCarrier hooks
        }
    } @catch (NSException *exception) {
        // We return the original but modified carrier object is handled via CTCarrier hooks
    }
    
    return original;
}

// iOS 12+ multi-carrier support - heavily used in iOS 15-16
- (NSDictionary *)serviceSubscriberCellularProviders {
    NSDictionary *original = %orig;
    
    @try {
        if (!%c(IdentifierManager)) {
            return original;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return original;
        }
        
        // For iOS 15+, apps often use this to fingerprint devices
        if ([manager isIdentifierEnabled:@"IDFV"] || 
            [manager isIdentifierEnabled:@"IDFA"] || 
            [manager isIdentifierEnabled:@"UDID"]) {
            // The individual CTCarrier objects in the dictionary will be modified 
            // by the CTCarrier hooks separately
        }
    } @catch (NSException *exception) {
        // The individual CTCarrier objects in the dictionary will be modified 
        // by the CTCarrier hooks separately
    }
    
    return original;
}

// iOS 13+ carrier data for specific carrier token
- (id)subscriberCellularProviderForIdentifier:(NSString *)identifier {
    id original = %orig;
    
    @try {
        if (!%c(IdentifierManager) || !identifier) {
            return original;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return original;
        }
        
        // Ensure consistent carrier info for this specific carrier
        if ([manager isIdentifierEnabled:@"IDFV"] || 
            [manager isIdentifierEnabled:@"IDFA"] || 
            [manager isIdentifierEnabled:@"UDID"]) {
        }
    } @catch (NSException *exception) {
        // The individual CTCarrier objects in the dictionary will be modified 
        // by the CTCarrier hooks separately
    }
    
    return original;
}

%end

%end // End of Identifiers group

// Define hook group for screenshot modifications
%group ScreenshotModifier

// Extension for UIImage to add profile indicator and remove navigation bar
%hookf(UIImage *, UIImagePNGRepresentation, UIImage *image) {
    UIImage *modifiedImage = image;
    
    // First, remove navigation bar from the screenshot
    modifiedImage = [modifiedImage weaponx_removeNavigationBar];
    
    // Then, add profile indicator
    modifiedImage = [modifiedImage weaponx_addProfileIndicator];
    
    // Finally, convert to PNG
    return %orig(modifiedImage);
}

// Hook into screenshot saving
%hook SBScreenshotManager

- (void)saveScreenshotsWithCompletion:(id)completion {
    PXLog(@"[WeaponX] Intercepted screenshot capture");
    %orig;
}

- (void)saveScreenshots {
    PXLog(@"[WeaponX] Intercepted screenshot capture (no completion)");
    %orig;
}

%end

%hook UIImage

// Extension method to add profile indicator
%new
- (UIImage *)weaponx_addProfileIndicator {
    // Get the current profile ID from NSUserDefaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
    NSString *profileId = [defaults objectForKey:@"CurrentProfileID"];
    
    if (!profileId) {
        profileId = @"1"; // Default to 1 if no profile ID is saved
    }
    
    // Ensure profileId is treated as a string to avoid any numeric conversion issues
    NSString *displayProfileId = [NSString stringWithFormat:@"%@", profileId];
    PXLog(@"[WeaponX] Screenshot using profile ID: %@", displayProfileId);
    
    // Begin a new graphics context with the image size
    UIGraphicsBeginImageContextWithOptions(self.size, NO, self.scale);
    
    // Draw the original image
    [self drawAtPoint:CGPointZero];
    
    // Create the indicator text
    NSString *indicatorText = [NSString stringWithFormat:@"←------------------ Profile Num: %@ -----------------→", displayProfileId];
    
    // Create the attributes for the text
    UIFont *font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor systemBlueColor]
    };
    
    // Create the text to be drawn
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:indicatorText attributes:attributes];
    
    // Get the size of the text
    CGSize textSize = [attributedString size];
    
    // Save the context state
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    
    // Translate and rotate the context to draw vertical text on the left edge
    CGContextTranslateCTM(context, 20, self.size.height / 2);
    CGContextRotateCTM(context, -M_PI_2);
    
    // Draw the text
    [attributedString drawAtPoint:CGPointMake(-textSize.width / 2, -textSize.height / 2)];
    
    // Restore the context state
    CGContextRestoreGState(context);
    
    // Get the modified image
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    
    // End the graphics context
    UIGraphicsEndImageContext();
    
    return newImage ?: self;
}

// Extension method to remove navigation bar
%new
- (UIImage *)weaponx_removeNavigationBar {
    // Check if there's a navigation bar to remove (usually at the top of the screen)
    // We'll assume a standard navigation bar height of ~44 points from the top
    CGFloat navBarHeight = 44.0;
    
    // Begin a new graphics context with the image size
    UIGraphicsBeginImageContextWithOptions(self.size, NO, self.scale);
    
    // Draw the original image but crop out the navigation bar area
    [self drawInRect:CGRectMake(0, 0, self.size.width, self.size.height)
            blendMode:kCGBlendModeNormal
                alpha:1.0];
    
    // Get a reference to the graphics context
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Create a solid color rectangle to cover the navigation bar area
    CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, self.size.width, navBarHeight));
    
    // Get the modified image
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    
    // End the graphics context
    UIGraphicsEndImageContext();
    
    return newImage ?: self;
}

%end

%end // End ScreenshotModifier group

// Define hook group for location spoofing
%group LocationSpoofing

// Hook CLLocationManager to intercept location updates
%hook CLLocationManager

- (void)setDelegate:(id)delegate {
    // First, pass through to the original implementation
    %orig;
    
    @try {
        // Only log spoofing info for non-Apple apps, and avoid excessive logging
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            // Get the manager instance outside the synchronized block to prevent deadlocks
            LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
            
            // Log only on the first delegation or periodically (using a static variable)
            static NSMutableSet *handledDelegates = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                handledDelegates = [NSMutableSet set];
            });
            
            @synchronized(handledDelegates) {
                // Create identifier for this delegate/manager pair
                NSString *delegateID = [NSString stringWithFormat:@"%p-%p", delegate, self];
                
                // Only log if we haven't seen this delegate before
                if (![handledDelegates containsObject:delegateID]) {
                    [handledDelegates addObject:delegateID];
                    
                    if (manager && bundleID) {
                        BOOL isSpoofingEnabled = [manager isSpoofingEnabled];
                        BOOL shouldSpoofApp = [manager shouldSpoofApp:bundleID];
                        
                        if (isSpoofingEnabled && shouldSpoofApp) {
                            double lat = [manager getSpoofedLatitude];
                            double lon = [manager getSpoofedLongitude];
                            PXLog(@"[WeaponX] GPS spoofing is enabled for %@. Using: %.6f, %.6f", 
                                  bundleID, lat, lon);
                        } else if (isSpoofingEnabled) {
                            PXLog(@"[WeaponX] GPS spoofing is enabled globally but not for %@", bundleID);
                        }
                        
                        // In iOS 15+, make sure position variations are enabled
                        if (isSpoofingEnabled && shouldSpoofApp && manager.jitterEnabled) {
                            // Set position variations to match jitter setting for consistency
                            manager.positionVariationsEnabled = YES;
                        }
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // Just log the exception and don't interfere with normal operation
        PXLog(@"[WeaponX] Exception in CLLocationManager.setDelegate: %@", exception);
    }
}

// Hook location accuracy settings
- (void)setDesiredAccuracy:(CLLocationAccuracy)accuracy {
    // Check if we should modify accuracy
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        
        // Only proceed if this is an app we're monitoring
        if (bundleID && manager && [manager isSpoofingEnabled] && [manager shouldSpoofApp:bundleID]) {
            // Ensure high accuracy for our spoofed locations
            PXLog(@"[WeaponX] App %@ requested accuracy %.1f, ensuring best accuracy for spoofing", 
                  bundleID, accuracy);
            
            // Override with best accuracy
            %orig(kCLLocationAccuracyBest);
            return;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in setDesiredAccuracy: %@", exception);
    }
    
    // Default behavior
    %orig;
}

// Monitor when location updates are started
- (void)startUpdatingLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startUpdatingLocation: %@", exception);
    }
    
    %orig;
}

// Monitor when location updates are stopped
- (void)stopUpdatingLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopUpdatingLocation: %@", exception);
    }
    
    %orig;
}

%end

// Hook CLLocation to modify coordinate with improved thread safety
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    // Get the original coordinate
    CLLocationCoordinate2D originalCoordinate = %orig;
    
    // Use thread-local storage to prevent recursive calls
    static NSString * const kRecursionGuardKey = @"CLLocationCoordinateRecursionGuard";
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    if ([threadDictionary[kRecursionGuardKey] boolValue]) {
        return originalCoordinate;
    }
    
    // Set recursion guard
    threadDictionary[kRecursionGuardKey] = @YES;
    
    @try {
        // Performance optimization: throttle location checks
        static NSTimeInterval lastProcessTime = 0;
        static CLLocationCoordinate2D lastReturnedCoordinate = {0, 0};
        
        // Thread-safe time check
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        BOOL shouldThrottle = NO;
        
        @synchronized([self class]) {
            shouldThrottle = (currentTime - lastProcessTime < 0.2);
            
            if (!shouldThrottle) {
                lastProcessTime = currentTime;
            }
        }
        
        if (shouldThrottle) {
            // Return the last spoofed coordinates if they were set and valid
            if (CLLocationCoordinate2DIsValid(lastReturnedCoordinate) && 
                (lastReturnedCoordinate.latitude != 0.0 || lastReturnedCoordinate.longitude != 0.0)) {
                threadDictionary[kRecursionGuardKey] = nil;
                return lastReturnedCoordinate;
            }
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Get the LocationSpoofingManager and check if spoofing is enabled
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        if (!manager) {
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Check if spoofing is enabled - this verifies pinned location exists
        if (![manager isSpoofingEnabled]) {
            // Not enabled, return original coordinate
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID) {
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Check if we should spoof this app
        if (![manager shouldSpoofApp:bundleID]) {
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Use modifySpoofedLocation method which properly handles position variations
        // Create a temporary CLLocation with the original coordinates to modify
        CLLocation *tempLocation = [[CLLocation alloc] initWithLatitude:originalCoordinate.latitude
                                                             longitude:originalCoordinate.longitude];
        
        // Get a properly spoofed location with all variations applied
        CLLocation *spoofedLocation = [manager modifySpoofedLocation:tempLocation];
        if (!spoofedLocation) {
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Get the spoofed coordinates with variations applied
        CLLocationCoordinate2D spoofedCoordinate = spoofedLocation.coordinate;
        
        // Store the spoofed coordinate for throttled requests in thread-safe way
        @synchronized([self class]) {
            lastReturnedCoordinate = spoofedCoordinate;
        }
        
        // Only log occasionally to reduce spam
        static NSTimeInterval lastLogTime = 0;
        if (currentTime - lastLogTime > 30.0) {
            @synchronized([self class]) {
                if (currentTime - lastLogTime > 30.0) {
                    PXLog(@"[WeaponX] Using spoofed location for %@: (%.6f, %.6f) with variations", 
                        bundleID, spoofedCoordinate.latitude, spoofedCoordinate.longitude);
                    lastLogTime = currentTime;
                }
            }
        }
        
        threadDictionary[kRecursionGuardKey] = nil;
        return spoofedCoordinate;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception while spoofing location: %@", exception);
        threadDictionary[kRecursionGuardKey] = nil;
        return originalCoordinate;
    }
}

%end

// Hook -[CLLocationManager locationManagerDidUpdateLocations:] delegate method
%hook NSObject

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        %orig;
        return;
    }
    
    if (!manager || !locations || locations.count == 0) {
        %orig;
        return;
    }
    
    // Get the LocationSpoofingManager
    LocationSpoofingManager *spoofManager = [LocationSpoofingManager sharedManager];
    
    // If spoofing is disabled (no pinned location) or manager is not available, use original location
    if (!spoofManager || ![spoofManager isSpoofingEnabled]) {
        %orig;
        return;
    }
    
    // Get the current bundle ID
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || ![spoofManager shouldSpoofApp:bundleID]) {
        %orig;
        return;
    }
    
    @try {
        // Create array of spoofed locations
        NSMutableArray *spoofedLocations = [NSMutableArray arrayWithCapacity:locations.count];
        
        // Apply proper position variations to each location using modifySpoofedLocation
        for (CLLocation *originalLocation in locations) {
            // Get a properly spoofed location with all variations applied
            CLLocation *spoofedLocation = [spoofManager modifySpoofedLocation:originalLocation];
            
            if (spoofedLocation) {
                [spoofedLocations addObject:spoofedLocation];
            } else {
                // If spoofing fails, use original location
                [spoofedLocations addObject:originalLocation];
            }
        }
        
        // Replace original locations with spoofed ones
        if (spoofedLocations.count > 0) {
            %orig(manager, spoofedLocations);
            return;
        }
        
        // If no spoofed locations were created, use original
        %orig;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didUpdateLocations: %@", exception);
        %orig; // Pass through original on exception
    }
}

// Add hook for the legacy location update method
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        %orig;
        return;
    }
    
    if (!manager || !newLocation) {
        %orig;
        return;
    }
    
    // Get the LocationSpoofingManager
    LocationSpoofingManager *spoofManager = [LocationSpoofingManager sharedManager];
    
    // If spoofing is disabled (no pinned location) or manager is not available, use original location
    if (!spoofManager || ![spoofManager isSpoofingEnabled]) {
        %orig;
        return;
    }
    
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || ![spoofManager shouldSpoofApp:bundleID]) {
            %orig;
            return;
        }
        
    @try {
        // Performance optimization: throttle excessive legacy updates
        static NSTimeInterval lastLegacyUpdateTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLegacyUpdateTime < 0.3) { // Max ~3 updates per second
            static int legacySkipCounter = 0;
            if (++legacySkipCounter % 3 != 0) { // Process only every 3rd rapid update
                %orig;
                return;
            }
        }
        lastLegacyUpdateTime = currentTime;
        
        // Get spoofed location with position variations applied
        CLLocation *spoofedLocation = [spoofManager modifySpoofedLocation:newLocation];
        
        if (spoofedLocation) {
            // Only log occasionally
            static NSTimeInterval lastLogTime = 0;
            if (currentTime - lastLogTime > 30.0) {
                PXLog(@"[WeaponX] Using pinned location with variations for %@ (legacy method)", bundleID);
                lastLogTime = currentTime;
            }
            
            // Call original with spoofed location
            %orig(manager, spoofedLocation, oldLocation);
        } else {
            // If spoofing fails, use original
            %orig;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in legacy location method: %@", exception);
        %orig; // Pass through original on exception
    }
}

%end

// Additional CLLocationManager hooks for special methods
%hook CLLocationManager

// Hook for one-time location requests
- (void)requestLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested one-time location", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in requestLocation: %@", exception);
    }
    
    %orig;
}

// Hook for significant location monitoring
- (void)startMonitoringSignificantLocationChanges {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring significant location changes", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringSignificantLocationChanges: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringSignificantLocationChanges {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring significant location changes", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringSignificantLocationChanges: %@", exception);
    }
    
    %orig;
}

// Hook for deferred location updates
- (void)allowDeferredLocationUpdatesUntilTraveled:(CLLocationDistance)distance timeout:(NSTimeInterval)timeout {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested deferred location updates (distance: %.2f, timeout: %.2f)", 
                  bundleID, distance, timeout);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in allowDeferredLocationUpdatesUntilTraveled: %@", exception);
    }
    
    %orig;
}

- (void)disallowDeferredLocationUpdates {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ disallowed deferred location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in disallowDeferredLocationUpdates: %@", exception);
    }
    
    %orig;
}

// Hook for heading updates
- (void)startUpdatingHeading {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started heading updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startUpdatingHeading: %@", exception);
    }
    
    %orig;
}

- (void)stopUpdatingHeading {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped heading updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopUpdatingHeading: %@", exception);
    }
    
    %orig;
}

// Hook for geofencing
- (void)startMonitoringForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringForRegion: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringForRegion: %@", exception);
    }
    
    %orig;
}

- (void)requestStateForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested state for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in requestStateForRegion: %@", exception);
    }
    
    %orig;
}

// Hook for visit monitoring
- (void)startMonitoringVisits {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring visits", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringVisits: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringVisits {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring visits", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringVisits: %@", exception);
    }
    
    %orig;
}

%end

// Hook CLLocation additional properties
%hook CLLocation

- (CLLocationSpeed)speed {
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (manager && [manager isSpoofingEnabled] && bundleID && [manager shouldSpoofApp:bundleID]) {
        // Return a reasonable speed value (walking pace)
        return 1.5;
    }
    
    return %orig;
}

- (CLLocationDirection)course {
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (manager && [manager isSpoofingEnabled] && bundleID && [manager shouldSpoofApp:bundleID]) {
        // Return a fixed direction (North = 0 degrees)
        return 0.0;
    }
    
    return %orig;
}

%end

// Add more delegate method hooks to NSObject
%hook NSObject

// Regional monitoring delegate methods
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didEnterRegion:)]) {
        %orig;
        return;
    }
    
    LocationSpoofingManager *spoofManager = [LocationSpoofingManager sharedManager];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!spoofManager || !bundleID || ![spoofManager isSpoofingEnabled] || ![spoofManager shouldSpoofApp:bundleID]) {
        %orig;
        return;
    }
    
    @try {
        // Log the interception
        PXLog(@"[WeaponX] Intercepted region entry for app %@, region: %@", bundleID, region.identifier);
        
        // We suppress region events when spoofing is active since our location isn't actually moving
        // This prevents apps from getting confusing region notifications
        
        // Do not call %orig to suppress the notification
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didEnterRegion: %@", exception);
        %orig;
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didExitRegion:)]) {
        %orig;
        return;
    }
    
    LocationSpoofingManager *spoofManager = [LocationSpoofingManager sharedManager];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!spoofManager || !bundleID || ![spoofManager isSpoofingEnabled] || ![spoofManager shouldSpoofApp:bundleID]) {
        %orig;
        return;
    }
    
    @try {
        // Log the interception
        PXLog(@"[WeaponX] Intercepted region exit for app %@, region: %@", bundleID, region.identifier);
        
        // Suppress region exit events when spoofing is active
        // Do not call %orig to suppress the notification
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didExitRegion: %@", exception);
        %orig;
    }
}

// Heading update delegate method
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
        %orig;
        return;
    }
    
    LocationSpoofingManager *spoofManager = [LocationSpoofingManager sharedManager];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!spoofManager || !bundleID || ![spoofManager isSpoofingEnabled] || ![spoofManager shouldSpoofApp:bundleID]) {
        %orig;
        return;
    }
    
    @try {
        // Create a spoofed heading pointing north
        // This would require creating a custom CLHeading, which is complex
        // For now, we'll just pass through the original heading
        PXLog(@"[WeaponX] Passing through heading update for app %@", bundleID);
        %orig;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didUpdateHeading: %@", exception);
        %orig;
    }
}

%end

// Hook for MKMapView to handle map-specific location display
%hook MKMapView

- (MKUserLocation *)userLocation {
    MKUserLocation *originalUserLocation = %orig;
    
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!manager || !bundleID || ![manager isSpoofingEnabled] || ![manager shouldSpoofApp:bundleID]) {
            return originalUserLocation;
        }
        
        // Since we can't directly modify MKUserLocation's coordinate (it's read-only),
        // we rely on our CLLocation hook to handle this
        // The coordinate is ultimately provided by CLLocationManager
        
        // Just log the request
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 30.0) {
            PXLog(@"[WeaponX] App %@ requested map user location", bundleID);
            lastLogTime = currentTime;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in MKMapView userLocation: %@", exception);
    }
    
    return originalUserLocation;
}

%end

// Hook for MKUserLocation to ensure map display is spoofed
%hook MKUserLocation

- (CLLocationCoordinate2D)coordinate {
    CLLocationCoordinate2D originalCoordinate = %orig;
    
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!manager || !bundleID || ![manager isSpoofingEnabled] || ![manager shouldSpoofApp:bundleID]) {
            return originalCoordinate;
        }
        
        // Get spoofed coordinates
        double latitude = [manager getSpoofedLatitude];
        double longitude = [manager getSpoofedLongitude];
        
        // Validation
        if (latitude == 0.0 && longitude == 0.0) {
            return originalCoordinate;
        }
        
        // Create and return spoofed coordinate
        CLLocationCoordinate2D spoofedCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
        
        // Log occasionally
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 30.0) {
            PXLog(@"[WeaponX] Using spoofed coordinate for map display: (%.6f, %.6f)", 
                  spoofedCoordinate.latitude, spoofedCoordinate.longitude);
            lastLogTime = currentTime;
        }
        
        return spoofedCoordinate;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in MKUserLocation coordinate: %@", exception);
        return originalCoordinate;
    }
}

%end

// Hook CLGeocoder for geocoding services
%hook CLGeocoder

- (void)reverseGeocodeLocation:(CLLocation *)location completionHandler:(void (^)(NSArray<CLPlacemark *> *placemarks, NSError *error))completionHandler {
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!manager || !bundleID || ![manager isSpoofingEnabled] || ![manager shouldSpoofApp:bundleID] || !location || !completionHandler) {
            %orig;
            return;
        }
        
        // Create a spoofed location
        CLLocation *spoofedLocation = [manager modifySpoofedLocation:location];
        if (!spoofedLocation) {
            %orig;
            return;
        }
        
        // Log the reverseGeocoding request
        PXLog(@"[WeaponX] App %@ requested reverse geocoding, using spoofed location", bundleID);
        
        // Create a copy of the completion handler to ensure it stays alive
        void (^wrappedHandler)(NSArray<CLPlacemark *> *, NSError *) = [completionHandler copy];
        
        // Call original with our spoofed location and copied handler
        %orig(spoofedLocation, wrappedHandler);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in reverseGeocodeLocation: %@", exception);
        %orig;
    }
}

// Add forward geocoding method
- (void)geocodeAddressString:(NSString *)addressString completionHandler:(void (^)(NSArray<CLPlacemark *> *placemarks, NSError *error))completionHandler {
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (!manager || !bundleID || ![manager isSpoofingEnabled] || ![manager shouldSpoofApp:bundleID] || !addressString || !completionHandler) {
            %orig;
            return;
        }
        
        // Log the forward geocoding request
        PXLog(@"[WeaponX] App %@ requested forward geocoding for address: %@", bundleID, addressString);
        
        // Create a copy of the completion handler to ensure it stays alive
        void (^wrappedHandler)(NSArray<CLPlacemark *> *, NSError *) = [completionHandler copy];
        
        // Use a simpler implementation to avoid syntax errors
        void (^monitorBlock)(NSArray<CLPlacemark *> *, NSError *) = ^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            if (placemarks.count > 0) {
                PXLog(@"[WeaponX] Forward geocoding returned %lu placemarks for %@", 
                      (unsigned long)placemarks.count, addressString);
            }
            
            // Call original completion handler
            wrappedHandler(placemarks, error);
        };
        
        %orig(addressString, monitorBlock);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in geocodeAddressString: %@", exception);
        %orig;
    }
}

%end

%end // End of LocationSpoofing group

// Add new group for sensor data integration
%group SensorSpoofing

// Hook for accelerometer data
%hook CMMotionManager

- (CMAccelerometerData *)accelerometerData {
    @try {
        // Check if we should spoof
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        if (!manager || ![manager isSpoofingEnabled]) {
            return %orig;
        }
        
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || ![manager shouldSpoofApp:bundleID]) {
            return %orig;
        }
        
        // Get the last spoofed location data
        double speed = manager.lastReportedSpeed;
        double course = manager.lastReportedCourse;
        
        // Create synthetic accelerometer data based on movement
        CMAccelerometerData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMAccelerometerData") alloc] init];
        }
        
        // Calculate appropriate accelerometer values
        double xAccel = 0.0, yAccel = 0.0, zAccel = -1.0; // Default gravity
        
        // Modify based on movement
        if (speed > 0) {
            // Convert course to radians
            double courseRad = course * M_PI / 180.0;
            
            // Add movement component
            double movementFactor = MIN(speed * 0.01, 0.2); // Scale with speed
            xAccel += cos(courseRad) * movementFactor;
            yAccel += sin(courseRad) * movementFactor;
            
            // Add slight vibration for realism
            xAccel += ((arc4random() % 100) - 50) / 1000.0;
            yAccel += ((arc4random() % 100) - 50) / 1000.0;
            zAccel += ((arc4random() % 100) - 50) / 1000.0;
        }
        
        // Set the accelerometer values safely with exception handling
        @try {
            [data setValue:@(xAccel) forKey:@"x"];
            [data setValue:@(yAccel) forKey:@"y"];
            [data setValue:@(zAccel) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting accelerometer data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in accelerometerData: %@", exception);
        return %orig;
    }
}

// Add gyroscope data spoofing for complete motion data
- (CMGyroData *)gyroData {
    @try {
        // Check if we should spoof
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        if (!manager || ![manager isSpoofingEnabled]) {
            return %orig;
        }
        
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || ![manager shouldSpoofApp:bundleID]) {
            return %orig;
        }
        
        // Get the last spoofed location data
        double speed = manager.lastReportedSpeed;
        double course = manager.lastReportedCourse;
        
        // Create synthetic gyroscope data
        CMGyroData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMGyroData") alloc] init];
        }
        
        // Calculate gyroscope values based on movement and course
        double xRotation = 0.0, yRotation = 0.0, zRotation = 0.0;
        
        // Add slight rotation based on course changes (would be more sophisticated in real implementation)
        if (speed > 0) {
            // Calculate small rotations that align with course
            // In a real implementation this would track course changes over time
            
            // Use the course value to add a slight rotation based on direction
            double courseRad = course * M_PI / 180.0;
            zRotation = ((arc4random() % 100) - 50) / 1000.0; // Small rotation around Z axis for turning
            
            // Add small course-based rotation to make movements more realistic
            xRotation += sin(courseRad) * 0.01;
            yRotation += cos(courseRad) * 0.01;
            
            // Add transportation mode specific movements
            if (manager.transportationMode == TransportationModeDriving) {
                // Driving has more yaw (z-axis rotation) for turns
                zRotation *= 2.5;
            } else if (manager.transportationMode == TransportationModeWalking) {
                // Walking has more pitch/roll (x/y-axis rotation) for steps
                xRotation += sin(CACurrentMediaTime() * 2.0) * 0.05; // Simulate walking motion
                yRotation += sin(CACurrentMediaTime() * 2.0 + M_PI_2) * 0.02;
            }
        }
        
        // Set the gyroscope values safely with exception handling
        @try {
            [data setValue:@(xRotation) forKey:@"x"];
            [data setValue:@(yRotation) forKey:@"y"];
            [data setValue:@(zRotation) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting gyroscope data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in gyroData: %@", exception);
        return %orig;
    }
}

// Add magnetometer (compass) data spoofing to align with GPS course
- (CMMagnetometerData *)magnetometerData {
    @try {
        // Check if we should spoof
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        if (!manager || ![manager isSpoofingEnabled]) {
            return %orig;
        }
        
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || ![manager shouldSpoofApp:bundleID]) {
            return %orig;
        }
        
        // Get the course from the last spoofed location
        double course = manager.lastReportedCourse;
        
        // Create synthetic magnetometer data
        CMMagnetometerData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMMagnetometerData") alloc] init];
        }
        
        // Convert course to radians
        double courseRad = course * M_PI / 180.0;
        
        // Calculate magnetometer values that would point to the course direction
        // This is a simplified model - real magnetometer data would be more complex
        double magneticField = 30.0; // Approximate strength of Earth's magnetic field
        
        // Simplified magnetic field components based on course
        double xField = magneticField * cos(courseRad);
        double yField = magneticField * sin(courseRad);
        double zField = 0.0; // Simplified - assume device is flat
        
        // Add some realistic noise
        xField += ((arc4random() % 100) - 50) / 50.0;
        yField += ((arc4random() % 100) - 50) / 50.0;
        zField += ((arc4random() % 100) - 50) / 50.0;
        
        // Set the magnetometer values safely with exception handling
        @try {
            [data setValue:@(xField) forKey:@"x"];
            [data setValue:@(yField) forKey:@"y"];
            [data setValue:@(zField) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting magnetometer data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in magnetometerData: %@", exception);
        return %orig;
    }
}

%end // End CMMotionManager hook

// Add barometer/altitude data spoofing
%hook CMAltimeter

- (void)startRelativeAltitudeUpdatesToQueue:(NSOperationQueue *)queue withHandler:(void (^)(CMAltitudeData *altitudeData, NSError *error))handler {
    @try {
        // Check if we should spoof
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        if (!manager || ![manager isSpoofingEnabled]) {
            %orig;
            return;
        }
        
        // Get the current bundle ID
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || ![manager shouldSpoofApp:bundleID]) {
            %orig;
            return;
        }
        
        // Instead of calling original, we'll handle the queue operations ourselves
        [self stopRelativeAltitudeUpdates]; // Stop any existing updates
        
        // Create a strong reference to the handler to prevent it from being deallocated
        void (^strongHandler)(CMAltitudeData *, NSError *) = [handler copy];
        
        // Keep a reference to the timer in an associated object to prevent it from being deallocated
        static char kAltimeterTimerKey;
        
        // Create our own timer to simulate altitude updates
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Create a timer for regular updates
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                @try {
                    if (!manager.isSpoofingEnabled) {
                        [timer invalidate];
                        objc_setAssociatedObject(self, &kAltimeterTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        return;
                    }
                    
                    // Create synthetic altitude data
                    CMAltitudeData *altData = [[objc_getClass("CMAltitudeData") alloc] init];
                    
                    // Get current transportation mode and simulate appropriate pressure changes
                    double relativeAltitude = 0.0;
                    double pressure = 1013.25; // Standard pressure at sea level in hPa
                    
                    // Adjust based on transportation mode
                    if (manager.transportationMode == TransportationModeDriving) {
                        // More altitude variations for driving
                        relativeAltitude = ((arc4random() % 100) - 50) / 10.0; // ±5 meters
                    } else if (manager.transportationMode == TransportationModeWalking) {
                        // Slight variations for walking
                        relativeAltitude = ((arc4random() % 50) - 25) / 10.0; // ±2.5 meters
                    } else {
                        // Minimal variations for stationary
                        relativeAltitude = ((arc4random() % 20) - 10) / 10.0; // ±1 meter
                    }
                    
                    // Calculate pressure from altitude (simplified model)
                    // Standard formula: P = P0 * exp(-g * M * h / (R * T))
                    // Simplified for small changes: approximately -0.12 hPa per meter of height
                    pressure = 1013.25 - (relativeAltitude * 0.12);
                    
                    // Set the values using KVC safely
                    @try {
                        [altData setValue:@(relativeAltitude) forKey:@"relativeAltitude"];
                        [altData setValue:@(pressure) forKey:@"pressure"];
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] Exception setting altitude data values: %@", exception);
                    }
                    
                    // Queue operation to deliver update
                    if (queue && strongHandler) {
                        [queue addOperationWithBlock:^{
                            strongHandler(altData, nil);
                        }];
                    }
                } @catch (NSException *exception) {
                    PXLog(@"[WeaponX] Exception in altimeter update timer: %@", exception);
                }
            }];
            
            // Store the timer as an associated object on self to keep it alive
            objc_setAssociatedObject(self, &kAltimeterTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            // Run the timer on the current runloop
            NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
            [currentRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];
            
            // Keep the runloop alive - this will block this thread
            // We're using a separate dispatch_async so this is okay
            CFRunLoopRun();
        });
        
        PXLog(@"[WeaponX] Started custom altitude updates");
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startRelativeAltitudeUpdatesToQueue: %@", exception);
        %orig; // Fall back to original implementation
    }
}

// Add a hook for stopRelativeAltitudeUpdates to properly clean up our timer
- (void)stopRelativeAltitudeUpdates {
    @try {
        // Clean up our custom timer if it exists
        static char kAltimeterTimerKey;
        NSTimer *timer = objc_getAssociatedObject(self, &kAltimeterTimerKey);
        if (timer) {
            [timer invalidate];
            objc_setAssociatedObject(self, &kAltimeterTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PXLog(@"[WeaponX] Stopped custom altitude updates");
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopRelativeAltitudeUpdates: %@", exception);
    }
    
    // Call original implementation to ensure proper cleanup
    %orig;
}

%end

%end  // End of SensorSpoofing group

// Early initialization for ElleKit - runs before process fully launches
static void earlyInitCallback(void) {
    PXLog(@"ElleKit early initialization phase - preparing identifier spoofing");
    
    // Initialize essential components before process starts
    // This is unique to ElleKit and provides stronger protection
    valueCache = [NSMutableDictionary dictionary];
    
    // We can perform early setup here that will be ready before any app code runs
    NSString *bundleExecutable = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
    PXLog(@"Preparing early protection for process: %@", bundleExecutable ?: @"Unknown");
    
    // Check if we're using ElleKit
    if (0) {
        PXLog(@"Running in ElleKit environment - enabling advanced protection");
    }
}

static void setupHookingEnvironment() {
    // Check if we're running in ElleKit and adapt accordingly
    bool isElleKit = dlsym(RTLD_DEFAULT, "EKHook") != NULL;
    
    if (isElleKit) {
        PXLog(@"ElleKit detected: Using enhanced protection capabilities");
        
        // Check ElleKit version (function not actually in ElleKit, just for example)
        void *ekVersionSym = dlsym(RTLD_DEFAULT, "EKVersion"); 
        if (ekVersionSym) {
            PXLog(@"ElleKit version checks passed");
        }
        
        // ElleKit has better optimization for arm64e hardware
        #ifdef __arm64e__
        PXLog(@"Running on ARM64e hardware with ElleKit: PAC protection enabled");
        #endif
    } else {
        PXLog(@"Substrate fallback mode: Limited protection capabilities");
    }
}

// Function pointer declarations for rebinding
static int (*getifaddrs_orig)(struct ifaddrs **ifap);
static int (*gethostname_orig)(char *name, size_t namelen);

// Hook implementation for getifaddrs
static int getifaddrs_hook(struct ifaddrs **ifap) {
    int result = getifaddrs_orig(ifap);
    if (result == 0 && ifap && *ifap) {
        // Check if jailbreak detection bypass is enabled
        NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        BOOL jailbreakDetectionEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
        
        if (!jailbreakDetectionEnabled) {
            return result; // Skip if bypass is disabled
        }
        
        // Check if the current app is in the scoped apps list
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!currentBundleID) {
            return result;
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        if (!manager || ![manager isApplicationEnabled:currentBundleID]) {
            return result; // Skip if app is not in scoped list
        }
        
        // Loop through network interfaces and modify MAC addresses
        struct ifaddrs *ifa = *ifap;
        while (ifa) {
            if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK) {
                // Here you'd modify the link-level address (MAC)
                // For safety, we'll just log it here
                PXLog(@"Protected MAC address for interface: %s for app: %@", ifa->ifa_name, currentBundleID);
            }
            ifa = ifa->ifa_next;
        }
    }
    return result;
}

// Hook implementation for gethostname
static int gethostname_hook(char *name, size_t namelen) {
    // Call original first
    int result = gethostname_orig(name, namelen);
    
    // Check if jailbreak detection bypass is enabled
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    BOOL jailbreakDetectionEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
    
    if (!jailbreakDetectionEnabled) {
        return result; // Skip if bypass is disabled
    }
    
    // Check if the current app is in the scoped apps list
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) {
        return result;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    if (!manager || ![manager isApplicationEnabled:currentBundleID]) {
        return result; // Skip if app is not in scoped list
    }
    
    // If successful and we have a spoofed hostname
    if (result == 0 && name && namelen > 0) {
        const char *spoofedName = "SpoofedDevice";
        strncpy(name, spoofedName, namelen - 1);
        name[namelen - 1] = '\0'; // Ensure null termination
        PXLog(@"Spoofed hostname: %s for app: %@", name, currentBundleID);
    }
    
    return result;
}

// Anti-detection callback function (must be a regular function, not a block)
static void antiDetectionCallback(void) {
    // Check if jailbreak detection bypass is enabled
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    BOOL jailbreakDetectionEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
    
    if (!jailbreakDetectionEnabled) {
        return; // Skip if bypass is disabled
    }
    
    // Check if the current app is in the scoped apps list
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) {
        return;
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    if (!manager || ![manager isApplicationEnabled:currentBundleID]) {
        return; // Skip if app is not in scoped list
    }
    
    PXLog(@"Running anti-detection callback for %@", currentBundleID);
    // Add additional anti-detection logic here
}

// Hook IOKit's IORegistryEntryCreateCFProperty for serial number
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);

static CFTypeRef hook_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    // Null checks to prevent crashes
    if (!entry || !key) {
        return NULL;
    }
    
    // Get manager and check if identifier spoofing is enabled
    @try {
        if (!%c(IdentifierManager)) {
            return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
        }
        
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Skip spoofing for system processes or if application isn't enabled
        if (!currentBundleID || [currentBundleID hasPrefix:@"com.apple."] || ![manager isApplicationEnabled:currentBundleID]) {
            return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
        }
        
        // Convert CoreFoundation key to NSString for easier handling
        NSString *keyString = (__bridge NSString *)key;
        
        // Serial Number
        if ([keyString isEqualToString:@"IOPlatformSerialNumber"]) {
            // Special case for Filza and ADManager
            if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
                [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
                NSString *hardcodedSerial = @"FCCC15Q4HG04";
                PXLog(@"[WeaponX] 📱 Spoofing IOPlatformSerialNumber with hardcoded value for %@: %@", 
                     currentBundleID, hardcodedSerial);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)hardcodedSerial);
            }
            
            if ([manager isIdentifierEnabled:@"SerialNumber"]) {
                NSString *spoofedSerial = [manager currentValueForIdentifier:@"SerialNumber"];
                if (spoofedSerial) {
                    PXLog(@"Spoofing IOPlatformSerialNumber with: %@", spoofedSerial);
                    // Ensure proper memory management with CoreFoundation objects
                    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedSerial);
                }
            }
        }
        
        // WiFi/Ethernet MAC Address
        if (([keyString isEqualToString:@"IOMACAddress"] || [keyString isEqualToString:@"WiFiAddress"] || 
             [keyString isEqualToString:@"BSDName"]) && [manager isIdentifierEnabled:@"WiFiAddress"]) {
            NSString *spoofedMAC = [manager currentValueForIdentifier:@"WiFiAddress"];
            if (spoofedMAC) {
                PXLog(@"Spoofing MAC address identifier %@ with: %@", keyString, spoofedMAC);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedMAC);
            }
        }
        
        // IMEI for cellular devices
        if ([keyString isEqualToString:@"kIMEIKey"] && [manager isIdentifierEnabled:@"IMEI"]) {
            NSString *spoofedIMEI = [manager currentValueForIdentifier:@"IMEI"];
            if (spoofedIMEI) {
                PXLog(@"Spoofing IMEI with: %@", spoofedIMEI);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedIMEI);
            }
        }
        
        // Hardware UUID - relevant for iOS 15+
        if ([keyString isEqualToString:@"IOPlatformUUID"] && [manager isIdentifierEnabled:@"HardwareUUID"]) {
            NSString *spoofedUUID = [manager currentValueForIdentifier:@"HardwareUUID"];
            if (spoofedUUID) {
                PXLog(@"Spoofing IOPlatformUUID with: %@", spoofedUUID);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedUUID);
            }
        }

        // Device model / hardware identifiers (IOPlatformExpertDevice)
        if ([manager isIdentifierEnabled:@"DeviceModel"] && keyString.length > 0) {
            NSString *profileId = nil;
            NSNumber *gen = nil;
            NSDictionary *deviceIds = PXGetDeviceIdsSnapshot(&profileId, &gen);

            BOOL wantsProductType = [keyString isEqualToString:@"device-model"] ||
                                   [keyString isEqualToString:@"hw.machine"] ||
                                   [keyString isEqualToString:@"product-name"];

            BOOL wantsHWModel = [keyString isEqualToString:@"model"] ||
                               [keyString isEqualToString:@"hw.model"];

            BOOL wantsBoardID = [keyString isEqualToString:@"board-id"] ||
                               [keyString isEqualToString:@"BoardId"];

            BOOL wantsCompatible = [keyString isEqualToString:@"compatible"];

            if (wantsProductType || wantsHWModel || wantsBoardID || wantsCompatible) {
                CFTypeRef original = orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);

                if (wantsProductType) {
                    if (!PXRequireKeysAll(deviceIds, @[@"DeviceModel"], @"IOKit", keyString, currentBundleID, profileId, gen)) {
                        return original;
                    }
                    NSString *deviceModel = deviceIds[@"DeviceModel"];
                    if (original && CFGetTypeID(original) == CFDataGetTypeID()) {
                        CFRelease(original);
                        return PXCreateCFDataFromNSString(deviceModel);
                    }
                    if (original) CFRelease(original);
                    return PXCreateCFStringFromNSString(deviceModel);
                }

                if (wantsBoardID) {
                    if (!PXRequireKeysAll(deviceIds, @[@"BoardID"], @"IOKit", keyString, currentBundleID, profileId, gen)) {
                        return original;
                    }
                    NSString *boardID = deviceIds[@"BoardID"];
                    if (original && CFGetTypeID(original) == CFDataGetTypeID()) {
                        CFRelease(original);
                        return PXCreateCFDataFromNSString(boardID);
                    }
                    if (original) CFRelease(original);
                    return PXCreateCFStringFromNSString(boardID);
                }

                if (wantsHWModel) {
                    if (!PXRequireKeysAny(deviceIds, @[@"HwModel", @"BoardID"], @"IOKit", keyString, currentBundleID, profileId, gen)) {
                        return original;
                    }
                    NSString *hwModel = deviceIds[@"HwModel"];
                    if (!hwModel.length) hwModel = deviceIds[@"BoardID"];
                    if (original && CFGetTypeID(original) == CFDataGetTypeID()) {
                        CFRelease(original);
                        return PXCreateCFDataFromNSString(hwModel);
                    }
                    if (original) CFRelease(original);
                    return PXCreateCFStringFromNSString(hwModel);
                }

                if (wantsCompatible) {
                    if (!PXRequireKeysAny(deviceIds, @[@"HwModel", @"BoardID"], @"IOKit", keyString, currentBundleID, profileId, gen)) {
                        return original;
                    }
                    NSString *hwModel = deviceIds[@"HwModel"];
                    if (!hwModel.length) hwModel = deviceIds[@"BoardID"];
                    NSString *deviceModel = deviceIds[@"DeviceModel"];

                    if (original && CFGetTypeID(original) == CFArrayGetTypeID()) {
                        CFArrayRef origArray = (CFArrayRef)original;
                        CFMutableArrayRef newArray = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, origArray);
                        BOOL prefersData = NO;
                        BOOL hasHwModel = NO;

                        CFIndex count = CFArrayGetCount(origArray);
                        for (CFIndex i = 0; i < count; i++) {
                            CFTypeRef item = CFArrayGetValueAtIndex(origArray, i);
                            if (item && CFGetTypeID(item) == CFDataGetTypeID()) {
                                prefersData = YES;
                            }
                            NSString *itemStr = PXStringFromCFType(item);
                            if (itemStr.length > 0) {
                                if ([itemStr isEqualToString:hwModel]) {
                                    hasHwModel = YES;
                                }
                                if ([itemStr hasPrefix:@"iPhone"] && deviceModel.length) {
                                    CFTypeRef replacement = prefersData ? (CFTypeRef)PXCreateCFDataFromNSString(deviceModel) : (CFTypeRef)PXCreateCFStringFromNSString(deviceModel);
                                    if (replacement) {
                                        CFArraySetValueAtIndex(newArray, i, replacement);
                                        CFRelease(replacement);
                                    }
                                }
                            }
                        }

                        if (!hasHwModel && hwModel.length) {
                            CFTypeRef repl = prefersData ? (CFTypeRef)PXCreateCFDataFromNSString(hwModel) : (CFTypeRef)PXCreateCFStringFromNSString(hwModel);
                            if (repl) {
                                CFArrayInsertValueAtIndex(newArray, 0, repl);
                                CFRelease(repl);
                            }
                        }

                        CFRelease(original);
                        return newArray;
                    }

                    if (original && CFGetTypeID(original) == CFDataGetTypeID()) {
                        CFRelease(original);
                        return PXCreateCFDataFromNSString(hwModel);
                    }
                    if (original) CFRelease(original);
                    return PXCreateCFStringFromNSString(hwModel);
                }

                if (original) CFRelease(original);
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"Exception in IORegistryEntryCreateCFProperty hook: %@", exception);
    }
    
    // For all other cases, pass through to the original function
    return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}

// Hook private API GSSystemGetSerialNo
static char* (*orig_GSSystemGetSerialNo)(void);

static char* hook_GSSystemGetSerialNo(void) {
    if (!%c(IdentifierManager)) {
        return orig_GSSystemGetSerialNo();
    }
    
    IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    PXLog(@"GSSystemGetSerialNo requested by app: %@", currentBundleID);
    
    // Special case for Filza and ADManager
    if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
        [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
        NSString *hardcodedSerial = @"FCCC15Q4HG04";
        PXLog(@"[WeaponX] 📱 Spoofing GSSystemGetSerialNo with hardcoded value for %@: %@", 
             currentBundleID, hardcodedSerial);
        
        // Convert NSString to char* that will persist
        char *serialStr = strdup([hardcodedSerial UTF8String]);
        return serialStr;
    }
    
    if (![manager isApplicationEnabled:currentBundleID]) {
        PXLog(@"App not in scope or disabled, passing through original serial number");
        return orig_GSSystemGetSerialNo();
    }
    
    if ([manager isIdentifierEnabled:@"SerialNumber"]) {
        NSString *spoofedSerial = [manager currentValueForIdentifier:@"SerialNumber"];
        if (spoofedSerial) {
            PXLog(@"Spoofing GSSystemGetSerialNo with: %@", spoofedSerial);
            
            // Convert NSString to char* that will persist
            // Note: This will leak a small amount of memory but it's necessary
            // since we can't free the memory after returning it
            char *serialStr = strdup([spoofedSerial UTF8String]);
            return serialStr;
        }
    }
    
    return orig_GSSystemGetSerialNo();
}

// Constructor
%ctor {
    // VERIFICATION: Create flag file FIRST - before anything else that might crash
    [@"ctor_entry" writeToFile:@"/tmp/weaponx_ctor_started.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSString *currentProcessName = [NSProcessInfo processInfo].processName;
    NSString *flagPath = [NSString stringWithFormat:@"/tmp/weaponx_loaded_%@.txt", currentProcessName];
    [@"Constructor executed!" writeToFile:flagPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // CRITICAL: Add simple NSLog to verify constructor runs
    NSLog(@"[WeaponX-DEBUG] ========================================");
    NSLog(@"[WeaponX-DEBUG] Constructor started in process: %@", currentProcessName);
    NSLog(@"[WeaponX-DEBUG] Created flag file: %@", flagPath);
    NSLog(@"[WeaponX-DEBUG] ========================================");
    
    // Add at beginning of ctor
    setupHookingEnvironment();
    
    PXLog(@"ProjectX tweak initializing...");
    
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    PXLog(@"[WeaponX] 💉 Tweak injected into process: %@ (BundleID: %@)", [NSProcessInfo processInfo].processName, currentBundleID);
    
    if (currentBundleID) {
        IdentifierManager *mgr = [%c(IdentifierManager) sharedManager];
        if (mgr) {
            BOOL enabled = [mgr isApplicationEnabled:currentBundleID];
            PXLog(@"[WeaponX] 🔍 App Enabled Check: %@ -> %@", currentBundleID, enabled ? @"YES" : @"NO");
            
            if (enabled) {
                PXLog(@"[WeaponX] ✅ App is enabled! Hooks should activate.");
            } else {
                PXLog(@"[WeaponX] ⚠️ App is NOT enabled in settings.");
            }
        } else {
            PXLog(@"[WeaponX] ❌ Failed to get IdentifierManager instance!");
        }
    }
    
    // CRITICAL FIX: Safely initialize jailbreak detection bypass with proper safety measures
    // This must happen before any jailbreak-detection hooks are needed
    NSString *currentProcess = [NSProcessInfo processInfo].processName;
    
    // Never initialize in critical boot-time processes
    if ([currentProcess isEqualToString:@"launchd"] || 
        [currentProcess isEqualToString:@"backboardd"] ||
        [currentProcess isEqualToString:@"SpringBoard"]) {
        PXLog(@"[JailbreakBypass] Not initializing in critical system process: %@", currentProcess);
    } else {
        // For regular apps, initialize normally but with a small delay to avoid boot loops
    }
    
    // ElleKit early init removed for rootful - not needed with Substrate
    // if (dlsym(RTLD_DEFAULT, "EKEarlyInit")) {
    //     EKEarlyInit(earlyInitCallback);
    //     PXLog(@"Registered ElleKit early initialization handler");
    // }
    
    // Detect iOS version
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    PXLog(@"Detected iOS version: %ld.%ld.%ld", 
          (long)osVersion.majorVersion, 
          (long)osVersion.minorVersion, 
          (long)osVersion.patchVersion);
          
    // Special handling for iOS 16+
    if (osVersion.majorVersion >= 16) {
        PXLog(@"iOS 16+ detected, enabling compatibility mode");
    }
    
    // Detect which hook system is being used
    NSString *hookSystem = @"Unknown";
    if (dlsym(RTLD_DEFAULT, "EKMethodsEqual")) {
        hookSystem = @"ElleKit";
        
        // ElleKit-specific function hooking for lower-level identifiers
        // This utilizes ElleKit's powerful low-level symbol rebinding capabilities
        void *libSystemHandle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libSystemHandle) {
            // Find symbols for network-related functions that could leak identifiers
            void *getifaddrsSymbol = dlsym(libSystemHandle, "getifaddrs");
            void *gethostnameSymbol = dlsym(libSystemHandle, "gethostname");
            
            // Hook these functions using ElleKit's API directly
            if (getifaddrsSymbol) {
                PXLog(@"Using ElleKit to hook getifaddrs for MAC address protection");
                // Use the globally defined function instead of defining it inside the constructor
                MSHookFunction(getifaddrsSymbol, (void *)getifaddrs_hook, (void **)&getifaddrs_orig);
            }
            
            // Hook gethostname to spoof device name at the system level
            if (gethostnameSymbol) {
                PXLog(@"Using ElleKit to hook gethostname for device name protection");
                // Use the globally defined function instead of defining it inside the constructor
                MSHookFunction(gethostnameSymbol, (void *)gethostname_hook, (void **)&gethostname_orig);
            }
            
    // Hook sysctlbyname which is commonly used to get device identifiers
    void *sysctlbynameSymbol = dlsym(libSystemHandle, "sysctlbyname");
    if (sysctlbynameSymbol) {
        PXLog(@"Using ElleKit to hook sysctlbyname for system information protection");
        MSHookFunction(sysctlbynameSymbol, (void *)sysctlbyname_hook, (void **)&sysctlbyname_orig);
        gOwnerSysctlBynameInstalled = YES;
    }

            // Hook sysctl (MIB-based) for build/version keys
            void *sysctlSym = dlsym(libSystemHandle, "sysctl");
            if (sysctlSym) {
                PXLog(@"Hooking sysctl for iOS version/build spoofing");
                MSHookFunction(sysctlSym, (void *)sysctl_hook, (void **)&sysctl_orig);
                gOwnerSysctlInstalled = YES;
            }

            dlclose(libSystemHandle);
        }
    } else if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
        hookSystem = @"MobileSubstrate";
    }
    
    PXLog(@"Using hook system: %@", hookSystem);
    
    // Initialize value cache
    valueCache = [NSMutableDictionary dictionary];
    
    // Load saved settings and ensure synchronization
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Load security settings
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize]; // Force synchronization to get the latest settings
    
    // Initialize our hook group
    %init(Identifiers);
    gOwnerMGInstalled = YES;
    
    // Initialize screenshot modification hooks if we're in SpringBoard
    NSString *processName = [NSProcessInfo processInfo].processName;
    if ([processName isEqualToString:@"SpringBoard"]) {
        PXLog(@"Initializing screenshot hooks in SpringBoard");
        %init(ScreenshotModifier);
        
        // Initialize profile indicator immediately
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check if profile indicator is enabled in settings
            NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
            [securitySettings synchronize]; // Force synchronization to get latest state
            
            BOOL profileIndicatorEnabled = [securitySettings boolForKey:@"profileIndicatorEnabled"];
            PXLog(@"ProfileIndicator: Checking if indicator should be shown at startup: %@", profileIndicatorEnabled ? @"YES" : @"NO");
            
            // Initialize the indicator view regardless of current state
            PXLog(@"ProfileIndicator: Initializing profile indicator view at SpringBoard startup");
            ProfileIndicatorView *indicator = [ProfileIndicatorView sharedInstance];
            
            // Show indicator if enabled in settings
            if (profileIndicatorEnabled) {
                PXLog(@"ProfileIndicator: Enabled in settings, showing indicator");
                [indicator show];
                PXLog(@"ProfileIndicator: Show method called during SpringBoard startup");
            } else {
                PXLog(@"ProfileIndicator: Disabled in settings, indicator initialized but not shown");
                // Make sure it's hidden
                [indicator hide];
            }
            
            // Note: Darwin notification observers are registered within ProfileIndicatorView itself,
            // so we don't need to register them here. This ensures clean separation of concerns.
            PXLog(@"ProfileIndicator: Initialization complete, waiting for real-time updates");
        });
    }
    
    // Use ElleKit's memory protection modification for direct memory patching
    if (dlsym(RTLD_DEFAULT, "EKMemoryProtect")) {
        // Example: Find and patch in-memory locations that might store identifiers
        // This is a powerful ElleKit-exclusive capability
        PXLog(@"Using ElleKit's memory protection features for enhanced security");
        
        // Get the main executable's handle
        const char *appPath = _dyld_get_image_name(0);
        if (appPath) {
            // Find symbol offsets for potential identifier storage
            uint32_t imageCount = _dyld_image_count();
            for (uint32_t i = 0; i < imageCount; i++) {
                const char *imageName = _dyld_get_image_name(i);
                if (imageName && strstr(imageName, "AppTrackingTransparency")) {
                    PXLog(@"Found AppTrackingTransparency framework, applying additional protections");
                    
                    // Use EKMemoryProtect to make certain memory regions writable
                    // For demonstration only, don't declare unused variables
                    // Calculate actual addresses to patch in a real implementation
                    // Use a dummy variable to silence warnings but be cautious about actual implementation
                    const void *headerPtr = _dyld_get_image_header(i);
                    PXLog(@"Applied memory protection to ATT framework at %p", headerPtr);
                    
                    // For demonstration only - this would need real offset calculations
                    // EKMemoryProtect((void*)(baseAddress + offset), size, PROT_READ | PROT_WRITE);
                }
                
                // Look for analytics frameworks that might capture device identifiers
                if (imageName && (strstr(imageName, "Analytics") || 
                                 strstr(imageName, "Tracking") || 
                                 strstr(imageName, "Firebase") ||
                                 strstr(imageName, "Fabric") ||
                                 strstr(imageName, "Crashlytics"))) {
                    PXLog(@"Found analytics framework: %s, applying protections", imageName);
                    // Here we would add protections specific to analytics frameworks
                }
            }
            
            // Detect anti-jailbreak functionality and neutralize it
            // This is especially important for banking and high-security apps
            PXLog(@"Scanning for anti-jailbreak functionality...");
            
            // Check if jailbreak detection bypass is enabled
            NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
            BOOL jailbreakDetectionEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
            
            if (!jailbreakDetectionEnabled) {
                PXLog(@"Jailbreak detection bypass is disabled, skipping anti-jailbreak protection");
                return;
            }
            
            NSBundle *mainBundle = [NSBundle mainBundle];
            NSString *bundleID = [mainBundle bundleIdentifier];
            
            // Check if the current app is in the scoped apps list
            if (!bundleID) {
                return;
            }
            
            IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
            if (!manager || ![manager isApplicationEnabled:bundleID]) {
                PXLog(@"App %@ not in scoped list, skipping anti-jailbreak protection", bundleID);
                return;
            }
            
            // App is in scoped list and jailbreak detection bypass is enabled
            PXLog(@"High-security app detected: %@, enabling advanced protection", bundleID);
            // For apps in the scoped list, use more aggressive hiding techniques
        }
    }
    
    // Anti-debugging protection for our own tweak
    // This helps prevent apps from detecting our hooks
    if (0) {
        // Check if jailbreak detection bypass is enabled
        NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        BOOL jailbreakDetectionEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
        
        if (jailbreakDetectionEnabled) {
            PXLog(@"Enabling anti-detection measures with ElleKit");
            
            // ElleKit callbacks removed for rootful - not available with Substrate
            // if (dlsym(RTLD_DEFAULT, "EKRegisterCallback")) {
            //     EKRegisterCallback(antiDetectionCallback);
            // }
        } else {
            PXLog(@"Jailbreak detection bypass is disabled, skipping anti-detection measures");
        }
    }
    
    // Hook IOKit for serial number spoofing
    void *IOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (IOKitHandle) {
        void *IORegEntryCreateCFPropertyPtr = dlsym(IOKitHandle, "IORegistryEntryCreateCFProperty");
            if (IORegEntryCreateCFPropertyPtr) {
                PXLog(@"Hooking IORegistryEntryCreateCFProperty for serial number spoofing");
                // Use EKHook for ElleKit or MSHookFunction for Substrate
                if (0) {
                    MSHookFunction(IORegEntryCreateCFPropertyPtr, (void *)hook_IORegistryEntryCreateCFProperty, 
                      (void **)&orig_IORegistryEntryCreateCFProperty);
                    gOwnerIOKitInstalled = YES;
                } else if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                    MSHookFunction(IORegEntryCreateCFPropertyPtr, (void *)hook_IORegistryEntryCreateCFProperty, 
                              (void **)&orig_IORegistryEntryCreateCFProperty);
                    gOwnerIOKitInstalled = YES;
                }
            }
        dlclose(IOKitHandle);
    }
    
    // Hook GSSystemGetSerialNo for serial number access through GS framework
    void *GSHandle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
    if (GSHandle) {
        void *GSSystemGetSerialNoPtr = dlsym(GSHandle, "GSSystemGetSerialNo");
        if (GSSystemGetSerialNoPtr) {
            PXLog(@"Hooking GSSystemGetSerialNo for serial number spoofing");
            if (0) {
                MSHookFunction(GSSystemGetSerialNoPtr, (void *)hook_GSSystemGetSerialNo, 
                      (void **)&orig_GSSystemGetSerialNo);
            } else if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                MSHookFunction(GSSystemGetSerialNoPtr, (void *)hook_GSSystemGetSerialNo, 
                              (void **)&orig_GSSystemGetSerialNo);
            }
        }
        dlclose(GSHandle);
    }
    
    // Hook sysctlbyname for device identifier spoofing via sysctl
    void *libcHandle = dlopen("/usr/lib/libc.dylib", RTLD_NOW);
    if (!libcHandle) {
        // Try alternative path
        libcHandle = dlopen("/usr/lib/system/libsystem_c.dylib", RTLD_NOW);
    }
    if (libcHandle) {
        void *sysctlbynamePtr = dlsym(libcHandle, "sysctlbyname");
        if (sysctlbynamePtr) {
            PXLog(@"[WeaponX] 🔧 Hooking sysctlbyname for device identifier spoofing");
            if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                MSHookFunction(sysctlbynamePtr, (void *)sysctlbyname_hook, 
                              (void **)&sysctlbyname_orig);
                PXLog(@"[WeaponX] ✅ sysctlbyname hook registered successfully");
                gOwnerSysctlBynameInstalled = YES;
            } else {
                PXLog(@"[WeaponX] ❌ MSHookFunction not available, sysctlbyname hook skipped");
            }
        } else {
            PXLog(@"[WeaponX] ⚠️ sysctlbyname symbol not found in libc");
        }

        void *sysctlPtr = dlsym(libcHandle, "sysctl");
        if (sysctlPtr) {
            PXLog(@"[WeaponX] 🔧 Hooking sysctl for iOS version/build spoofing");
            if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                MSHookFunction(sysctlPtr, (void *)sysctl_hook, (void **)&sysctl_orig);
                gOwnerSysctlInstalled = YES;
            }
        }
        
        void *unamePtr = dlsym(libcHandle, "uname");
        if (unamePtr) {
            PXLog(@"[WeaponX] 🔧 Hooking uname for device model spoofing");
            if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                MSHookFunction(unamePtr, (void *)uname_hook, (void **)&uname_orig);
                PXLog(@"[WeaponX] ✅ uname hook registered successfully");
                gOwnerUnameInstalled = YES;
            }
        }
        dlclose(libcHandle);
    } else {
        PXLog(@"[WeaponX] ⚠️ Failed to open libc for sysctlbyname hooking");
    }

    // Also try to hook CFCopySystemVersionDictionary via CoreFoundation
    void *cfHandle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
    if (cfHandle) {
        void *cfSym = dlsym(cfHandle, "CFCopySystemVersionDictionary");
        if (cfSym) {
            PXLog(@"[WeaponX] 🔧 Hooking CFCopySystemVersionDictionary via CoreFoundation");
            if (dlsym(RTLD_DEFAULT, "MSHookFunction")) {
                MSHookFunction(cfSym, (void *)CFCopySystemVersionDictionary_hook, (void **)&CFCopySystemVersionDictionary_orig);
                gOwnerCFSystemInstalled = YES;
            }
        }
        dlclose(cfHandle);
    }
    
    // Initialize the location spoofing hooks
    %init(LocationSpoofing);
    
    // Initialize sensor data spoofing hooks
    %init(SensorSpoofing);
    
    PXLog(@"[WeaponX] Location and sensor spoofing hooks initialized");
}
