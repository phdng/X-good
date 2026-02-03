#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ProjectXLogging.h"
#import "HookOwnership.h"
#import "IOSVersionInfo.h"
#import <WebKit/WebKit.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <substrate.h>
// #import <ellekit/ellekit.h> // Removed for rootful - using Substrate
#import <mach/mach_time.h>
#import <dispatch/dispatch.h>

#import "PXScope.h"

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Add a macro for logging with a recognizable prefix
// Set DEBUG_LOG to 0 to reduce logging in production
#define DEBUG_LOG 0

#if DEBUG_LOG
#define IOSVERSION_LOG(fmt, ...) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#else
// Only log important messages when DEBUG_LOG is off
#define IOSVERSION_LOG(fmt, ...) if ([fmt hasPrefix:@"❌"] || [fmt hasPrefix:@"⚠️"]) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#endif

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);
static BOOL isCriticalSystemProcess(NSString *bundleID);
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion);
static BOOL isSystemVersionFile(NSString *path);
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist);

// Function declarations for file access hooks
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path);
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path);
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

// Original sysctlbyname function pointer for hooking
static int (*original_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

// Original function pointers for direct file access hooks
static NSData* (*original_NSData_dataWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static NSDictionary* (*original_NSDictionary_dictionaryWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static id (*original_NSString_stringWithContentsOfFile)(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

// Global variables
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes
static NSMutableDictionary *versionCache = nil;
static NSTimeInterval lastVersionLoad = 0;

// Throttling variables to prevent excessive function calls
static uint64_t lastSystemVersionCallTime = 0;
static NSString *cachedSystemVersionResult = nil;
static uint64_t lastDictCallTime = 0;
static CFDictionaryRef cachedDictResult = NULL;

// Define constants
#define VERSION_CACHE_VALID_PERIOD 1800.0 // 30 minutes
#define THROTTLE_INTERVAL_NSEC 100000000  // 100ms in nanoseconds

// SystemVersion.plist path constants
#define SYSTEM_VERSION_PATH @"/System/Library/CoreServices/SystemVersion.plist"
#define ROOTLESS_SYSTEM_VERSION_PATH @"/System/Library/CoreServices/SystemVersion.plist"

#pragma mark - Helper Functions

// Get the current bundle ID
static NSString *getCurrentBundleID(void) {
    @try {
        NSBundle *mainBundle = [NSBundle mainBundle];
        if (!mainBundle) {
            return nil;
        }
        return [mainBundle bundleIdentifier];
    } @catch (NSException *e) {
        return nil;
    }
}

// Load scoped apps from the plist file
static NSDictionary *loadScopedApps(void) {
    @try {
        // Check if cache is valid
        if (scopedAppsCache && scopedAppsCacheTimestamp && 
            [[NSDate date] timeIntervalSinceDate:scopedAppsCacheTimestamp] < kScopedAppsCacheValidDuration) {
            return scopedAppsCache;
        }
        
        // Initialize cache if needed
        if (!scopedAppsCache) {
            scopedAppsCache = [NSMutableDictionary dictionary];
        } else {
            [scopedAppsCache removeAllObjects];
        }
        
        // Try each possible path for the scoped apps file
        NSArray *possiblePaths = @[kScopedAppsPath, kScopedAppsPathAlt1, kScopedAppsPathAlt2];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *validPath = nil;
        
        for (NSString *path in possiblePaths) {
            if ([fileManager fileExistsAtPath:path]) {
                validPath = path;
                break;
            }
        }
        
        if (!validPath) {
            // Don't log this error too frequently to avoid spam
            static NSDate *lastErrorLog = nil;
            if (!lastErrorLog || [[NSDate date] timeIntervalSinceDate:lastErrorLog] > 300.0) { // 5 minutes
                PXLog(@"[IOSVersionHooks] Could not find scoped apps file");
                lastErrorLog = [NSDate date];
            }
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Load the plist file safely
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        if (!plistDict || ![plistDict isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Get the scoped apps dictionary
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Copy the scoped apps to our cache
        [scopedAppsCache addEntriesFromDictionary:scopedApps];
        scopedAppsCacheTimestamp = [NSDate date];
        
        return scopedAppsCache;
        
    } @catch (NSException *e) {
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache ?: [NSMutableDictionary dictionary];
    }
}

// Check if the current app is in the scoped apps list
static BOOL isInScopedAppsList(void) {
    @try {
        NSString *bundleID = getCurrentBundleID();
        if (!bundleID || [bundleID length] == 0) {
            return NO;
        }
        
        NSDictionary *scopedApps = loadScopedApps();
        if (!scopedApps || scopedApps.count == 0) {
            return NO;
        }
        
        // Check if this bundle ID is in the scoped apps dictionary
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        
        // Check if the app is enabled
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
        
    } @catch (NSException *e) {
        return NO;
    }
}

// Critical system processes to exclude from spoofing
static NSSet *criticalSystemBundleIDs() {
    static NSSet *criticalBundleIDs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        criticalBundleIDs = [NSSet setWithArray:@[
            @"com.apple.springboard",
            @"com.apple.backboardd",
            @"com.apple.Preferences",
            @"com.apple.UIKit",
            @"com.apple.iokit",
            @"com.apple.mediaserverd",
            @"com.apple.dock",
            @"com.apple.security",
            @"com.apple.powerd",
            @"com.apple.tccd",
            @"com.apple.launchd",
            @"com.apple.trustd",
            @"com.apple.CoreTelephony",
            // Note: The following browser-related bundle IDs are kept in this list
            // but special handling in isCriticalSystemProcess allows spoofing for them
            @"com.apple.mobilesafari",
            @"com.apple.WebKit",
            @"com.apple.WebKit.WebContent",
            @"com.apple.WebKit.Networking"
        ]];
    });
    return criticalBundleIDs;
}

// Helper function to check if we should spoof for this bundle ID (with caching)
static BOOL shouldSpoofForBundle(NSString *bundleID) {
    @try {
        // Basic validation
        if (!bundleID) {
            NSLog(@"[iosversion] Skipping iOS version spoofing for nil bundleID");
            return NO;
        }

        // Allow unscoped spoofing for Safari/Auth stack when enabled.
        if (PXAllowUnscopedSafariStack()) {
            return YES;
        }
        
        // Check cache first
        if (!cachedBundleDecisions) {
            cachedBundleDecisions = [NSMutableDictionary dictionary];
        } else {
            NSNumber *cachedDecision = cachedBundleDecisions[bundleID];
            NSDate *decisionTimestamp = cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]];
            
            if (cachedDecision && decisionTimestamp && 
                [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
                return [cachedDecision boolValue];
            }
        }
        
        // Skip spoofing for system apps and critical processes
        if (isCriticalSystemProcess(bundleID)) {
            cachedBundleDecisions[bundleID] = @NO;
            cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
            return NO;
        }
        
        // Check if the current app is a scoped app
        BOOL isScoped = isInScopedAppsList();
        
        // Cache the decision
        cachedBundleDecisions[bundleID] = @(isScoped);
        cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        
        if (isScoped) {
            NSLog(@"[iosversion] iOS Version spoofing enabled for %@", bundleID);
        }
        
        return isScoped;
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in shouldSpoofForBundle: %@", e);
        return NO; // Default to NO for safety
    }
}

// Get the current iOS version information from the profile
static NSDictionary *getIOSVersionInfo() {
    static dispatch_once_t onceToken;
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Check if we have a cached version that's still valid
    if (versionCache && (now - lastVersionLoad < VERSION_CACHE_VALID_PERIOD)) {
        return versionCache;
    }
    
    // Read version info directly from device_ids.plist (source of truth)
    NSString *formattedVersion = nil;
    NSDictionary *deviceIds = nil;

    NSArray *possibleProfilePaths = @[
        @"/var/mobile/Library/WeaponX/Profiles",
        @"/private/var/mobile/Library/WeaponX/Profiles",
        @"/var/mobile/Library/WeaponX/Profiles"
    ];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *profileBasePath in possibleProfilePaths) {
        if ([fileManager fileExistsAtPath:profileBasePath]) {
            NSString *currentProfileInfoPath = [profileBasePath stringByAppendingPathComponent:@"current_profile_info.plist"];
            NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:currentProfileInfoPath];
            NSString *profileId = currentProfileInfo[@"ProfileId"];
            if (profileId) {
                NSString *identityDir = [[profileBasePath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                if (deviceIds.count > 0) {
                    formattedVersion = deviceIds[@"IOSVersion"];
                    break;
                }
            }
        }
    }

    if (deviceIds.count > 0) {
        NSString *version = nil;
        NSString *build = deviceIds[@"IOSBuild"];
        if ([formattedVersion isKindOfClass:[NSString class]] && [formattedVersion containsString:@"("]) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9.]+)\\s*\\(([^)]+)\\)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:formattedVersion options:0 range:NSMakeRange(0, formattedVersion.length)];
            if (match && match.numberOfRanges == 3) {
                version = [formattedVersion substringWithRange:[match rangeAtIndex:1]];
                if (!build.length) {
                    build = [formattedVersion substringWithRange:[match rangeAtIndex:2]];
                }
            }
        }
        if (!version.length && [formattedVersion isKindOfClass:[NSString class]] && formattedVersion.length > 0) {
            version = formattedVersion;
        }

        NSString *darwin = deviceIds[@"Darwin"];
        NSString *xnu = deviceIds[@"XNU"];
        NSString *kernel = deviceIds[@"KernelVersion"];

        if (version.length && build.length && darwin.length && xnu.length && kernel.length) {
            NSDictionary *versionInfo = @{
                @"version": version,
                @"build": build,
                @"darwin": darwin,
                @"xnu": xnu,
                @"kernel_version": kernel
            };

            versionCache = [versionInfo copy];
            lastVersionLoad = now;

            dispatch_once(&onceToken, ^{
                IOSVERSION_LOG(@"Using iOS version from device_ids: %@ (%@)", version, build);
            });

            return versionCache;
        }

        IOSVERSION_LOG(@"❌ device_ids.plist missing required iOS fields (version/build/darwin/xnu/kernel)");
    }

    // Fallback to IOSVersionInfo current (no synthetic generation)
    NSDictionary *current = [[IOSVersionInfo sharedManager] currentIOSVersionInfo];
    if (current && current[@"version"] && current[@"build"] && current[@"darwin"] && current[@"xnu"] && current[@"kernel_version"]) {
        versionCache = [current copy];
        lastVersionLoad = now;
        return versionCache;
    }

    return nil;
}

