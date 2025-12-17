#import "ProjectX.h"
#import "UptimeManager.h"
#import "ProfileManager.h"
#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/mach_host.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// Define the boot time structure for sysctl calls
struct timeval_boot {
    time_t tv_sec;
    suseconds_t tv_usec;
};

// Original function pointers - ONLY for system calls
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

// Cache for spoofed values to improve performance
static NSDate *cachedBootTime = nil;
static NSTimeInterval cachedUptime = 0;
static NSString *cachedProfilePath = nil;
static NSDate *cacheTimestamp = nil;
static const NSTimeInterval kCacheValidityDuration = 30.0; // 30 seconds cache

// Global flag to track if hooks are installed
static BOOL hooksInstalled = NO;

// Forward declarations
static NSString *getCurrentProfilePath(void);
static void updateCachedBootTimeValues(void);
static void installSystemCallHooks(void);
static BOOL isBootTimeOrUptimeEnabled(void);

#pragma mark - Helper Functions




// Get the current profile path for spoofed values
static NSString *getCurrentProfilePath(void) {
    @try {
        ProfileManager *profileManager = [ProfileManager sharedManager];
        if (!profileManager) return nil;
        
        Profile *currentProfile = [profileManager currentProfile];
        if (!currentProfile) return nil;
        
        // Use the hardcoded profiles directory path since profilesDirectory is private
        NSString *profilesDir = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        return [profilesDir stringByAppendingPathComponent:currentProfile.profileId];
    } @catch (NSException *e) {
        return nil;
    }
}

// Update cached boot time values from profile data
static void updateCachedBootTimeValues(void) {
    @try {
        NSString *profilePath = getCurrentProfilePath();
        if (!profilePath) {
            // Don't log this too frequently
            static NSDate *lastLog = nil;
            if (!lastLog || [[NSDate date] timeIntervalSinceDate:lastLog] > 300.0) {
                PXLog(@"[BootTimeHooks] ⚠️ No profile path available");
                lastLog = [NSDate date];
            }
            return;
        }
        
        // Check if cache is still valid
        if (cachedBootTime && cacheTimestamp && cachedProfilePath && 
            [cachedProfilePath isEqualToString:profilePath] &&
            [[NSDate date] timeIntervalSinceDate:cacheTimestamp] < kCacheValidityDuration) {
            return; // Cache is still valid
        }
        
        UptimeManager *uptimeManager = [UptimeManager sharedManager];
        if (!uptimeManager) return;
        
        // Get spoofed boot time and uptime
        NSDate *bootTime = [[UptimeManager sharedManager] currentBootTime];
        NSTimeInterval uptime = [[UptimeManager sharedManager] currentUptime];
        
        if (!bootTime || uptime <= 0) {
            [[IdentifierManager sharedManager] generateSystemUptime];
            [[IdentifierManager sharedManager] generateBootTime];
            bootTime = [[UptimeManager sharedManager] currentBootTime];
            uptime = [[UptimeManager sharedManager] currentUptime];
        }
        
        // Validate the data before caching
        if (bootTime && uptime > 0) {
            cachedBootTime = bootTime;
            cachedUptime = uptime;
            cachedProfilePath = profilePath;
            cacheTimestamp = [NSDate date];
        }
        
    } @catch (NSException *e) {
        // Silent failure to avoid crashes
    }
}

// Helper to check if a spoof identifier is enabled for the current profile
static BOOL isBootTimeOrUptimeEnabled(void) {
    @try {
        IdentifierManager *manager = [IdentifierManager sharedManager];
        SEL isEnabledSel = NSSelectorFromString(@"isIdentifierEnabled:");
        if (![manager respondsToSelector:isEnabledSel]) return NO;
        
        BOOL bootTimeEnabled = NO;
        BOOL uptimeEnabled = NO;
        NSString *bootTimeStr = @"BootTime";
        NSString *uptimeStr = @"SystemUptime";
        NSMethodSignature *sig = [manager methodSignatureForSelector:isEnabledSel];
        if (sig) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setSelector:isEnabledSel];
            [invocation setTarget:manager];
            // BootTime
            [invocation setArgument:&bootTimeStr atIndex:2];
            [invocation invoke];
            [invocation getReturnValue:&bootTimeEnabled];
            // SystemUptime
            [invocation setArgument:&uptimeStr atIndex:2];
            [invocation invoke];
            [invocation getReturnValue:&uptimeEnabled];
        }
        return bootTimeEnabled || uptimeEnabled;
    } @catch (NSException *e) {
        return NO;
    }
}

