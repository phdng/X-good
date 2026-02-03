#import "ProjectX.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"

#import "PXScope.h"

// Helper declarations
static BOOL isSpoofingEnabled(void);
static NSString* getSpoofedDeviceModel(void);

// Device Resolution Database
// Format: ModelID -> @{ @"width": @W, @"height": @H, @"scale": @S }
static NSDictionary* getDeviceResolutions() {
    static NSDictionary *resolutions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resolutions = @{
            // iPhone 6s, 7, 8, SE2, SE3
            @"iPhone8,1": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone9,1": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone9,3": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone10,1": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone10,4": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone12,8": @{@"w": @750, @"h": @1334, @"s": @2.0},
            @"iPhone14,6": @{@"w": @750, @"h": @1334, @"s": @2.0},
            
            // iPhone 6s Plus, 7 Plus, 8 Plus
            @"iPhone8,2": @{@"w": @1242, @"h": @2208, @"s": @3.0},
            @"iPhone9,2": @{@"w": @1242, @"h": @2208, @"s": @3.0},
            @"iPhone9,4": @{@"w": @1242, @"h": @2208, @"s": @3.0},
            @"iPhone10,2": @{@"w": @1242, @"h": @2208, @"s": @3.0},
            @"iPhone10,5": @{@"w": @1242, @"h": @2208, @"s": @3.0},
            
            // iPhone X, XS, 11 Pro
            @"iPhone10,3": @{@"w": @1125, @"h": @2436, @"s": @3.0},
            @"iPhone10,6": @{@"w": @1125, @"h": @2436, @"s": @3.0},
            @"iPhone11,2": @{@"w": @1125, @"h": @2436, @"s": @3.0},
            @"iPhone12,3": @{@"w": @1125, @"h": @2436, @"s": @3.0},
            
            // iPhone XR, 11
            @"iPhone11,8": @{@"w": @828, @"h": @1792, @"s": @2.0},
            @"iPhone12,1": @{@"w": @828, @"h": @1792, @"s": @2.0},
            
            // iPhone XS Max, 11 Pro Max
            @"iPhone11,6": @{@"w": @1242, @"h": @2688, @"s": @3.0},
            @"iPhone12,5": @{@"w": @1242, @"h": @2688, @"s": @3.0},
            
            // iPhone 12/13/14 mini
            @"iPhone13,1": @{@"w": @1080, @"h": @2340, @"s": @3.0},
            @"iPhone14,4": @{@"w": @1080, @"h": @2340, @"s": @3.0},
            
            // iPhone 12/13/14, 12/13/14 Pro
            @"iPhone13,2": @{@"w": @1170, @"h": @2532, @"s": @3.0},
            @"iPhone13,3": @{@"w": @1170, @"h": @2532, @"s": @3.0},
            @"iPhone14,2": @{@"w": @1170, @"h": @2532, @"s": @3.0},
            @"iPhone14,5": @{@"w": @1170, @"h": @2532, @"s": @3.0},
            @"iPhone14,7": @{@"w": @1170, @"h": @2532, @"s": @3.0},
            @"iPhone15,2": @{@"w": @1179, @"h": @2556, @"s": @3.0}, // 14 Pro
            
            // iPhone 12/13/14 Pro Max
            @"iPhone13,4": @{@"w": @1284, @"h": @2778, @"s": @3.0},
            @"iPhone14,3": @{@"w": @1284, @"h": @2778, @"s": @3.0},
            @"iPhone14,8": @{@"w": @1284, @"h": @2778, @"s": @3.0}, // 14 Plus
            @"iPhone15,3": @{@"w": @1290, @"h": @2796, @"s": @3.0}, // 14 Pro Max
        };
    });
    return resolutions;
}

static NSDictionary* getSpecsForModel(NSString *model) {
    if (!model) return nil;
    return getDeviceResolutions()[model];
}