// Extract just the version number from the full version info
static NSString *getSpoofedSystemVersion() {
    NSDictionary *versionInfo = getIOSVersionInfo();
    return versionInfo ? versionInfo[@"version"] : nil;
}

// Convert version string to NSOperatingSystemVersion struct
static NSOperatingSystemVersion getOperatingSystemVersion(NSString *versionString) {
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    
    NSInteger majorVersion = components.count > 0 ? [components[0] integerValue] : 0;
    NSInteger minorVersion = components.count > 1 ? [components[1] integerValue] : 0;
    NSInteger patchVersion = components.count > 2 ? [components[2] integerValue] : 0;
    
    return (NSOperatingSystemVersion){majorVersion, minorVersion, patchVersion};
}

static BOOL PXHostMatchesSuffix(NSString *host, NSString *suffix) {
    if (![host isKindOfClass:[NSString class]] || !host.length) return NO;
    if (![suffix isKindOfClass:[NSString class]] || !suffix.length) return NO;
    NSString *h = [host lowercaseString];
    NSString *s = [suffix lowercaseString];
    if ([h isEqualToString:s]) return YES;
    return [h hasSuffix:[@"." stringByAppendingString:s]];
}

static BOOL PXIsSensitiveAuthHost(NSString *host) {
    // Allow login flows to work even when Safari/Auth stack spoof is enabled.
    // These domains are particularly sensitive to UA tampering.
    if (!host.length) return NO;
    return PXHostMatchesSuffix(host, @"google.com") ||
           PXHostMatchesSuffix(host, @"accounts.google.com") ||
           PXHostMatchesSuffix(host, @"gstatic.com") ||
           PXHostMatchesSuffix(host, @"googleusercontent.com") ||
           PXHostMatchesSuffix(host, @"recaptcha.net");
}

// ---- UA Debug Toggles (runtime, plist-driven) ----
// Stored in com.weaponx.securitySettings.plist (same file as other settings)

typedef struct {
    BOOL masterEnabled;
    BOOL traceEnabled;

    BOOL scopeSafari;
    BOOL scopeSafariViewService;
    BOOL scopeWebKit;

    BOOL hook_allowedTopLevelWebView;
    BOOL hook_init;
    BOOL hook_setCustomUserAgent;
    BOOL hook_evaluateJavaScript;
    BOOL hook_appNameUA;
    BOOL hook_requestHeaderUA;
    BOOL hook_sfUserAgentWithDomain;
    BOOL hook_sfDefaultUA;

    BOOL sensitiveHostExemptionsEnabled;
} PXUADebugSettings;

static PXUADebugSettings gUADebug;
static BOOL gUADebugValid = NO;
static NSTimeInterval gUADebugLastRead = 0;

static void PXUADebugInvalidate(void) {
    gUADebugValid = NO;
}

static NSDictionary *PXReadSecuritySettingsDict(void) {
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
        @"/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist"
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if ([d isKindOfClass:[NSDictionary class]]) return d;
    }
    return nil;
}

static id PXSecuritySettingObject(NSString *key) {
    NSDictionary *d = PXReadSecuritySettingsDict();
    if ([d isKindOfClass:[NSDictionary class]] && d[key] != nil) {
        return d[key];
    }
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    return [ud objectForKey:key];
}

static BOOL PXSecuritySettingBoolDefault(NSString *key, BOOL def) {
    id v = PXSecuritySettingObject(key);
    return v ? [v boolValue] : def;
}

static void PXUADebugEnsure(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gUADebugValid && (now - gUADebugLastRead) < 1.0) {
        return;
    }
    gUADebugLastRead = now;

    // Default: master OFF (no behavior change)
    BOOL master = PXSecuritySettingBoolDefault(@"debugSafariUAMasterEnabled", NO);
    gUADebug.masterEnabled = master;
    gUADebug.traceEnabled = PXSecuritySettingBoolDefault(@"debugSafariUATraceEnabled", NO);

    // Defaults when master ON: everything enabled
    gUADebug.scopeSafari = PXSecuritySettingBoolDefault(@"debugSafariUAScope_applySafari", YES);
    gUADebug.scopeSafariViewService = PXSecuritySettingBoolDefault(@"debugSafariUAScope_applySafariViewService", YES);
    gUADebug.scopeWebKit = PXSecuritySettingBoolDefault(@"debugSafariUAScope_applyWebKit", YES);

    gUADebug.hook_allowedTopLevelWebView = PXSecuritySettingBoolDefault(@"debugSafariUA_WKWebView_allowedTopLevelWebView", YES);
    gUADebug.hook_init = PXSecuritySettingBoolDefault(@"debugSafariUA_WKWebView_init", YES);
    gUADebug.hook_setCustomUserAgent = PXSecuritySettingBoolDefault(@"debugSafariUA_WKWebView_setCustomUserAgent", YES);
    gUADebug.hook_evaluateJavaScript = PXSecuritySettingBoolDefault(@"debugSafariUA_WKWebView_evaluateJavaScript", YES);
    gUADebug.hook_appNameUA = PXSecuritySettingBoolDefault(@"debugSafariUA_WKWebViewConfiguration_appNameUA", YES);
    gUADebug.hook_requestHeaderUA = PXSecuritySettingBoolDefault(@"debugSafariUA_NSURLRequest_setHeaderUA", YES);
    gUADebug.hook_sfUserAgentWithDomain = PXSecuritySettingBoolDefault(@"debugSafariUA_SFUserAgentController_userAgentWithDomain", YES);
    gUADebug.hook_sfDefaultUA = PXSecuritySettingBoolDefault(@"debugSafariUA_SFUserAgentController_defaultUA", YES);

    // Defaults: exemptions ON
    gUADebug.sensitiveHostExemptionsEnabled = PXSecuritySettingBoolDefault(@"debugSafariUA_SensitiveHostExemptionsEnabled", YES);

    gUADebugValid = YES;
}

static BOOL PXUADebugMasterEnabled(void) {
    PXUADebugEnsure();
    return gUADebug.masterEnabled;
}

static BOOL PXUADebugTraceEnabled(void) {
    PXUADebugEnsure();
    return gUADebug.traceEnabled;
}

// Whether to spoof the UA Mobile/<build> token. Default OFF.
// On older iOS/WebKit builds, changing the Mobile build token can create an impossible UA
// and break sensitive sites (e.g. Google login flows).
static BOOL gUAMobileBuildCached = NO;
static BOOL gUAMobileBuildValid = NO;
static NSTimeInterval gUAMobileBuildLastRead = 0;

static BOOL PXUAShouldSpoofMobileBuildToken(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gUAMobileBuildValid && (now - gUAMobileBuildLastRead) < 1.0) {
        return gUAMobileBuildCached;
    }
    gUAMobileBuildLastRead = now;
    gUAMobileBuildCached = PXSecuritySettingBoolDefault(@"uaSpoofMobileBuildEnabled", NO);
    gUAMobileBuildValid = YES;
    return gUAMobileBuildCached;
}

static void PXUAMobileBuildTokenInvalidate(void) {
    gUAMobileBuildValid = NO;
}

static BOOL PXUADebugScopeAllows(NSString *bundleID, NSString *processName) {
    PXUADebugEnsure();
    if (!gUADebug.masterEnabled) return YES;

    BOOL isSafari = [bundleID isEqualToString:@"com.apple.mobilesafari"];
    BOOL isSafariViewService = [bundleID isEqualToString:@"com.apple.SafariViewService"] ||
                               ([processName isKindOfClass:[NSString class]] && [processName containsString:@"SafariViewService"]);
    BOOL isWebKit = ([bundleID hasPrefix:@"com.apple.WebKit"] ||
                     ([processName isKindOfClass:[NSString class]] && [processName containsString:@"WebKit"]));

    if (isSafari) return gUADebug.scopeSafari;
    if (isSafariViewService) return gUADebug.scopeSafariViewService;
    if (isWebKit) return gUADebug.scopeWebKit;
    return YES;
}

static BOOL PXUAHostIsSensitive(NSString *hostOrDomain) {
    if (!hostOrDomain.length) return NO;

    // In Full Spoof Test Mode we intentionally do NOT exempt sensitive hosts.
    // This is used to reproduce failure cases (e.g. Google login breakages) reliably.
    if (PXFullSpoofTestModeEnabled()) {
        return NO;
    }

    PXUADebugEnsure();
    if (gUADebug.masterEnabled && !gUADebug.sensitiveHostExemptionsEnabled) {
        return NO;
    }
    return PXIsSensitiveAuthHost(hostOrDomain);
}

