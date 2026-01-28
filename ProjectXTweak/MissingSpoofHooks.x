#import "ProjectX.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"

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
    if ([bundleID containsString:@"com.apple."] && ![bundleID isEqualToString:@"com.apple.mobilesafari"]) return NO;
    // Add more robust checks if needed
    return YES; 
    // Ideally this should use the centralized `isDeviceModelSpoofingEnabled` but that requires linking or exposing it.
    // We'll rely on the fact that if we get a spoofed model, we should probably use it.
}


// --- UIScreen Hook ---

%hook UIScreen

- (CGRect)nativeBounds {
    CGRect original = %orig;
    NSString *spoofedModel = getSpoofedModel();
    NSDictionary *specs = getSpecsForModel(spoofedModel);
    
    if (specs) {
        // PXLog(@"[MissingHooks] Spoofing nativeBounds for %@", spoofedModel);
        CGFloat w = [specs[@"w"] floatValue];
        CGFloat h = [specs[@"h"] floatValue];
        return CGRectMake(0, 0, w, h);
    }
    return original;
}

- (CGRect)bounds {
    CGRect original = %orig;
    NSString *spoofedModel = getSpoofedModel();
    NSDictionary *specs = getSpecsForModel(spoofedModel);
    
    if (specs) {
        CGFloat w = [specs[@"w"] floatValue];
        CGFloat h = [specs[@"h"] floatValue];
        CGFloat s = [specs[@"s"] floatValue];
        // Bounds is usually in points (pixels / scale)
        return CGRectMake(0, 0, w/s, h/s);
    }
    return original;
}

- (CGFloat)scale {
    CGFloat original = %orig;
    NSString *spoofedModel = getSpoofedModel();
    NSDictionary *specs = getSpecsForModel(spoofedModel);
    if (specs) {
        return [specs[@"s"] floatValue];
    }
    return original;
}

- (CGFloat)nativeScale {
    CGFloat original = %orig;
    NSString *spoofedModel = getSpoofedModel();
    NSDictionary *specs = getSpecsForModel(spoofedModel);
    if (specs) {
        return [specs[@"s"] floatValue];
    }
    return original;
}

%end

// --- Metal GPU Name Hook ---

// Helper to get GPU name from Chip
static NSString* getGPUName(NSString *model) {
    // Simplified mapping based on Generation
    if ([model hasPrefix:@"iPhone8"]) return @"Apple A9 GPU";
    if ([model hasPrefix:@"iPhone9"]) return @"Apple A10 GPU";
    if ([model hasPrefix:@"iPhone10"]) return @"Apple A11 GPU";
    if ([model hasPrefix:@"iPhone11"]) return @"Apple A12 GPU";
    if ([model hasPrefix:@"iPhone12"]) return @"Apple A13 GPU";
    if ([model hasPrefix:@"iPhone13"]) return @"Apple A14 GPU";
    if ([model hasPrefix:@"iPhone14"]) return @"Apple A15 GPU";
    if ([model hasPrefix:@"iPhone15"]) return @"Apple A16 GPU"; // 14 Pro
    if ([model hasPrefix:@"iPhone16"]) return @"Apple A17 GPU"; // 15 Pro (hypothetical naming)
    return @"Apple GPU";
}

// Hook MTLDevice name
// Since the concrete class of the device is private (e.g. AGXG13Device), we can't %hook it easily by name at compile time.
// We'll hook MTLCreateSystemDefaultDevice and then dynamcially hook the returned object's class.

static NSString *(*orig_MTLDevice_name)(id, SEL);
static NSString *hook_MTLDevice_name(id self, SEL _cmd) {
    NSString *model = getSpoofedModel();
    if (model) {
        NSString *gpuName = getGPUName(model);
        // PXLog(@"[MissingHooks] Spoofing GPU Name to %@", gpuName);
        return gpuName;
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