// Reuse helper from DeviceModelHooks.x (simplified duplication for safety)
static NSString* getSpoofedModel() {
    // Try to get from property first if feasible, but here we can just read from file directly 
    // to avoid cross-file dependency issues if symbols aren't exported.
    // For simplicity, let's try to get it from profile directly.
    @try {
        NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        NSString *profileId = centralInfo[@"ProfileId"];
        
        if (profileId) {
            NSString *identityDir = [[profilesPath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:[identityDir stringByAppendingPathComponent:@"device_ids.plist"]];
            return deviceIds[@"DeviceModel"];
        }
    } @catch (NSException *e) {}
    return nil;
}

static BOOL isSpoofingGlobalEnabled() {
    // Implement minimal check or reuse existing logic
    // This is a simplified check.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return NO;
    NSString *proc = [NSProcessInfo processInfo].processName;
    if ([bundleID hasPrefix:@"com.apple."] &&
        !(PXSafariStackSpoofEnabled() && PXIsSafariStackProcess(bundleID, proc))) {
        return NO;
    }
    // Tie to global device spoofing toggle.
    return PXDeviceSpoofingEnabled();
    // Ideally this should use the centralized `isDeviceModelSpoofingEnabled` but that requires linking or exposing it.
    // We'll rely on the fact that if we get a spoofed model, we should probably use it.
}


// --- Metal GPU Name Hook ---

// Helper to get GPU name from Chip
static BOOL isInScopedAppsList_Missing(void) {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID.length) return NO;
        NSArray *paths = @[@"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                           @"/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                           @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist"];
        NSDictionary *plist = nil;
        for (NSString *p in paths) {
            plist = [NSDictionary dictionaryWithContentsOfFile:p];
            if (plist) break;
        }
        NSDictionary *scopedApps = [plist isKindOfClass:[NSDictionary class]] ? plist[@"ScopedApps"] : nil;
        NSDictionary *entry = [scopedApps isKindOfClass:[NSDictionary class]] ? scopedApps[bundleID] : nil;
        return [entry isKindOfClass:[NSDictionary class]] ? [entry[@"enabled"] boolValue] : NO;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL shouldSpoofForCurrentProcess_Missing(void) {
    if (!PXDeviceSpoofingEnabled()) return NO;
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid.length) return NO;
    NSString *proc = [NSProcessInfo processInfo].processName;
    if ([bid hasPrefix:@"com.apple."] && !(PXSafariStackSpoofEnabled() && PXIsSafariStackProcess(bid, proc))) {
        return NO;
    }
    return isInScopedAppsList_Missing() || PXAllowUnscopedSafariStack();
}

static NSString *getSpoofedGPUFamily(void) {
    @try {
        NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        NSString *profileId = centralInfo[@"ProfileId"];
        if (!profileId.length) return nil;
        NSString *identityDir = [[profilesPath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:[identityDir stringByAppendingPathComponent:@"device_ids.plist"]];
        NSString *gpuFamily = [deviceIds[@"GPUFamily"] isKindOfClass:[NSString class]] ? deviceIds[@"GPUFamily"] : nil;
        if (gpuFamily.length) return gpuFamily;
        NSString *webgl = [deviceIds[@"WebGLRenderer"] isKindOfClass:[NSString class]] ? deviceIds[@"WebGLRenderer"] : nil;
        return webgl.length ? webgl : nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

// Hook MTLDevice name
// Since the concrete class of the device is private (e.g. AGXG13Device), we can't %hook it easily by name at compile time.
// We'll hook MTLCreateSystemDefaultDevice and then dynamcially hook the returned object's class.

static NSString *(*orig_MTLDevice_name)(id, SEL);
static NSString *hook_MTLDevice_name(id self, SEL _cmd) {
    if (shouldSpoofForCurrentProcess_Missing()) {
        NSString *gpuName = getSpoofedGPUFamily();
        if (gpuName.length) {
            return gpuName;
        }
    }
    return orig_MTLDevice_name(self, _cmd);
}

static id (*orig_MTLCreateSystemDefaultDevice)(void);
static id new_MTLCreateSystemDefaultDevice(void) {
    id device = orig_MTLCreateSystemDefaultDevice();
    if (device) {
        // Check if we already hooked this class
        static NSMutableSet *hookedClasses = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            hookedClasses = [NSMutableSet set];
        });
        
        Class cls = [device class];
        NSString *clsName = NSStringFromClass(cls);
        
        @synchronized(hookedClasses) {
            if (![hookedClasses containsObject:clsName]) {
                // Hook the 'name' method of this specific class
                MSHookMessageEx(cls, @selector(name), (IMP)hook_MTLDevice_name, (IMP *)&orig_MTLDevice_name);
                [hookedClasses addObject:clsName];
                PXLog(@"[MissingHooks] Hooked MTLDevice name for class: %@", clsName);
            }
        }
    }
    return device;
}

%ctor {
    @autoreleasepool {
        PXLog(@"[MissingHooks] Init");
        // Hook Metal Create function
        void *mtlCreate = dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        if (mtlCreate) {
            MSHookFunction(mtlCreate, (void *)new_MTLCreateSystemDefaultDevice, (void **)&orig_MTLCreateSystemDefaultDevice);
        }
    }
}