static void PXUADebugTrace(NSString *hookName,
                           NSString *bundleID,
                           NSString *processName,
                           NSString *host,
                           NSString *decision,
                           NSString *reason,
                           NSString *uaBefore,
                           NSString *uaAfter) {
    if (!PXUADebugTraceEnabled()) return;

    // Optional file logging to avoid relying on syslog.
    // Enabled by default when trace is enabled; can be disabled via plist key.
    static dispatch_queue_t logQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("com.hydra.projectx.uadebuglog", DISPATCH_QUEUE_SERIAL);
    });

    BOOL fileLogEnabled = PXSecuritySettingBoolDefault(@"debugSafariUA_LogFileEnabled", YES);
    NSString *logPath = @"/var/mobile/Documents/WeaponX_UADebug.log";
    NSString *h = host.length ? host : @"(nil)";
    NSString *b = bundleID.length ? bundleID : @"(nil)";
    NSString *p = processName.length ? processName : @"(nil)";
    NSString *r = reason.length ? reason : @"";
    NSMutableString *line = [NSMutableString string];
    NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];
    if (uaBefore.length || uaAfter.length) {
        [line appendFormat:@"[%.0f] [UADebug] hook=%@ bid=%@ proc=%@ host=%@ decision=%@ %@ ua='%@' -> '%@'",
         ts, hookName, b, p, h, decision, r, uaBefore ?: @"", uaAfter ?: @""];
    } else {
        [line appendFormat:@"[%.0f] [UADebug] hook=%@ bid=%@ proc=%@ host=%@ decision=%@ %@",
         ts, hookName, b, p, h, decision, r];
    }

    IOSVERSION_LOG(@"%@", line);

    if (fileLogEnabled) {
        dispatch_async(logQueue, ^{
            @autoreleasepool {
                NSFileManager *fm = [NSFileManager defaultManager];
                // Rotate if too large (2MB)
                NSDictionary *attrs = [fm attributesOfItemAtPath:logPath error:nil];
                unsigned long long size = [attrs[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)] ? [attrs[NSFileSize] unsignedLongLongValue] : 0;
                if (size > (2ULL * 1024ULL * 1024ULL)) {
                    NSString *rotated = [logPath stringByAppendingString:@".1"];
                    [fm removeItemAtPath:rotated error:nil];
                    [fm moveItemAtPath:logPath toPath:rotated error:nil];
                }

                if (![fm fileExistsAtPath:logPath]) {
                    [fm createFileAtPath:logPath contents:nil attributes:@{NSFilePosixPermissions: @(0644)}];
                }

                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
                if (!fh) return;
                @try {
                    [fh seekToEndOfFile];
                    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
                    if (d) {
                        [fh writeData:d];
                    }
                } @catch (__unused NSException *e) {
                }
                @try {
                    [fh closeFile];
                } @catch (__unused NSException *e) {
                }
            }
        });
    }
}

// ---- UA Sync Test: keep HTTP header UA and JS UA aligned ----
// Enable via com.weaponx.securitySettings.plist key: uaSyncHeaderAndJS (default NO)
static BOOL gUASyncEnabledCached = NO;
static BOOL gUASyncEnabledValid = NO;
static NSTimeInterval gUASyncEnabledLastRead = 0;

static BOOL PXUASyncHeaderAndJSEnabled(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gUASyncEnabledValid && (now - gUASyncEnabledLastRead) < 1.0) {
        return gUASyncEnabledCached;
    }
    gUASyncEnabledLastRead = now;
    // uaSyncHeaderAndJS: sync both layers when UA is modified
    // uaSyncJSOnlyFromRequests: allow syncing JS UA even if header UA modification is disabled via debug toggle
    BOOL syncBoth = PXSecuritySettingBoolDefault(@"uaSyncHeaderAndJS", NO);
    BOOL syncJSOnly = PXSecuritySettingBoolDefault(@"uaSyncJSOnlyFromRequests", NO);
    gUASyncEnabledCached = (syncBoth || syncJSOnly);
    gUASyncEnabledValid = YES;
    return gUASyncEnabledCached;
}

static void PXUASyncInvalidate(void) {
    gUASyncEnabledValid = NO;
}

static dispatch_queue_t gWKWebViewsQueue;
static NSPointerArray *gWKWebViews; // weak
static NSMutableDictionary<NSString *, NSString *> *gUAByHost;
static NSString *gUASyncLastUA;
static __thread BOOL gUASyncApplying = NO;

static void PXUASyncInitIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gWKWebViewsQueue = dispatch_queue_create("com.hydra.projectx.wkwebviews", DISPATCH_QUEUE_SERIAL);
        gWKWebViews = [NSPointerArray weakObjectsPointerArray];
        gUAByHost = [NSMutableDictionary dictionary];
    });
}

static void PXUASyncRegisterWKWebView(WKWebView *webView) {
    if (!webView) return;
    PXUASyncInitIfNeeded();
    dispatch_async(gWKWebViewsQueue, ^{
        [gWKWebViews addPointer:(__bridge void *)webView];
        [gWKWebViews compact];
    });
}

static void PXUASyncUnregisterWKWebView(WKWebView *webView) {
    if (!webView) return;
    PXUASyncInitIfNeeded();
    dispatch_async(gWKWebViewsQueue, ^{
        for (NSUInteger i = 0; i < gWKWebViews.count; i++) {
            id obj = [gWKWebViews pointerAtIndex:i] ? (__bridge id)[gWKWebViews pointerAtIndex:i] : nil;
            if (obj == webView) {
                [gWKWebViews removePointerAtIndex:i];
                break;
            }
        }
        [gWKWebViews compact];
    });
}

static void PXUASyncRememberHostUA(NSString *host, NSString *ua) {
    if (!host.length || !ua.length) return;
    PXUASyncInitIfNeeded();
    dispatch_async(gWKWebViewsQueue, ^{
        gUAByHost[host.lowercaseString] = ua;
        gUASyncLastUA = ua;
    });
}

static NSString *PXUASyncLookupHostUA(NSString *host) {
    if (!host.length) return nil;
    PXUASyncInitIfNeeded();
    __block NSString *ua = nil;
    dispatch_sync(gWKWebViewsQueue, ^{
        ua = gUAByHost[host.lowercaseString];
    });
    return ua;
}