#pragma mark - System Call Hooks

// Hook sysctl() for KERN_BOOTTIME queries - ONLY method that App Store apps commonly use
int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    @try {
        // Check if this is a KERN_BOOTTIME query
        if (namelen >= 2 && name && name[0] == CTL_KERN && name[1] == KERN_BOOTTIME) {
            updateCachedBootTimeValues();
            if (cachedBootTime && oldp && oldlenp && *oldlenp >= sizeof(struct timeval)) {
                struct timeval boottime;
                boottime.tv_sec = (time_t)[cachedBootTime timeIntervalSince1970];
                boottime.tv_usec = 0;
                memcpy(oldp, &boottime, sizeof(boottime));
                *oldlenp = sizeof(boottime);
                return 0; // Success
            }
        }
    } @catch (NSException *e) {
        // Silent failure, pass through to original
    }
    // Call original function for all other cases
    if (orig_sysctl) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }
    return -1;
}

// Hook sysctlbyname() for "kern.boottime" queries - ONLY method that App Store apps commonly use
int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    @try {
        if (name && strcmp(name, "kern.boottime") == 0) {
            updateCachedBootTimeValues();
            if (cachedBootTime && oldp && oldlenp && *oldlenp >= sizeof(struct timeval)) {
                struct timeval boottime;
                boottime.tv_sec = (time_t)[cachedBootTime timeIntervalSince1970];
                boottime.tv_usec = 0;
                memcpy(oldp, &boottime, sizeof(boottime));
                *oldlenp = sizeof(boottime);
                return 0; // Success
            }
        }
    } @catch (NSException *e) {
        // Silent failure, pass through to original
    }
    // Call original function for all other cases
    if (orig_sysctlbyname) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    return -1;
}

// Hook for -[NSProcessInfo systemUptime]
static NSTimeInterval (*orig_systemUptime)(NSProcessInfo *, SEL);
static NSTimeInterval hook_systemUptime(NSProcessInfo *self, SEL _cmd) {
    updateCachedBootTimeValues();
    if (cachedUptime > 0) {
        return cachedUptime;
    }
    
    return orig_systemUptime(self, _cmd);
}

// Install system call hooks ONLY for scoped apps
static void installSystemCallHooks(void) {
    @try {
        if (hooksInstalled) {
            return; // Already installed
        }
        
        BOOL hookingSuccess = NO;
        
        // Try ElleKit first (preferred for rootless jailbreaks)

        // Fallback to Substrate
        void *sysctlPtr = dlsym(RTLD_DEFAULT, "sysctl");
        if (sysctlPtr) {
            MSHookFunction(sysctlPtr, (void *)hook_sysctl, (void **)&orig_sysctl);
            hookingSuccess = YES;
        }
        
        void *sysctlbynamePtr = dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (sysctlbynamePtr) {
            MSHookFunction(sysctlbynamePtr, (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
            hookingSuccess = YES;
        }
    
        
        if (hookingSuccess) {
            hooksInstalled = YES;
            // Add systemUptime hook for NSProcessInfo
            Class procInfoClass = objc_getClass("NSProcessInfo");
            if (procInfoClass) {
                MSHookMessageEx(procInfoClass, @selector(systemUptime), (IMP)hook_systemUptime, (IMP *)&orig_systemUptime);
            }
        }
        
    } @catch (NSException *e) {
        PXLog(@"[BootTimeHooks] ❌ Exception installing hooks: %@", e);
    }
}

#pragma mark - Initialization

// COMPLETELY REMOVED ALL %hook DIRECTIVES - NO MORE OBJECTIVE-C METHOD HOOKS
// This eliminates crashes in non-scoped apps

%ctor {
    @autoreleasepool {
        @try {

            if (!isBootTimeOrUptimeEnabled()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                return;
            }
            
            PXLog(@"[BootTimeHooks]  Installing minimal system call hooks for scoped app");
            
            // Install the minimal system call hooks that App Store apps actually use immediately
            installSystemCallHooks();
            
        } @catch (NSException *e) {
            // Silent failure to prevent crashes
        }
    }
} 