static void PXUASyncApplyToWebViewsForHost(NSString *host, NSString *ua) {
    if (!host.length || !ua.length) return;
    PXUASyncInitIfNeeded();
    dispatch_async(gWKWebViewsQueue, ^{
        [gWKWebViews compact];

        BOOL applyAll = PXSecuritySettingBoolDefault(@"uaSyncApplyAllWebViews", YES);
        BOOL injectJS = PXSecuritySettingBoolDefault(@"uaSyncInjectJS", YES);

        for (NSUInteger i = 0; i < gWKWebViews.count; i++) {
            WKWebView *wv = [gWKWebViews pointerAtIndex:i] ? (__bridge WKWebView *)[gWKWebViews pointerAtIndex:i] : nil;
            if (!wv) continue;
            NSString *h = wv.URL.host;

            if (!applyAll) {
                if (!h.length) continue;
                if (![h.lowercaseString isEqualToString:host.lowercaseString]) continue;
            }

            // WKWebView APIs must be called on main thread.
            dispatch_async(dispatch_get_main_queue(), ^{
                gUASyncApplying = YES;
                @try {
                    if ([wv respondsToSelector:@selector(setCustomUserAgent:)]) {
                        [wv setCustomUserAgent:ua];
                    }

                    if (injectJS && [wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                        NSString *escaped = [[ua stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                                             stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
                        NSString *js = [NSString stringWithFormat:
                                        @"(function(){try{Object.defineProperty(navigator,'userAgent',{get:function(){return '%@';},configurable:true});}catch(e){}})();",
                                        escaped];
                        [wv evaluateJavaScript:js completionHandler:nil];
                    }
                } @catch (__unused NSException *e) {
                }
                gUASyncApplying = NO;
            });
        }
    });
}

static void PXUASyncApplyLastToWebViewIfNeeded(WKWebView *webView) {
    if (!PXUASyncHeaderAndJSEnabled() || !webView) return;
    PXUASyncInitIfNeeded();
    __block NSString *ua = nil;
    dispatch_sync(gWKWebViewsQueue, ^{
        ua = gUASyncLastUA;
    });
    if (!ua.length) return;

    BOOL injectJS = PXSecuritySettingBoolDefault(@"uaSyncInjectJS", YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        gUASyncApplying = YES;
        @try {
            if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
                [webView setCustomUserAgent:ua];
            }
            if (injectJS && [webView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                NSString *escaped = [[ua stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                                     stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
                NSString *js = [NSString stringWithFormat:
                                @"(function(){try{Object.defineProperty(navigator,'userAgent',{get:function(){return '%@';},configurable:true});}catch(e){}})();",
                                escaped];
                [webView evaluateJavaScript:js completionHandler:nil];
            }
        } @catch (__unused NSException *e) {
        }
        gUASyncApplying = NO;
    });
}

// Helper function to modify a user agent string with the spoofed iOS version
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion) {
    if (!userAgentString || !*userAgentString || !spoofedVersion || !originalVersion) {
        return;
    }
    
    NSString *originalUA = *userAgentString;
    
    // Common patterns to handle:
    // 1. Mobile/15E148 (for older formats)
    // 2. OS 15_4 like Mac (for newer formats)
    // 3. Version/15.4 (for Safari)
    // 4. CPU OS 15_4 (for iPad)
    // 5. Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X)
    // 6. AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15
    
    // Pattern 1: Mobile/15E148
    // Keep the original Mobile/<build> token by default. Spoofing it can break sites.
    NSString *updatedUA = originalUA;
    if (PXUAShouldSpoofMobileBuildToken()) {
        NSRegularExpression *mobileRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mobile)/\\d+[A-Z]\\d+" options:0 error:nil];
        NSString *spoofedBuild = getIOSVersionInfo()[@"build"];
        if (spoofedBuild) {
            updatedUA = [mobileRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1/%@", spoofedBuild]];
        }
    }
    
    // Pattern 2: OS 15_4 like Mac
    NSString *underscoreVersion = [spoofedVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSRegularExpression *osRegex = [NSRegularExpression regularExpressionWithPattern:@"(OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like\\s+Mac)" options:0 error:nil];
    updatedUA = [osRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 3: Version/15.4
    NSRegularExpression *versionRegex = [NSRegularExpression regularExpressionWithPattern:@"(Version/)\\d+\\.\\d+(?:\\.\\d+)?" options:0 error:nil];
    updatedUA = [versionRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@", spoofedVersion]];
    
    // Pattern 4: CPU OS 15_4
    NSRegularExpression *cpuOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [cpuOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 5: CPU iPhone OS 15_4
    NSRegularExpression *iPhoneOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU iPhone OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [iPhoneOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 6: Mozilla/5.0 (iPhone; ... OS X)
    NSRegularExpression *mozillaRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mozilla/5\\.0 \\([^;]+; [^;]+; [^\\s]+\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [mozillaRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    if (![updatedUA isEqualToString:originalUA]) {
        *userAgentString = updatedUA;
        IOSVERSION_LOG(@"Modified UA: %@ → %@", originalUA, updatedUA);
    } else {
        IOSVERSION_LOG(@"Failed to modify UA: %@", originalUA);
    }
}

#pragma mark - UIDevice Hooks

%hook UIDevice

// Hook the systemVersion method to return our spoofed version
- (NSString *)systemVersion {
    @try {
        // Rate limiting - don't call this function too frequently
        uint64_t currentTime = mach_absolute_time();
        if (cachedSystemVersionResult != nil && 
            (currentTime - lastSystemVersionCallTime) < THROTTLE_INTERVAL_NSEC) {
            return cachedSystemVersionResult;
        }
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSString *originalVersion = %orig;
                
                // Only log occasionally to reduce overhead
                if (lastSystemVersionCallTime == 0 || (currentTime - lastSystemVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                    IOSVERSION_LOG(@"UIDevice.systemVersion: %@ → %@", originalVersion, spoofedVersion);
                }
                
                // Update cache and timestamp
                lastSystemVersionCallTime = currentTime;
                cachedSystemVersionResult = spoofedVersion;
                
                return spoofedVersion;
            }
        }
        
        // Cache the original result too
        NSString *originalResult = %orig;
        lastSystemVersionCallTime = currentTime;
        cachedSystemVersionResult = originalResult;
        return originalResult;
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in systemVersion hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - NSProcessInfo Hooks

%hook NSProcessInfo

// Hook operatingSystemVersion to return our spoofed version
- (NSOperatingSystemVersion)operatingSystemVersion {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSOperatingSystemVersion originalVersion = %orig;
                NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
                
                NSLog(@"[iosversion] NSProcessInfo.operatingSystemVersion: %ld.%ld.%ld → %ld.%ld.%ld", 
                      (long)originalVersion.majorVersion, 
                      (long)originalVersion.minorVersion, 
                      (long)originalVersion.patchVersion,
                      (long)spoofedStructVersion.majorVersion, 
                      (long)spoofedStructVersion.minorVersion, 
                      (long)spoofedStructVersion.patchVersion);
                
                return spoofedStructVersion;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in operatingSystemVersion hook: %@", e);
    }
    return %orig;
}

// Hook isOperatingSystemAtLeastVersion to handle our spoofed version
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
                
                // Implement the comparison logic ourselves instead of calling orig
                BOOL result = (spoofedStructVersion.majorVersion > version.majorVersion) ||
                             ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                              (spoofedStructVersion.minorVersion > version.minorVersion)) ||
                             ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                              (spoofedStructVersion.minorVersion == version.minorVersion) && 
                              (spoofedStructVersion.patchVersion >= version.patchVersion));
                
                BOOL originalResult = %orig;
                NSLog(@"[iosversion] NSProcessInfo.isOperatingSystemAtLeastVersion: %ld.%ld.%ld, original: %d → spoofed: %d", 
                      (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion,
                      originalResult, result);
                
                return result;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in isOperatingSystemAtLeastVersion hook: %@", e);
    }
    return %orig;
}

// Additional method to hook for getting raw operating system version string
- (NSString *)operatingSystemVersionString {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (versionInfo && versionInfo[@"version"]) {
                NSString *originalVersion = %orig;
                NSString *spoofedVersion = [NSString stringWithFormat:@"Version %@ (Build %@)", 
                                           versionInfo[@"version"], 
                                           versionInfo[@"build"]];
                
                IOSVERSION_LOG(@"NSProcessInfo.operatingSystemVersionString: %@ → %@", 
                      originalVersion, spoofedVersion);
                      
                return spoofedVersion;
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in operatingSystemVersionString hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - WKWebView User Agent Hooks

// Hook WKWebView to modify the user agent
%hook WKWebView

+ (WKWebView *)_allowedTopLevelWebView:(WKWebView *)webView {
    WKWebView *resultWebView = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"WKWebView._allowedTopLevelWebView", bundleID, proc, resultWebView.URL.host, @"skip", @"reason=scope", nil, nil);
            return resultWebView;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_allowedTopLevelWebView) {
            PXUADebugTrace(@"WKWebView._allowedTopLevelWebView", bundleID, proc, resultWebView.URL.host, @"skip", @"reason=toggle", nil, nil);
            return resultWebView;
        }
        // Special case for Safari/Auth stack processes to force spoofing (even if not scoped)
        BOOL forceSpoofForWebKit = PXSafariStackSpoofEnabled() &&
                                  PXIsSafariStackProcess(bundleID, proc);
         
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && resultWebView) {
            // For Safari/Auth stack, avoid setting a global UA before we know the host.
            // In FullSpoof test mode, we override this to force UA spoofing.
            if (forceSpoofForWebKit && !PXFullSpoofTestModeEnabled()) {
                NSString *host = resultWebView.URL.host;
                if (!host.length || PXUAHostIsSensitive(host)) {
                    PXUADebugTrace(@"WKWebView._allowedTopLevelWebView", bundleID, proc, host, @"skip", @"reason=host", nil, nil);
                    return resultWebView;
                }
            }
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // Get the current user agent
                if ([resultWebView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                    [resultWebView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                        if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                            // Modify the user agent string
                            NSMutableString *modifiedUA = [userAgent mutableCopy];
                            modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                            
                            // Set the new user agent if it changed
                            if (![modifiedUA isEqualToString:userAgent]) {
                                if ([resultWebView respondsToSelector:@selector(setCustomUserAgent:)]) {
                                    PXUADebugTrace(@"WKWebView._allowedTopLevelWebView", bundleID, proc, resultWebView.URL.host, @"modify", @"", userAgent, modifiedUA);
                                    [resultWebView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set modified user agent for WebView in %@", bundleID);
                                }
                            }
                        }
                    }];
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in _allowedTopLevelWebView: %@", e);
    }
    
    return resultWebView;
}

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = %orig;

    // Track instances for UA sync testing.
    if (PXUASyncHeaderAndJSEnabled() && webView) {
        PXUASyncRegisterWKWebView(webView);
        // Best-effort apply most recent UA immediately to reduce header/JS mismatch.
        PXUASyncApplyLastToWebViewIfNeeded(webView);
    }
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"WKWebView.init", bundleID, proc, webView.URL.host, @"skip", @"reason=scope", nil, nil);
            return webView;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_init) {
            PXUADebugTrace(@"WKWebView.init", bundleID, proc, webView.URL.host, @"skip", @"reason=toggle", nil, nil);
            return webView;
        }
        // Special case for Safari/Auth stack processes to force spoofing (even if not scoped)
        BOOL forceSpoofForWebKit = PXSafariStackSpoofEnabled() &&
                                  PXIsSafariStackProcess(bundleID, proc);
         
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && webView) {
            // For Safari/Auth stack, avoid setting a global UA before we know the host.
            // In FullSpoof test mode, we override this to force UA spoofing.
            if (forceSpoofForWebKit && !PXFullSpoofTestModeEnabled()) {
                NSString *host = webView.URL.host;
                if (!host.length || PXUAHostIsSensitive(host)) {
                    PXUADebugTrace(@"WKWebView.init", bundleID, proc, host, @"skip", @"reason=host", nil, nil);
                    return webView;
                }
            }
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // First, if configuration has applicationNameForUserAgent, try to modify it
                if (configuration && [configuration respondsToSelector:@selector(applicationNameForUserAgent)]) {
                    NSString *appName = [configuration applicationNameForUserAgent];
                    if (appName) {
                        NSMutableString *modifiedName = [appName mutableCopy];
                        modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                        
                        if (![modifiedName isEqualToString:appName]) {
                            [configuration setApplicationNameForUserAgent:modifiedName];
                            IOSVERSION_LOG(@"Modified applicationNameForUserAgent: %@ → %@", appName, modifiedName);
                        }
                    }
                }
                
                // Now try to set customUserAgent directly if possible
                if ([webView respondsToSelector:@selector(customUserAgent)] && 
                    [webView respondsToSelector:@selector(setCustomUserAgent:)]) {
                    
                    // Try to get existing customUserAgent first
                NSString *currentUserAgent = [webView customUserAgent];
                if (currentUserAgent) {
                    NSMutableString *modifiedUA = [currentUserAgent mutableCopy];
                    modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                    
                    if (![modifiedUA isEqualToString:currentUserAgent]) {
                        [webView setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Set custom user agent on init: %@ → %@", currentUserAgent, modifiedUA);
                        }
                    } else {
                        // If no custom user agent yet, we need to get the default one and modify it
                        [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                            if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                                NSMutableString *modifiedUA = [userAgent mutableCopy];
                                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                                
                                if (![modifiedUA isEqualToString:userAgent]) {
                                    PXUADebugTrace(@"WKWebView.init", bundleID, proc, webView.URL.host, @"modify", @"", userAgent, modifiedUA);
                                    [webView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set custom user agent from default: %@ → %@", userAgent, modifiedUA);
                                }
                            }
                        }];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in initWithFrame: %@", e);
    }
    
    return webView;
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    // UA sync test: if we are applying from our own sync path, pass through.
    if (gUASyncApplying) {
        %orig;
        return;
    }

    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"WKWebView.setCustomUserAgent", bundleID, proc, self.URL.host, @"skip", @"reason=scope", customUserAgent, nil);
            %orig;
            return;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_setCustomUserAgent) {
            PXUADebugTrace(@"WKWebView.setCustomUserAgent", bundleID, proc, self.URL.host, @"skip", @"reason=toggle", customUserAgent, nil);
            %orig;
            return;
        }
        // Special case for Safari/Auth stack processes to force spoofing (even if not scoped)
        BOOL forceSpoofForWebKit = PXSafariStackSpoofEnabled() &&
                                  PXIsSafariStackProcess(bundleID, proc);
         
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && customUserAgent) {
            if (forceSpoofForWebKit && !PXFullSpoofTestModeEnabled()) {
                NSString *host = self.URL.host;
                if (!host.length || PXUAHostIsSensitive(host)) {
                    PXUADebugTrace(@"WKWebView.setCustomUserAgent", bundleID, proc, host, @"skip", @"reason=host", customUserAgent, nil);
                    %orig;
                    return;
                }
            }
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedUA = [customUserAgent mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:customUserAgent]) {
                    PXUADebugTrace(@"WKWebView.setCustomUserAgent", bundleID, proc, self.URL.host, @"modify", @"", customUserAgent, modifiedUA);
                    IOSVERSION_LOG(@"Setting modified custom UA: %@ → %@", customUserAgent, modifiedUA);
                    %orig(modifiedUA);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in setCustomUserAgent: %@", e);
    }
    
    %orig;
}

// Add hooks for common JavaScript evaluation methods to modify user agent when detected
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(id)completionHandler {
    // Check if this is a user agent detection script
    BOOL isUserAgentScript = [javaScriptString containsString:@"navigator.userAgent"];
    
    // Let the original method run first
    %orig;
    
    // If it's a user agent script, try to update the user agent
    if (isUserAgentScript) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"WKWebView.evaluateJavaScript", bundleID, proc, self.URL.host, @"skip", @"reason=scope", nil, nil);
            return;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_evaluateJavaScript) {
            PXUADebugTrace(@"WKWebView.evaluateJavaScript", bundleID, proc, self.URL.host, @"skip", @"reason=toggle", nil, nil);
            return;
        }
        // Special case for Safari/Auth stack processes to force spoofing (even if not scoped)
        BOOL forceSpoofForWebKit = PXSafariStackSpoofEnabled() &&
                                  PXIsSafariStackProcess(bundleID, proc);
        
        if (forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) {
            // For Safari/Auth stack, only touch UA when host is known and not sensitive.
            // In FullSpoof test mode, we override this to force UA spoofing.
            NSString *host = self.URL.host;
            if (!PXFullSpoofTestModeEnabled()) {
                if (forceSpoofForWebKit) {
                    if (!host.length || PXUAHostIsSensitive(host)) {
                        PXUADebugTrace(@"WKWebView.evaluateJavaScript", bundleID, proc, host, @"skip", @"reason=host", nil, nil);
                        return;
                    }
                } else {
                    if (PXUAHostIsSensitive(host)) {
                        PXUADebugTrace(@"WKWebView.evaluateJavaScript", bundleID, proc, host, @"skip", @"reason=sensitive", nil, nil);
                        return;
                    }
                }
            }
            // Wait a short time to let the script execute
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *spoofedVersion = getSpoofedSystemVersion();
                NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
                
                if (spoofedVersion && [self respondsToSelector:@selector(customUserAgent)]) {
                    NSString *currentUA = [self customUserAgent];
                    if (currentUA) {
                        NSMutableString *modifiedUA = [currentUA mutableCopy];
                        modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                        
                        if (![modifiedUA isEqualToString:currentUA]) {
                            PXUADebugTrace(@"WKWebView.evaluateJavaScript", bundleID, proc, self.URL.host, @"modify", @"", currentUA, modifiedUA);
                            [self setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Updated UA after JS evaluation: %@ → %@", currentUA, modifiedUA);
                        }
                    }
                }
            });
        }
    }
}

%end

#pragma mark - WKWebViewConfiguration Hooks

%hook WKWebViewConfiguration

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"WKWebViewConfiguration.setApplicationNameForUserAgent", bundleID, proc, nil, @"skip", @"reason=scope", applicationNameForUserAgent, nil);
            %orig;
            return;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_appNameUA) {
            PXUADebugTrace(@"WKWebViewConfiguration.setApplicationNameForUserAgent", bundleID, proc, nil, @"skip", @"reason=toggle", applicationNameForUserAgent, nil);
            %orig;
            return;
        }
        // Don't mutate UA at configuration time for Safari/Auth stack; host is unknown here.
        // In FullSpoof test mode we allow this to force UA spoofing.
        BOOL forceSpoofForWebKit = PXSafariStackSpoofEnabled() &&
                                  PXIsSafariStackProcess(bundleID, proc);
        if (forceSpoofForWebKit && !PXFullSpoofTestModeEnabled()) {
            PXUADebugTrace(@"WKWebViewConfiguration.setApplicationNameForUserAgent", bundleID, proc, nil, @"skip", @"reason=safaristack", applicationNameForUserAgent, nil);
            %orig;
            return;
        }

        if (shouldSpoofForBundle(bundleID) && applicationNameForUserAgent) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedName = [applicationNameForUserAgent mutableCopy];
                modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                
                if (![modifiedName isEqualToString:applicationNameForUserAgent]) {
                    PXUADebugTrace(@"WKWebViewConfiguration.setApplicationNameForUserAgent", bundleID, proc, nil, @"modify", @"", applicationNameForUserAgent, modifiedName);
                    %orig(modifiedName);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - NSURLRequest User-Agent Hooks

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    @try {
        if ([field isEqualToString:@"User-Agent"] && value) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            NSString *proc = [NSProcessInfo processInfo].processName;
            if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
                PXUADebugTrace(@"NSMutableURLRequest.setValue(User-Agent)", bundleID, proc, self.URL.host, @"skip", @"reason=scope", value, nil);
                %orig;
                return;
            }
            BOOL headerModifyEnabled = !(PXUADebugMasterEnabled() && !gUADebug.hook_requestHeaderUA);
            BOOL syncEnabled = PXUASyncHeaderAndJSEnabled();
            if (!headerModifyEnabled && !syncEnabled) {
                PXUADebugTrace(@"NSMutableURLRequest.setValue(User-Agent)", bundleID, proc, self.URL.host, @"skip", @"reason=toggle", value, nil);
                %orig;
                return;
            }
            if (shouldSpoofForBundle(bundleID)) {
                NSString *host = self.URL.host;
                if (PXUAHostIsSensitive(host)) {
                    PXUADebugTrace(@"NSMutableURLRequest.setValue(User-Agent)", bundleID, proc, host, @"skip", @"reason=sensitive", value, nil);
                    %orig;
                    return;
                }
                NSString *spoofedVersion = getSpoofedSystemVersion();
                NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
                
                if (spoofedVersion) {
                    NSMutableString *modifiedValue = [value mutableCopy];
                    modifyUserAgentString(&modifiedValue, originalVersion, spoofedVersion);
                    
                    if (![modifiedValue isEqualToString:value]) {
                        // If syncing is enabled, always push the UA into JS layer (customUserAgent + optional JS patch)
                        // even when header UA modification is disabled (for mismatch testing).
                        if (syncEnabled && host.length) {
                            PXUASyncRememberHostUA(host, modifiedValue);
                            PXUASyncApplyToWebViewsForHost(host, modifiedValue);
                            PXUADebugTrace(@"UASync.remember", bundleID, proc, host, @"modify", headerModifyEnabled ? @"" : @"reason=jsOnly", value, modifiedValue);
                        }

                        if (headerModifyEnabled) {
                            PXUADebugTrace(@"NSMutableURLRequest.setValue(User-Agent)", bundleID, proc, host, @"modify", @"", value, modifiedValue);
                            %orig(modifiedValue, field);
                            return;
                        }

                        // Header disabled: keep original header, only sync JS.
                        PXUADebugTrace(@"NSMutableURLRequest.setValue(User-Agent)", bundleID, proc, host, @"skip", @"reason=jsOnly", value, modifiedValue);
                        %orig;
                        return;
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - Safari Specific Hooks

// Hook Safari's SFUserAgentController to modify the user agent string
%hook SFUserAgentController

+ (NSString *)userAgentWithDomain:(NSString *)domain {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"SFUserAgentController.userAgentWithDomain", bundleID, proc, domain, @"skip", @"reason=scope", originalUA, nil);
            return originalUA;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_sfUserAgentWithDomain) {
            PXUADebugTrace(@"SFUserAgentController.userAgentWithDomain", bundleID, proc, domain, @"skip", @"reason=toggle", originalUA, nil);
            return originalUA;
        }
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            if (PXUAHostIsSensitive(domain)) {
                PXUADebugTrace(@"SFUserAgentController.userAgentWithDomain", bundleID, proc, domain, @"skip", @"reason=sensitive", originalUA, nil);
                return originalUA;
            }
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    PXUADebugTrace(@"SFUserAgentController.userAgentWithDomain", bundleID, proc, domain, @"modify", @"", originalUA, modifiedUA);
                    IOSVERSION_LOG(@"Safari: Modified user agent for domain %@", domain);
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari user agent: %@", e);
    }
    
    return originalUA;
}

+ (NSString *)defaultUserAgentString {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *proc = [NSProcessInfo processInfo].processName;
        if (PXUADebugMasterEnabled() && !PXUADebugScopeAllows(bundleID, proc)) {
            PXUADebugTrace(@"SFUserAgentController.defaultUserAgentString", bundleID, proc, nil, @"skip", @"reason=scope", originalUA, nil);
            return originalUA;
        }
        if (PXUADebugMasterEnabled() && !gUADebug.hook_sfDefaultUA) {
            PXUADebugTrace(@"SFUserAgentController.defaultUserAgentString", bundleID, proc, nil, @"skip", @"reason=toggle", originalUA, nil);
            return originalUA;
        }
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            // Avoid global UA changes for Safari; per-request/domain hooks handle spoofing.
            // In FullSpoof test mode, allow default UA mutation to force failures.
            if (PXSafariStackSpoofEnabled() && !PXFullSpoofTestModeEnabled()) {
                PXUADebugTrace(@"SFUserAgentController.defaultUserAgentString", bundleID, proc, nil, @"skip", @"reason=safaristack", originalUA, nil);
                return originalUA;
            }
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    PXUADebugTrace(@"SFUserAgentController.defaultUserAgentString", bundleID, proc, nil, @"modify", @"", originalUA, modifiedUA);
                    IOSVERSION_LOG(@"Safari: Modified default user agent");
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari default user agent: %@", e);
    }
    
    return originalUA;
}

%end

#pragma mark - CoreFoundation Version Dictionary Hook

// Hook CFCopySystemVersionDictionary to spoof iOS version information at the CoreFoundation level
static CFDictionaryRef (*original_CFCopySystemVersionDictionary)(void);
CFDictionaryRef replaced_CFCopySystemVersionDictionary(void) {
    @try {
        // Rate limiting to prevent excessive calls
        uint64_t currentTime = mach_absolute_time();
        if (cachedDictResult != NULL && 
            (currentTime - lastDictCallTime) < THROTTLE_INTERVAL_NSEC) {
            // Return cached result to reduce CPU usage
            return CFRetain(cachedDictResult);
        }
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Create a fallback dictionary if original function is NULL
            CFDictionaryRef originalDict = NULL;
            BOOL usingFallback = NO;
            
            if (original_CFCopySystemVersionDictionary) {
                originalDict = original_CFCopySystemVersionDictionary();
            } else {
                // Create a basic dictionary with current system version
                NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
                CFStringRef versionKey = CFSTR("ProductVersion");
                CFStringRef buildKey = CFSTR("ProductBuildVersion");
                
                // Use a default build number based on version
                NSString *actualBuild = [NSString stringWithFormat:@"%@000", [actualVersion stringByReplacingOccurrencesOfString:@"." withString:@""]];
                
                CFStringRef versionValue = CFStringCreateWithCString(NULL, [actualVersion UTF8String], kCFStringEncodingUTF8);
                CFStringRef buildValue = CFStringCreateWithCString(NULL, [actualBuild UTF8String], kCFStringEncodingUTF8);
                
                CFMutableDictionaryRef fallbackDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                
                if (fallbackDict && versionValue && buildValue) {
                    CFDictionarySetValue(fallbackDict, versionKey, versionValue);
                    CFDictionarySetValue(fallbackDict, buildKey, buildValue);
                    
                    CFRelease(versionValue);
                    CFRelease(buildValue);
                    
                    originalDict = fallbackDict;
                    usingFallback = YES;
                    
                    IOSVERSION_LOG(@"📝 Created fallback dictionary for CFCopySystemVersionDictionary");
                }
            }
            
            if (!originalDict) {
                IOSVERSION_LOG(@"⚠️ Failed to get system version dictionary");
                return NULL;
            }
            
            // Get spoofed version info
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (!versionInfo || !versionInfo[@"version"] || !versionInfo[@"build"]) {
                IOSVERSION_LOG(@"⚠️ Missing version info for CFCopySystemVersionDictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            NSString *spoofedVersion = versionInfo[@"version"];
            NSString *spoofedBuild = versionInfo[@"build"];
            
            // Log original values only occasionally to reduce overhead
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                CFStringRef origVersionKey = CFSTR("ProductVersion");
                CFStringRef origBuildKey = CFSTR("ProductBuildVersion");
                CFStringRef origVersionValue = CFDictionaryGetValue(originalDict, origVersionKey);
                CFStringRef origBuildValue = CFDictionaryGetValue(originalDict, origBuildKey);
                
                if (origVersionValue && origBuildValue) {
                    IOSVERSION_LOG(@"🔍 CFCopySystemVersionDictionary original: version=%@ build=%@", 
                          (__bridge NSString *)origVersionValue,
                          (__bridge NSString *)origBuildValue);
                }
            }
            
            // Create mutable copy to modify
            CFMutableDictionaryRef mutableDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, originalDict);
            if (!mutableDict) {
                IOSVERSION_LOG(@"⚠️ Failed to create mutable copy of system version dictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            // Update version and build number
            CFStringRef versionKey = CFSTR("ProductVersion");
            CFStringRef buildKey = CFSTR("ProductBuildVersion");
            
            CFStringRef versionValue = CFStringCreateWithCString(NULL, [spoofedVersion UTF8String], kCFStringEncodingUTF8);
            CFStringRef buildValue = CFStringCreateWithCString(NULL, [spoofedBuild UTF8String], kCFStringEncodingUTF8);
            
            if (versionValue) {
                CFDictionarySetValue(mutableDict, versionKey, versionValue);
                CFRelease(versionValue);
            }
            
            if (buildValue) {
                CFDictionarySetValue(mutableDict, buildKey, buildValue);
                CFRelease(buildValue);
            }
            
            // Log the newly set values only occasionally
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                IOSVERSION_LOG(@"✅ CFCopySystemVersionDictionary spoofed: version=%@ build=%@", 
                      spoofedVersion, spoofedBuild);
            }
            
            // Release the original dictionary since we're returning a new one
            if (!usingFallback) {
                CFRelease(originalDict);
            }
            
            // Cache the result and update timestamp
            if (cachedDictResult != NULL) {
                CFRelease(cachedDictResult);
            }
            cachedDictResult = CFRetain(mutableDict);
            lastDictCallTime = currentTime;
            
            return mutableDict;
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in CFCopySystemVersionDictionary hook: %@", e);
    }
    
    // Call original function or return NULL if it's not available
    CFDictionaryRef result = original_CFCopySystemVersionDictionary ? original_CFCopySystemVersionDictionary() : NULL;
    
    // Update cache
    if (result) {
        if (cachedDictResult != NULL) {
            CFRelease(cachedDictResult);
        }
        cachedDictResult = CFRetain(result);
        lastDictCallTime = mach_absolute_time();
    }
    
    return result;
}

#pragma mark - sysctlbyname Hook

// Hook sysctlbyname to spoof iOS kernel version information
int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Store last call time and cached result for the common kernel version calls
    static uint64_t lastOsVersionCallTime = 0;
    static char cachedBuildStr[32] = {0}; // Cache the build string
    static size_t cachedBuildStrLen = 0;
    
    // For kern.version - full Darwin kernel version string
    static uint64_t lastKernVersionCallTime = 0;
    static char cachedKernelVersionStr[256] = {0}; // Cache the kernel version string
    static size_t cachedKernelVersionStrLen = 0;
    
    @try {
        // Pre-cache version info only once
        static NSDictionary *cachedVersionInfo = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cachedVersionInfo = getIOSVersionInfo();
            if (cachedVersionInfo) {
                // Extract build number and cache it
                NSString *buildNumber = cachedVersionInfo[@"build"];
                if (buildNumber) {
                    strlcpy(cachedBuildStr, [buildNumber UTF8String], sizeof(cachedBuildStr));
                    cachedBuildStrLen = strlen(cachedBuildStr) + 1; // +1 for null terminator
                }
                
                // Extract kernel version string and cache it
                NSString *kernelVersion = cachedVersionInfo[@"kernel_version"];
                if (kernelVersion) {
                    strlcpy(cachedKernelVersionStr, [kernelVersion UTF8String], sizeof(cachedKernelVersionStr));
                    cachedKernelVersionStrLen = strlen(cachedKernelVersionStr) + 1; // +1 for null terminator
                }
                
                IOSVERSION_LOG(@"🔄 Pre-cached version info: %@ (%@), kernel: %@", 
                      cachedVersionInfo[@"version"], 
                      cachedVersionInfo[@"build"],
                      cachedVersionInfo[@"kernel_version"]);
            } else {
                IOSVERSION_LOG(@"⚠️ Failed to pre-cache version info");
            }
        });

        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Check if this is a request for full kernel version string
            if (name && strcmp(name, "kern.version") == 0) {
                uint64_t currentTime = mach_absolute_time();
                
                // Ensure we have a valid cached kernel version string
                if (cachedKernelVersionStrLen == 0 && cachedVersionInfo && cachedVersionInfo[@"kernel_version"]) {
                    NSString *kernelVersion = cachedVersionInfo[@"kernel_version"];
                    strlcpy(cachedKernelVersionStr, [kernelVersion UTF8String], sizeof(cachedKernelVersionStr));
                    cachedKernelVersionStrLen = strlen(cachedKernelVersionStr) + 1;
                }
                
                // If we have a valid cached kernel version string
                if (cachedKernelVersionStrLen > 0) {
                    // Check if this is just a length query (oldp is NULL but oldlenp is not)
                    if (!oldp && oldlenp) {
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"ℹ️ Returning required buffer size for kern.version: %zu", cachedKernelVersionStrLen);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0;
                    }
                    
                    // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                    if (oldp && oldlenp && *oldlenp >= cachedKernelVersionStrLen) {
                        memcpy(oldp, cachedKernelVersionStr, cachedKernelVersionStrLen);
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed kern.version to %s", cachedKernelVersionStr);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"⚠️ Buffer too small for kern.version (%zu < %zu)", *oldlenp, cachedKernelVersionStrLen);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0; // Success (caller will need to provide a bigger buffer)
                    }
                } else {
                    IOSVERSION_LOG(@"❌ Missing cached kernel version string");
                }
            }
            // Check if this is a request for Darwin version number (kern.osrelease)
            else if (name && strcmp(name, "kern.osrelease") == 0 && cachedVersionInfo && cachedVersionInfo[@"darwin"]) {
                uint64_t currentTime = mach_absolute_time();
                
                // Get Darwin version (format: "21.6.0")
                NSString *darwinVersion = cachedVersionInfo[@"darwin"];
                if (darwinVersion) {
                    const char *darwinVersionStr = [darwinVersion UTF8String];
                    size_t darwinVersionLen = strlen(darwinVersionStr) + 1; // +1 for null terminator
                    
                    // Check if this is just a length query
                    if (!oldp && oldlenp) {
                        *oldlenp = darwinVersionLen;
                        return 0;
                    }
                    
                    // Copy the version if buffer is big enough
                    if (oldp && oldlenp && *oldlenp >= darwinVersionLen) {
                        memcpy(oldp, darwinVersionStr, darwinVersionLen);
                        *oldlenp = darwinVersionLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed kern.osrelease to %s", darwinVersionStr);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = darwinVersionLen;
                        return 0;
                    }
                }
            }
            // Check if this is a request for iOS version information
            else if (name && (strcmp(name, "kern.osversion") == 0)) {
                // Rate limiting - don't process too many calls
                uint64_t currentTime = mach_absolute_time();
                
                // Ensure we have a valid cached build string
                if (cachedBuildStrLen == 0 && cachedVersionInfo && cachedVersionInfo[@"build"]) {
                    NSString *buildNumber = cachedVersionInfo[@"build"];
                    strlcpy(cachedBuildStr, [buildNumber UTF8String], sizeof(cachedBuildStr));
                    cachedBuildStrLen = strlen(cachedBuildStr) + 1;
                }
                
                // Skip processing if we have a valid cached build and not enough time has passed
                if (cachedBuildStrLen > 0) {
                    // Check if this is just a length query (oldp is NULL but oldlenp is not)
                    if (!oldp && oldlenp) {
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"ℹ️ Returning required buffer size: %zu", cachedBuildStrLen);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0;
                    }
                    
                    // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                    if (oldp && oldlenp && *oldlenp >= cachedBuildStrLen) {
                        memcpy(oldp, cachedBuildStr, cachedBuildStrLen);
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed sysctlbyname to %s", cachedBuildStr);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"⚠️ Buffer too small for sysctlbyname (%zu < %zu)", *oldlenp, cachedBuildStrLen);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success (caller will need to provide a bigger buffer)
                    }
                } else {
                    IOSVERSION_LOG(@"❌ Missing cached build number");
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in sysctlbyname hook: %@", e);
    }
    
    // Call the original function for all other cases
    return original_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - Bundle Version Hooks

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    @try {
        NSString *bundleID = [self bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Handle system version info in Info.plist queries
            if ([key isEqualToString:@"MinimumOSVersion"] || 
                [key isEqualToString:@"DTPlatformVersion"] ||
                [key isEqualToString:@"DTSDKName"]) {
                
                NSString *spoofedVersion = getSpoofedSystemVersion();
                if (spoofedVersion) {
                    // For SDK and platform keys, add iOS prefix if needed
                    if ([key isEqualToString:@"DTPlatformVersion"] || 
                        [key isEqualToString:@"DTSDKName"]) {
                        if (![spoofedVersion hasPrefix:@"iOS"]) {
                            return [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                        }
                        return spoofedVersion;
                    }
                    return spoofedVersion;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    return %orig;
}

%end

// Original function pointer for CFBundleGetValueForInfoDictionaryKey
static CFTypeRef (*original_CFBundleGetValueForInfoDictionaryKey)(CFBundleRef bundle, CFStringRef key);

// Replacement function for CFBundleGetValueForInfoDictionaryKey
CFTypeRef replaced_CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    @try {
        if (!bundle || !key) return NULL;
        
        // Get the bundle ID for CFBundle
        CFStringRef bundleID = CFBundleGetIdentifier(bundle);
        NSString *nsBundleID = bundleID ? (__bridge NSString*)bundleID : nil;
        
        if (shouldSpoofForBundle(nsBundleID)) {
            // Check for system version keys
            if (CFEqual(key, CFSTR("MinimumOSVersion")) || 
                CFEqual(key, CFSTR("DTPlatformVersion")) ||
                CFEqual(key, CFSTR("DTSDKName"))) {
                
                NSString *spoofedVersion = getSpoofedSystemVersion();
                if (spoofedVersion) {
                    // Log what we're spoofing
                    NSLog(@"[iosversion] 💉 Spoofing %@ for bundle %@ to %@", 
                          (__bridge NSString*)key, nsBundleID, spoofedVersion);
                    
                    // Create a CFString from our spoofed version
                    if (CFEqual(key, CFSTR("DTPlatformVersion")) || 
                        CFEqual(key, CFSTR("DTSDKName"))) {
                        
                        if (![spoofedVersion hasPrefix:@"iOS"]) {
                            NSString *prefixedVersion = [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                            return CFStringCreateWithCString(NULL, [prefixedVersion UTF8String], kCFStringEncodingUTF8);
                        }
                    }
                    
                    return CFStringCreateWithCString(NULL, [spoofedVersion UTF8String], kCFStringEncodingUTF8);
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] ❌ Error in CFBundleGetValueForInfoDictionaryKey hook: %@", e);
    }
    
    // Call original function if available, otherwise return NULL
    if (original_CFBundleGetValueForInfoDictionaryKey) {
        return original_CFBundleGetValueForInfoDictionaryKey(bundle, key);
    } else {
        // For some keys, provide default values
        if (key && (CFEqual(key, CFSTR("MinimumOSVersion")))) {
            // Return the current device's actual iOS version for MinimumOSVersion
            NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
            return CFStringCreateWithCString(NULL, [actualVersion UTF8String], kCFStringEncodingUTF8);
        }
        
        NSLog(@"[iosversion] ℹ️ No original function for CFBundleGetValueForInfoDictionaryKey, returning NULL");
        return NULL;
    }
}

#pragma mark - Notification Handling

// Settings changed notification handler
static void settingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cached decisions
    if (cachedBundleDecisions) {
        [cachedBundleDecisions removeAllObjects];
    }
    
    // Clear version cache
    versionCache = nil;
    lastVersionLoad = 0;

    // Clear UA debug cache (runtime toggles)
    PXUADebugInvalidate();

    // Clear UA Mobile/<build> toggle cache
    PXUAMobileBuildTokenInvalidate();

    // Clear UA sync toggle cache
    PXUASyncInvalidate();

    // Clear sync mapping (avoid stale UA across tests)
    PXUASyncInitIfNeeded();
    dispatch_async(gWKWebViewsQueue, ^{
        [gUAByHost removeAllObjects];
        gUASyncLastUA = nil;
        [gWKWebViews compact];
    });
}

// Safe check if a bundle ID is a critical system process
static BOOL isCriticalSystemProcess(NSString *bundleID) {
    if (!bundleID) return YES; // Treat nil as critical for safety

    // Safari/Auth stack is allowed when the dedicated toggle is enabled.
    NSString *proc = [NSProcessInfo processInfo].processName;
    if (PXSafariStackSpoofEnabled() && PXIsSafariStackProcess(bundleID, proc)) {
        return NO;
    }
    
    // Check against our critical system bundle IDs list
    if ([criticalSystemBundleIDs() containsObject:bundleID]) {
        // Allow spoofing for Safari and WebKit processes, even though they're in the critical list
        // This is necessary to spoof browser user agents
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"] ||
            [bundleID isEqualToString:@"com.apple.SafariViewService"] ||
            [bundleID hasPrefix:@"com.apple.WebKit"]) {
            return NO;
        }
        return YES;
    }
    
    // Check for system app prefixes
    if ([bundleID hasPrefix:@"com.apple."]) {
        // Allow spoofing for Safari and WebKit processes
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"] ||
            [bundleID isEqualToString:@"com.apple.SafariViewService"] ||
            [bundleID hasPrefix:@"com.apple.WebKit"]) {
            return NO;
        }
        return YES;
    }
    
    // Check for other known system bundle ID patterns
    if ([bundleID hasPrefix:@"com.hydra.projectx"] ||
        [bundleID isEqualToString:@"com.saurik.Cydia"] ||
        [bundleID isEqualToString:@"org.coolstar.SileoStore"] ||
        [bundleID isEqualToString:@"xyz.willy.Zebra"]) {
        return YES;
    }
    
    return NO;
}

#pragma mark - Constructor

// Cleanup function to be called on process termination
%dtor {
    // Free any retained CF objects to prevent memory leaks
    if (cachedDictResult != NULL) {
        CFRelease(cachedDictResult);
        cachedDictResult = NULL;
    }
    
    // Clear other caches
    cachedSystemVersionResult = nil;
    cachedBundleDecisions = nil;
    versionCache = nil;
}

%ctor {
    @autoreleasepool {
        // Get the bundle ID for scope checking
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Skip for system processes to avoid potential issues
        if (isCriticalSystemProcess(bundleID)) {
            return;
        }
        
        IOSVERSION_LOG(@"Initializing iOS Version Hooks for %@...", bundleID);
        
        // Only install hooks if app is scoped, OR if Safari/Auth stack spoof is enabled.
        if (!isInScopedAppsList() && !PXAllowUnscopedSafariStack()) {
            // App is NOT scoped - no hooks, no interference, no crashes
            IOSVERSION_LOG(@"App %@ is not scoped, skipping iOS version hook installation", bundleID);
            return;
        }
        
        IOSVERSION_LOG(@"App %@ is scoped, installing iOS version hooks", bundleID);
        
        // Initialize caches
        cachedBundleDecisions = [NSMutableDictionary dictionary];
        versionCache = nil;
        
        // Register for settings change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.settings.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Register for iOS version-specific toggle notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.toggleIOSVersionSpoof"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Register for profile change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.profileChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Force ElleKit hooks to be applied regardless of environment detection
        // This is needed for rootless jailbreaks where 0 might fail
        IOSVERSION_LOG(@"Setting up ElleKit hooks for build number spoofing");
        
        // Hook CoreFoundation version dictionary function
        void *cfFramework = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
        if (cfFramework) {
            // Try several possible symbol names for CFCopySystemVersionDictionary
            const char *symbolNames[] = {
                "CFCopySystemVersionDictionary",
                "_CFCopySystemVersionDictionary",
                "__CFCopySystemVersionDictionary"
            };
            
            void *cfCopySystemVersionDictionaryPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfCopySystemVersionDictionaryPtr = dlsym(cfFramework, symbolNames[i]);
                if (cfCopySystemVersionDictionaryPtr) {
                    IOSVERSION_LOG(@"Found CoreFoundation symbol: %s", symbolNames[i]);
                    break;
                }
            }
            
            if (cfCopySystemVersionDictionaryPtr) {
                MSHookFunction(cfCopySystemVersionDictionaryPtr, (void *)replaced_CFCopySystemVersionDictionary, (void **)&original_CFCopySystemVersionDictionary);
                IOSVERSION_LOG(@"Successfully hooked CFCopySystemVersionDictionary");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFCopySystemVersionDictionary symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFCopySystemVersionDictionary = NULL;
                IOSVERSION_LOG(@"Set original_CFCopySystemVersionDictionary to NULL, will use fallback in replacement function");
            }
            
            // Hook CFBundle info dictionary key function - try different symbol names
            const char *bundleSymbolNames[] = {
                "CFBundleGetValueForInfoDictionaryKey",
                "_CFBundleGetValueForInfoDictionaryKey",
                "__CFBundleGetValueForInfoDictionaryKey"
            };
            
            void *cfBundleGetValueForInfoDictionaryKeyPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfBundleGetValueForInfoDictionaryKeyPtr = dlsym(cfFramework, bundleSymbolNames[i]);
                if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                    IOSVERSION_LOG(@"Found CFBundle symbol: %s", bundleSymbolNames[i]);
                    break;
                }
            }
            
            if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                MSHookFunction(cfBundleGetValueForInfoDictionaryKeyPtr, (void *)replaced_CFBundleGetValueForInfoDictionaryKey, (void **)&original_CFBundleGetValueForInfoDictionaryKey);
                IOSVERSION_LOG(@"Successfully hooked CFBundleGetValueForInfoDictionaryKey");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFBundleGetValueForInfoDictionaryKey symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFBundleGetValueForInfoDictionaryKey = NULL;
                IOSVERSION_LOG(@"Set original_CFBundleGetValueForInfoDictionaryKey to NULL, will use fallback in replacement function");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open CoreFoundation framework");
        }
        
        // Hook sysctlbyname for kernel version checks
        void *libSystemHandle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libSystemHandle) {
            void *sysctlbynamePtr = dlsym(libSystemHandle, "sysctlbyname");
            if (sysctlbynamePtr) {
                if (!gOwnerSysctlBynameInstalled) {
                    MSHookFunction(sysctlbynamePtr, (void *)hooked_sysctlbyname, (void **)&original_sysctlbyname);
                    IOSVERSION_LOG(@"Hooked sysctlbyname");
                } else {
                    IOSVERSION_LOG(@"Skipping sysctlbyname hook (owner already installed)");
                }
            } else {
                IOSVERSION_LOG(@"⚠️ Failed to find sysctlbyname symbol");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open libSystem.B.dylib");
        }
        
        // Set up hooks for direct file access methods to catch SystemVersion.plist reads
        IOSVERSION_LOG(@"Setting up hooks for direct file access methods");
        
        // Hook NSData dataWithContentsOfFile:
        Class NSDataClass = objc_getClass("NSData");
        SEL dataWithContentsOfFileSelector = @selector(dataWithContentsOfFile:);
        Method dataWithContentsOfFileMethod = class_getClassMethod(NSDataClass, dataWithContentsOfFileSelector);
        if (dataWithContentsOfFileMethod) {
            original_NSData_dataWithContentsOfFile = (NSData* (*)(Class, SEL, NSString *))method_getImplementation(dataWithContentsOfFileMethod);
            method_setImplementation(dataWithContentsOfFileMethod, (IMP)replaced_NSData_dataWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSData dataWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSData dataWithContentsOfFile:");
        }
        
        // Hook NSDictionary dictionaryWithContentsOfFile:
        Class NSDictionaryClass = objc_getClass("NSDictionary");
        SEL dictWithContentsOfFileSelector = @selector(dictionaryWithContentsOfFile:);
        Method dictWithContentsOfFileMethod = class_getClassMethod(NSDictionaryClass, dictWithContentsOfFileSelector);
        if (dictWithContentsOfFileMethod) {
            original_NSDictionary_dictionaryWithContentsOfFile = (NSDictionary* (*)(Class, SEL, NSString *))method_getImplementation(dictWithContentsOfFileMethod);
            method_setImplementation(dictWithContentsOfFileMethod, (IMP)replaced_NSDictionary_dictionaryWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSDictionary dictionaryWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSDictionary dictionaryWithContentsOfFile:");
        }
        
        // Hook NSString stringWithContentsOfFile:encoding:error:
        Class NSStringClass = objc_getClass("NSString");
        SEL stringWithContentsOfFileSelector = @selector(stringWithContentsOfFile:encoding:error:);
        Method stringWithContentsOfFileMethod = class_getClassMethod(NSStringClass, stringWithContentsOfFileSelector);
        if (stringWithContentsOfFileMethod) {
            original_NSString_stringWithContentsOfFile = (id (*)(Class, SEL, NSString *, NSStringEncoding, NSError **))method_getImplementation(stringWithContentsOfFileMethod);
            method_setImplementation(stringWithContentsOfFileMethod, (IMP)replaced_NSString_stringWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSString stringWithContentsOfFile:encoding:error:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSString stringWithContentsOfFile:encoding:error:");
        }
        
        // Initialize Objective-C hooks for scoped apps only
        %init;
        
        IOSVERSION_LOG(@"iOS Version Hooks successfully initialized for scoped app: %@", bundleID);
    }
}

#pragma mark - File Access Hooks for SystemVersion.plist

// Function to check if a path is a system version file
static BOOL isSystemVersionFile(NSString *path) {
    if (!path) return NO;
    
    // Normalize path before comparing
    path = [path stringByStandardizingPath];
    return [path isEqualToString:SYSTEM_VERSION_PATH] || 
           [path isEqualToString:ROOTLESS_SYSTEM_VERSION_PATH] ||
           [path hasSuffix:@"SystemVersion.plist"];
}

// Function to spoof a system version plist
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist) {
    if (!originalPlist) return nil;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) return originalPlist;
    
    // Get our spoofed values
    NSDictionary *versionInfo = getIOSVersionInfo();
    if (!versionInfo || !versionInfo[@"version"] || !versionInfo[@"build"]) {
        return originalPlist;
    }
    
    // Make a copy with our spoofed values
    NSMutableDictionary *modifiedPlist = [originalPlist mutableCopy];
    
    // Modify the values we want to spoof
    [modifiedPlist setValue:versionInfo[@"version"] forKey:@"ProductVersion"];
    [modifiedPlist setValue:versionInfo[@"build"] forKey:@"ProductBuildVersion"];
    
    // Only log occasionally to reduce overhead
    static uint64_t lastPlistLogTime = 0;
    uint64_t currentTime = mach_absolute_time();
    if (lastPlistLogTime == 0 || (currentTime - lastPlistLogTime) > THROTTLE_INTERVAL_NSEC * 10) {
        IOSVERSION_LOG(@"📄 Spoofed SystemVersion.plist access: %@ → %@, %@ → %@",
              originalPlist[@"ProductVersion"], versionInfo[@"version"],
              originalPlist[@"ProductBuildVersion"], versionInfo[@"build"]);
        lastPlistLogTime = currentTime;
    }
    
    return modifiedPlist;
}

// Hook NSData dataWithContentsOfFile: to intercept SystemVersion.plist reads
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSData *originalData = original_NSData_dataWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path)) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Get the plist as a dictionary from the data
            NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:originalData 
                                                                            options:0 
                                                                             format:NULL 
                                                                              error:NULL];
            if (plist) {
                // Spoof the values
                NSDictionary *spoofedPlist = spoofSystemVersionPlist(plist);
                
                // Convert back to data
                NSData *spoofedData = [NSPropertyListSerialization dataWithPropertyList:spoofedPlist
                                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                                options:0
                                                                                  error:NULL];
                if (spoofedData) {
                    return spoofedData;
                }
            }
        }
    }
    
    return originalData;
}

// Hook NSDictionary dictionaryWithContentsOfFile: to intercept SystemVersion.plist reads
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSDictionary *originalDict = original_NSDictionary_dictionaryWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path) && originalDict) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            return spoofSystemVersionPlist(originalDict);
        }
    }
    
    return originalDict;
}

// Hook NSString stringWithContentsOfFile:encoding:error: to intercept text file reads
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    id originalString = original_NSString_stringWithContentsOfFile(self, _cmd, path, enc, error);
    
    if (isSystemVersionFile(path) && originalString) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // For handling XML/plist files as raw strings
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (versionInfo && versionInfo[@"version"] && versionInfo[@"build"]) {
                NSString *modifiedString = [originalString mutableCopy];
                modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                      [NSString stringWithFormat:@"<key>ProductVersion</key>\\s*<string>[^<]+</string>"]
                                      withString:[NSString stringWithFormat:@"<key>ProductVersion</key><string>%@</string>", versionInfo[@"version"]]
                                      options:NSRegularExpressionSearch
                                      range:NSMakeRange(0, [modifiedString length])];
                                      
                modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                      [NSString stringWithFormat:@"<key>ProductBuildVersion</key>\\s*<string>[^<]+</string>"]
                                      withString:[NSString stringWithFormat:@"<key>ProductBuildVersion</key><string>%@</string>", versionInfo[@"build"]]
                                      options:NSRegularExpressionSearch
                                      range:NSMakeRange(0, [modifiedString length])];
                                      
                return modifiedString;
            }
        }
    }
    
    return originalString;
} 
