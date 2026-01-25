#import "ProjectX.h"
#import "DeviceModelManager.h"
#import "IdentifierManager.h"
#import "ProfileManager.h"
#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>
// #import <ellekit/ellekit.h> // Removed for rootful - using Substrate
#import "MobileGestalt.h"

// Original function pointers
static int (*orig_uname)(struct utsname *);
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);

// Forward declare helper functions
static void logDeviceModelAccess(const char* method, NSString* bundleID);

#pragma mark - Helper Functions

// Cache to reduce frequency of expensive checks
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes

// Check if device model spoofing is enabled for the current app with caching
static BOOL isDeviceModelSpoofingEnabled() {
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) return NO;
    
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    });
    
    // Check cache first
    @synchronized(cachedBundleDecisions) {
        NSNumber *cachedDecision = cachedBundleDecisions[currentBundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]];
        
        if (cachedDecision && decisionTimestamp && 
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    
    // If not cached or expired, check if this app is enabled for spoofing
    BOOL shouldSpoof = NO;
    @try {
        BOOL managerCheckPassed = NO;
        
        // METHOD 1: Check via IdentifierManager if available
        if (NSClassFromString(@"IdentifierManager")) {
            IdentifierManager *manager = [NSClassFromString(@"IdentifierManager") sharedManager];
            if (manager && [manager isApplicationEnabled:currentBundleID]) {
                if ([manager isIdentifierEnabled:@"DeviceModel"]) {
                    shouldSpoof = YES;
                    managerCheckPassed = YES;
                }
            }
        }
        
        // METHOD 2: Fallback to direct profile settings if Manager check didn't pass
        // (This handles cases where IdentifierManager is missing OR it says NO/Disabled, 
        // but we might want to trust the plist if the user insists - typically we respect the Manager, 
        // but if Manager is missing we MUST check plist)
        if (!managerCheckPassed) {
            // Try to get profile settings directly from file
            NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
            NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
            NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
            
            NSString *profileId = centralInfo[@"ProfileId"];
            if (profileId) {
                NSString *profileSettingsPath = [profilesPath stringByAppendingPathComponent:[profileId stringByAppendingPathComponent:@"settings.plist"]];
                NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:profileSettingsPath];
                // Check if global enabled or device model specifically enabled
                if (settings && settings[@"deviceModelEnabled"]) {
                    shouldSpoof = [settings[@"deviceModelEnabled"] boolValue];
                    
                    // Also check if App is Scoped (Global Scope Plist)
                    // If we are falling back to manual plist reading, we should ideally check scope too.
                    NSString *scopePath = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
                    NSDictionary *scopeDict = [NSDictionary dictionaryWithContentsOfFile:scopePath];
                    NSDictionary *scopedApps = scopeDict[@"ScopedApps"];
                    if (scopedApps && scopedApps[currentBundleID]) {
                        if ([scopedApps[currentBundleID][@"enabled"] boolValue]) {
                            // Only set YES if both App is scoped AND DeviceModel is enabled in profile
                            // (If shouldSpoof was already YES from profile settings)
                        } else {
                            shouldSpoof = NO;
                        }
                    } else {
                        shouldSpoof = NO; // Not in scope
                    }
                }
            }
                }
            }
        
        // METHOD 3: Fallback check - if we have a valid spoofed model available via legacy means (or any means),
        // we should probably enable spoofing to match old behavior where existence of data implied enablement.
        // This is critical for users migrating who haven't set up new profiles yet.
        if (!shouldSpoof) {
            // Check if we can get a model. Note: usage of getSpoofedDeviceModel() here might be expensive
            // but we cache the "isEnabled" decision so it only happens once per 5 mins.
            // We can't call getSpoofedDeviceModel() directly easily here because it's defined later.
            // But we can check the Legacy CFPreference directly as a quick check.
            
            CFStringRef appID = CFSTR("com.projectx.phoneinfo");
            CFStringRef key = CFSTR("PhoneInfo");
            CFPropertyListRef value = CFPreferencesCopyValue(key, appID, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
            if (value) {
                if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                    NSDictionary *dict = (__bridge NSDictionary *)value;
                    if (dict[@"deviceModel"] && dict[@"deviceModel"][@"modelName"]) {
                        shouldSpoof = YES;
                    }
                }
                CFRelease(value);
            }
            
            if (!shouldSpoof) {
                 value = CFPreferencesCopyValue(key, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                 if (value) {
                    if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                        NSDictionary *dict = (__bridge NSDictionary *)value;
                         if (dict[@"deviceModel"] && dict[@"deviceModel"][@"modelName"]) {
                            shouldSpoof = YES;
                        }
                    }
                    CFRelease(value);
                 }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[model] Exception checking if device model spoofing is enabled: %@", exception);
        shouldSpoof = NO;
    }
    
    // Cache the decision
    @synchronized(cachedBundleDecisions) {
        cachedBundleDecisions[currentBundleID] = @(shouldSpoof);
        cachedBundleDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    }
    
    return shouldSpoof;
}

// Cache for device model values
static NSMutableDictionary *modelCache = nil;
static NSDate *cacheTimestamp = nil;

// Get the spoofed device model more reliably
static NSString* getSpoofedDeviceModel() {
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        modelCache = [NSMutableDictionary dictionary];
        cacheTimestamp = [NSDate date];
    });
    
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) return nil;
    
    // Check cache first for consistency (per bundle ID)
    @synchronized(modelCache) {
        NSString *cachedModel = modelCache[currentBundleID];
        if (cachedModel && [[NSDate date] timeIntervalSinceDate:cacheTimestamp] < 300.0) {
            return cachedModel;
        }
    }
    
    // Try multiple methods to get the model value, with better error handling
    NSString *deviceModel = nil;
    @try {
        // METHOD 1: Try direct access from profile plist for highest reliability
        // First get current profile ID
        NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        
        NSString *profileId = centralInfo[@"ProfileId"];
        if (profileId) {
            // Get the model value from settings.plist in the profile directory
            NSString *settingsPath = [profilesPath stringByAppendingPathComponent:[profileId stringByAppendingPathComponent:@"settings.plist"]];
            NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
            deviceModel = settings[@"deviceModel"];
            
            if (deviceModel.length > 0) {
                PXLog(@"[model] Found device model %@ directly in profile %@ settings", deviceModel, profileId);
            }
        }
        
        // METHOD 2: Use IdentifierManager if direct file access failed
        if (!deviceModel.length && NSClassFromString(@"IdentifierManager")) {
            IdentifierManager *manager = [NSClassFromString(@"IdentifierManager") sharedManager];
            deviceModel = [manager currentValueForIdentifier:@"DeviceModel"];
            
            if (deviceModel.length > 0) {
                PXLog(@"[model] Found device model %@ via IdentifierManager", deviceModel);
            }
        }
        
        // METHOD 3: Use DeviceModelManager as last resort
        if (!deviceModel.length && NSClassFromString(@"DeviceModelManager")) {
            DeviceModelManager *deviceManager = [NSClassFromString(@"DeviceModelManager") sharedManager];
            deviceModel = [deviceManager currentDeviceModel] ?: [deviceManager generateDeviceModel];
            
            if (deviceModel.length > 0) {
                PXLog(@"[model] Using model %@ from DeviceModelManager", deviceModel);
            }
        }
        
        // METHOD 4: Legacy Fallback (CFPreferences - Old Method)
        // This is highly reliable for bypassing sandbox restrictions
        if (!deviceModel.length) {
            CFStringRef appID = CFSTR("com.projectx.phoneinfo");
            CFStringRef key = CFSTR("PhoneInfo");
            
            // Try AnyUser/AnyHost combination first (most likely for system-wide tweaks)
            CFPropertyListRef value = CFPreferencesCopyValue(key, appID, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
            
            if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                NSDictionary *dict = (__bridge NSDictionary *)value;
                NSDictionary *legacyModelDict = dict[@"deviceModel"];
                if (legacyModelDict && legacyModelDict[@"modelName"]) {
                    deviceModel = legacyModelDict[@"modelName"];
                    PXLog(@"[model] Found device model %@ via Legacy CFPreferences (AnyUser/AnyHost)", deviceModel);
                }
                CFRelease(value);
            }
            
            // Try CurrentUser if failed
            if (!deviceModel.length) {
                value = CFPreferencesCopyValue(key, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                    NSDictionary *dict = (__bridge NSDictionary *)value;
                    NSDictionary *legacyModelDict = dict[@"deviceModel"];
                    if (legacyModelDict && legacyModelDict[@"modelName"]) {
                        deviceModel = legacyModelDict[@"modelName"];
                        PXLog(@"[model] Found device model %@ via Legacy CFPreferences (CurrentUser/AnyHost)", deviceModel);
                    }
                    CFRelease(value);
                }
            }
        }
        
        // If we got a model, cache it for this bundle ID
        if (deviceModel.length > 0) {
            @synchronized(modelCache) {
                modelCache[currentBundleID] = deviceModel;
                cacheTimestamp = [NSDate date];
            }
        } else {
            PXLog(@"[model] WARNING: Failed to get device model through any method");
        }
        
        return deviceModel;
    } @catch (NSException *exception) {
        PXLog(@"[model] Exception getting spoofed device model: %@", exception);
        return nil;
    }
}

// Get the spoofed board ID (based on the spoofed device model)
static NSString* getSpoofedBoardID() {
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) return nil;
    
    @try {
        // Get the device model first
        NSString *deviceModel = getSpoofedDeviceModel();
        if (!deviceModel.length) {
            return nil;
        }
        
        // METHOD 1: Try to get from device_ids.plist directly
        NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        NSString *profileId = centralInfo[@"ProfileId"];
        
        if (profileId) {
            NSString *identityDir = [profilesPath stringByAppendingPathComponent:profileId];
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            
            NSString *boardID = deviceIds[@"BoardID"];
            if (boardID.length > 0) {
                PXLog(@"[model] Found board ID %@ directly in device_ids.plist", boardID);
                return boardID;
            }
        }
        
        // METHOD 2: Use DeviceModelManager to look up the board ID for this model
        if (NSClassFromString(@"DeviceModelManager")) {
            DeviceModelManager *deviceManager = [NSClassFromString(@"DeviceModelManager") sharedManager];
            NSString *boardID = [deviceManager boardIDForModel:deviceModel];
            
            if (boardID.length > 0 && ![boardID isEqualToString:@"Unknown"]) {
                PXLog(@"[model] Using board ID %@ from DeviceModelManager for model %@", boardID, deviceModel);
                return boardID;
            }
        }
        
        return nil;
    } @catch (NSException *exception) {
        PXLog(@"[model] Exception getting spoofed board ID: %@", exception);
        return nil;
    }
}

// Get the spoofed hardware model (hw.model) based on the spoofed device model
static NSString* getSpoofedHWModel() {
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!currentBundleID) return nil;
    
    @try {
        // Get the device model first
        NSString *deviceModel = getSpoofedDeviceModel();
        if (!deviceModel.length) {
            return nil;
        }
        
        // METHOD 1: Try to get from device_ids.plist directly
        NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        NSString *profileId = centralInfo[@"ProfileId"];
        
        if (profileId) {
            NSString *identityDir = [profilesPath stringByAppendingPathComponent:profileId];
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            
            NSString *hwModel = deviceIds[@"HwModel"];
            if (hwModel.length > 0) {
                PXLog(@"[model] Found hw.model %@ directly in device_ids.plist", hwModel);
                return hwModel;
            }
        }
        
        // METHOD 2: Use DeviceModelManager to look up the hwModel for this device
        if (NSClassFromString(@"DeviceModelManager")) {
            DeviceModelManager *deviceManager = [NSClassFromString(@"DeviceModelManager") sharedManager];
            NSString *hwModel = [deviceManager hwModelForModel:deviceModel];
            
            if (hwModel.length > 0 && ![hwModel isEqualToString:@"Unknown"]) {
                PXLog(@"[model] Using hw.model %@ from DeviceModelManager for model %@", hwModel, deviceModel);
                return hwModel;
            }
        }
        
        return nil;
    } @catch (NSException *exception) {
        PXLog(@"[model] Exception getting spoofed hw.model: %@", exception);
        return nil;
    }
}

#pragma mark - Hook Implementations

// Hook for uname() system call - used by many apps to detect device model
static int hook_uname(struct utsname *buf) {
    // Call the original first
    int ret = orig_uname(buf);
    
    if (ret != 0) {
        // If original call failed, just return the error
        return ret;
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        return ret; // Can't determine bundle ID, return original result
    }
    
    // Store original value for logging
    char originalMachine[256] = {0};
    if (buf) {
        strlcpy(originalMachine, buf->machine, sizeof(originalMachine));
    }
    
    // Check if we need to spoof
    if (isDeviceModelSpoofingEnabled()) {
        NSString *spoofedModel = getSpoofedDeviceModel();
        
        if (spoofedModel.length > 0) {
            // Convert spoofed model to a C string and copy it to the utsname struct
            const char *model = [spoofedModel UTF8String];
            if (model) {
                size_t modelLen = strlen(model);
                size_t bufferLen = sizeof(buf->machine);
                
                // Ensure we don't overflow the buffer
                if (modelLen < bufferLen) {
                    memset(buf->machine, 0, bufferLen);
                    strcpy(buf->machine, model);
                    PXLog(@"[model] Spoofed uname machine from %s to: %s for app: %@", 
                          originalMachine, buf->machine, bundleID);
                } else {
                    PXLog(@"[model] WARNING: Spoofed model too long for uname buffer");
                }
            }
        } else {
            PXLog(@"[model] WARNING: getSpoofedDeviceModel returned empty string for app: %@", bundleID);
        }
    } else {
        // Just log that we saw a model check but didn't spoof it
        logDeviceModelAccess("uname", bundleID);
    }
    
    return ret;
}

// Hook for sysctlbyname - another common way to get device model
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // First, we need to log that this call happened
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if we should intercept this call
    BOOL isHWMachine = (name && (strcmp(name, "hw.machine") == 0));
    BOOL isHWModel = (name && (strcmp(name, "hw.model") == 0));
    
    if (isHWMachine || isHWModel) {
        // Make a copy of the original value for logging purposes
        char originalValue[256] = "<not available>";
        size_t originalLen = sizeof(originalValue);
        
        // Get the original value first to show before/after in logs
        int origResult = orig_sysctlbyname(name, originalValue, &originalLen, NULL, 0);
        
        if (isDeviceModelSpoofingEnabled()) {
            NSString *spoofedValue = nil;
            
            if (isHWMachine) {
                // For hw.machine, use the device model
                spoofedValue = getSpoofedDeviceModel();
            } else if (isHWModel) {
                // For hw.model, use the hw.model value
                spoofedValue = getSpoofedHWModel();
            }
            
            if (spoofedValue.length > 0 && oldp && oldlenp && *oldlenp > 0) {
                const char *valueToUse = [spoofedValue UTF8String];
                if (valueToUse) {
                    size_t valueLen = strlen(valueToUse);
                    
                    // Ensure we don't overflow the buffer
                    if (valueLen < *oldlenp) {
                        *oldlenp = valueLen + 1; // +1 for null terminator
                        memset(oldp, 0, *oldlenp);
                        strcpy(oldp, valueToUse);
                        
                        if (origResult == 0) {
                            PXLog(@"[model] Spoofed sysctlbyname %s from: %s to: %s for app: %@", 
                                  name, originalValue, valueToUse, bundleID);
                        } else {
                            PXLog(@"[model] Spoofed sysctlbyname %s to: %s for app: %@", 
                                  name, valueToUse, bundleID);
                        }
                        return 0;
                    } else {
                        PXLog(@"[model] WARNING: Spoofed value too long for sysctlbyname buffer");
                    }
                }
            }
        }
    }
    
    // Missing sysctl keys implementation
    if (isDeviceModelSpoofingEnabled()) {
        if (strcmp(name, "kern.hostname") == 0) {
           // Spoof hostname to obscure real device name
           const char *fakeHostname = "iPhone";
           NSString *spoofedName = nil;
           // Try to use spoofed device name if available (reuse logic from UIDevice.name hook if possible, or simplified here)
            // Simplified: "iPhone" or model name
           NSString *model = getSpoofedDeviceModel();
           if (model) spoofedName = model; // e.g. "iPhone14,2"
           else spoofedName = @"iPhone";
           
           fakeHostname = [spoofedName UTF8String];
           
           if (oldp && oldlenp) {
               size_t len = strlen(fakeHostname) + 1;
               if (*oldlenp >= len) {
                   *oldlenp = len;
                   strcpy((char *)oldp, fakeHostname);
                   return 0;
               }
           }
        }
        
        if (strcmp(name, "kern.ostype") == 0) {
            const char *val = "Darwin";
            if (oldp && oldlenp) {
                size_t len = strlen(val) + 1;
                if (*oldlenp >= len) {
                    *oldlenp = len;
                    strcpy((char *)oldp, val);
                    return 0;
                }
            }
        }
        
        if (strcmp(name, "hw.physicalcpu") == 0 || strcmp(name, "hw.logicalcpu") == 0 || 
            strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
            // Simple mapping for cores based on model generation
            int cores = 2; // Default
            NSString *model = getSpoofedDeviceModel();
            if (model) {
                 if ([model hasPrefix:@"iPhone8"] || [model hasPrefix:@"iPhone9"] || [model hasPrefix:@"iPhone10"]) cores = 2; // 6s, 7, 8, X (Efficiency cores hidden usually? No, sysctl reports simple count)
                 // Actually:
                 // A9: 2
                 // A10: 2 (Fusion, only 2 active at once perceived strictly? or 4? Usually reports 2 big)
                 // A11 (iPhone 8/X): 6 (2 Big + 4 Little) -> Sysctl logical usually reports 6?
                 // Let's use a safe baseline or map properly.
                 // A11+: 6 cores
                 if ([model hasPrefix:@"iPhone10"]) cores = 6;
                 if ([model hasPrefix:@"iPhone11"]) cores = 6;
                 if ([model hasPrefix:@"iPhone12"]) cores = 6;
                 if ([model hasPrefix:@"iPhone13"]) cores = 6;
                 if ([model hasPrefix:@"iPhone14"]) cores = 6;
                 if ([model hasPrefix:@"iPad"]) cores = 8; // M1/M2 usually 8
            }
            
            // Allow override logic if you had it, for now hardcoded safe spoof
            if (oldp && oldlenp) {
                if (*oldlenp == sizeof(int)) {
                    *(int *)oldp = cores;
                    return 0;
                } else if (*oldlenp == sizeof(int64_t)) {
                    *(int64_t *)oldp = cores;
                    return 0;
                }
            }
        }
    }
    
    // For all other cases, pass through to the original function
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// Hook for sysctl (array-based) - critical for older apps/low-level checks
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctl) {
        // Try to load if not already loaded (should happen in ctor but safety first)
        void *sysctlPtr = dlsym(RTLD_DEFAULT, "sysctl");
        if (sysctlPtr) {
            orig_sysctl = (int (*)(int *, u_int, void *, size_t *, void *, size_t))sysctlPtr;
        } else {
            return -1; // Can't call original
        }
    }
    
    // Safety check
    if (!name) return -1;
    
    // Get the bundle ID first to determine if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }
    
    // Safety: if caller passes NULL out pointers, don't interfere
    if (!oldp || !oldlenp) {
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    }
    
    // Check if this is a hardware model query: CTL_HW (6) + HW_MACHINE (1) or HW_MODEL (2)
    BOOL isHWMachine = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 1 /*HW_MACHINE*/);
    BOOL isHWModel = (namelen >= 2 && name[0] == 6 /*CTL_HW*/ && name[1] == 2 /*HW_MODEL*/);
    BOOL isModelQuery = isHWMachine || isHWModel;
    
    // Store original value for logging if needed
    char originalValue[256] = "<not available>";
    
    if (isModelQuery && oldp && oldlenp && *oldlenp > 0) {
        // Make a copy of oldp and oldlenp to get original value
        void *origBuf = malloc(*oldlenp);
        if (origBuf) {
            size_t origLen = *oldlenp;
            int origResult = orig_sysctl(name, namelen, origBuf, &origLen, NULL, 0);
            if (origResult == 0) {
                strlcpy(originalValue, origBuf, sizeof(originalValue));
            }
            free(origBuf);
        }
    }
    
    // Call original function
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    
    // If it failed or not a query we care about, return
    if (ret != 0 || !isModelQuery) {
        return ret;
    }
    
    // Spoof if enabled
    if (isDeviceModelSpoofingEnabled()) {
        if (oldp && oldlenp && *oldlenp > 0) {
            NSString *spoofedValue = nil;
            
            if (isHWMachine) {
                spoofedValue = getSpoofedDeviceModel();
            } else if (isHWModel) {
                spoofedValue = getSpoofedHWModel();
            }
            
            if (spoofedValue.length > 0) {
                const char *valueToUse = [spoofedValue UTF8String];
                if (valueToUse) {
                    size_t valueLen = strlen(valueToUse);
                    
                    if (valueLen < *oldlenp) {
                        memset(oldp, 0, *oldlenp);
                        strcpy(oldp, valueToUse);
                        PXLog(@"[model] Spoofed sysctl CTL_HW %@ from %s to: %s for app: %@", 
                             isHWMachine ? @"hw.machine" : @"hw.model", originalValue, valueToUse, bundleID);
                    } else {
                        PXLog(@"[model] WARNING: Spoofed value too long for sysctl buffer");
                    }
                }
            } else {
                PXLog(@"[model] WARNING: Failed to get spoofed value for %@", 
                     isHWMachine ? @"hw.machine" : @"hw.model");
            }
        }
    } else {
        // Log access
        PXLog(@"[model] App %@ checked sysctl CTL_HW %@: %s", 
              bundleID, isHWMachine ? @"hw.machine" : @"hw.model", originalValue);
    }
    
    return ret;
}

// Hook for IOKit device property - used by some apps to get detailed device info
static CFTypeRef hook_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    // Call original first to avoid unnecessary operations
    CFTypeRef result = orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if this is a device property we want to spoof
    if (key) {
        // Check for various model-related keys
        BOOL isModelKey = 
            (CFStringCompare(key, CFSTR("model"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) ||
            (CFStringCompare(key, CFSTR("device-model"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) ||
            (CFStringCompare(key, CFSTR("hw.machine"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
            
        // Check for board-id related keys
        BOOL isBoardIDKey = 
            (CFStringCompare(key, CFSTR("board-id"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) ||
            (CFStringCompare(key, CFSTR("BoardId"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
            
        // Check for hw.model related keys
        BOOL isHWModelKey = 
            (CFStringCompare(key, CFSTR("hw.model"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) ||
            (CFStringCompare(key, CFSTR("HWModel"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
        
        if (isDeviceModelSpoofingEnabled()) {
            // Handle device model spoofing
            if (isModelKey) {
                // Convert the original result to a string for logging
                NSString *originalModel = nil;
                if (result && CFGetTypeID(result) == CFStringGetTypeID()) {
                    originalModel = (__bridge NSString *)result;
                }
                
                NSString *spoofedModel = getSpoofedDeviceModel();
                
                if (spoofedModel.length > 0) {
                    // If we already have a result, release it since we're replacing it
                    if (result) {
                        CFRelease(result);
                    }
                    
                    // Create a new CFString with our spoofed model
                    result = CFStringCreateWithCString(kCFAllocatorDefault, [spoofedModel UTF8String], kCFStringEncodingUTF8);
                    PXLog(@"[model] Spoofed IOKit property '%@' from: %@ to: %@ for app: %@", 
                         (__bridge NSString *)key, originalModel ?: @"<nil>", spoofedModel, bundleID);
                } else {
                    PXLog(@"[model] WARNING: getSpoofedDeviceModel returned empty for IOKit property: %@", 
                         (__bridge NSString *)key);
                }
            }
            // Handle board-id spoofing
            else if (isBoardIDKey) {
                // Convert the original result to a string for logging
                NSString *originalBoardID = nil;
                if (result && CFGetTypeID(result) == CFStringGetTypeID()) {
                    originalBoardID = (__bridge NSString *)result;
                } else if (result && CFGetTypeID(result) == CFDataGetTypeID()) {
                    // Some properties might be returned as data
                    CFDataRef dataRef = (CFDataRef)result;
                    NSData *data = (__bridge NSData *)dataRef;
                    originalBoardID = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                }
                
                NSString *spoofedBoardID = getSpoofedBoardID();
                
                if (spoofedBoardID.length > 0) {
                    // If we already have a result, release it since we're replacing it
                    if (result) {
                        CFRelease(result);
                    }
                    
                    // Create a new CFString with our spoofed board ID
                    result = CFStringCreateWithCString(kCFAllocatorDefault, [spoofedBoardID UTF8String], kCFStringEncodingUTF8);
                    PXLog(@"[model] Spoofed IOKit board-id property '%@' from: %@ to: %@ for app: %@", 
                         (__bridge NSString *)key, originalBoardID ?: @"<nil>", spoofedBoardID, bundleID);
                } else {
                    PXLog(@"[model] WARNING: getSpoofedBoardID returned empty for IOKit property: %@", 
                         (__bridge NSString *)key);
                }
            }
            // Handle hw.model spoofing
            else if (isHWModelKey) {
                // Convert the original result to a string for logging
                NSString *originalHWModel = nil;
                if (result && CFGetTypeID(result) == CFStringGetTypeID()) {
                    originalHWModel = (__bridge NSString *)result;
                } else if (result && CFGetTypeID(result) == CFDataGetTypeID()) {
                    // Some properties might be returned as data
                    CFDataRef dataRef = (CFDataRef)result;
                    NSData *data = (__bridge NSData *)dataRef;
                    originalHWModel = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                }
                
                NSString *spoofedHWModel = getSpoofedHWModel();
                
                if (spoofedHWModel.length > 0) {
                    // If we already have a result, release it since we're replacing it
                    if (result) {
                        CFRelease(result);
                    }
                    
                    // Create a new CFString with our spoofed hw.model
                    result = CFStringCreateWithCString(kCFAllocatorDefault, [spoofedHWModel UTF8String], kCFStringEncodingUTF8);
                    PXLog(@"[model] Spoofed IOKit hw-model property '%@' from: %@ to: %@ for app: %@", 
                         (__bridge NSString *)key, originalHWModel ?: @"<nil>", spoofedHWModel, bundleID);
                } else {
                    PXLog(@"[model] WARNING: getSpoofedHWModel returned empty for IOKit property: %@", 
                         (__bridge NSString *)key);
                }
            }
        } else if (isModelKey || isBoardIDKey || isHWModelKey) {
            // Just log that we saw a property check but didn't spoof it
            NSString *originalValue = nil;
            if (result && CFGetTypeID(result) == CFStringGetTypeID()) {
                originalValue = (__bridge NSString *)result;
            } else if (result && CFGetTypeID(result) == CFDataGetTypeID()) {
                // Some properties might be returned as data
                CFDataRef dataRef = (CFDataRef)result;
                NSData *data = (__bridge NSData *)dataRef;
                originalValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            }
            
            PXLog(@"[model] App %@ checked IOKit property '%@' value: %@", 
                  bundleID, (__bridge NSString *)key, originalValue ?: @"<nil>");
        }
    }
    
    return result;
}

// MGCopyAnswer hook for device model
%hookf(NSString *, MGCopyAnswer, CFStringRef property) {
    if (!property) {
        return %orig; // Handle null property case
    }
    
    NSString *propertyString = (__bridge NSString *)property;
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Comprehensive list of hardware model identifier properties
    static NSSet *modelProperties = nil;
    static NSSet *boardIDProperties = nil;
    static NSSet *hwModelProperties = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        modelProperties = [NSSet setWithArray:@[
            @"HWModelStr",
            @"DeviceName",
            @"ProductType",
            @"ProductModel",
            @"HardwareModel",
            @"ModelNumber",
            @"DeviceClass",
            @"DeviceVariant"
        ]];
        
        boardIDProperties = [NSSet setWithArray:@[
            @"BoardId",
            @"board-id"
        ]];
        
        hwModelProperties = [NSSet setWithArray:@[
            @"hw-model",
            @"HWModel"
        ]];
    });
    
    BOOL isModelProperty = [modelProperties containsObject:propertyString];
    BOOL isBoardIDProperty = [boardIDProperties containsObject:propertyString];
    BOOL isHWModelProperty = [hwModelProperties containsObject:propertyString];
    
    // Get the original value first for logging
    NSString *originalValue = %orig;
    
    // Check if device model spoofing is enabled
    if (isDeviceModelSpoofingEnabled()) {
        // Handle device model properties
        if (isModelProperty) {
            // Log regardless of whether spoofing is enabled
            PXLog(@"[model] MGCopyAnswer(%@) called by app: %@ - original value: %@", 
                propertyString, currentBundleID, originalValue ?: @"<nil>");
            
            NSString *spoofedModel = getSpoofedDeviceModel();
            
            if (spoofedModel.length > 0) {
                PXLog(@"[model] Spoofed MGCopyAnswer %@ from: %@ to: %@ for app: %@", 
                    propertyString, originalValue ?: @"<nil>", spoofedModel, currentBundleID);
                return [spoofedModel copy];
            } else {
                PXLog(@"[model] WARNING: getSpoofedDeviceModel returned empty for MGCopyAnswer property: %@", 
                    propertyString);
            }
        }
        // Handle board ID properties
        else if (isBoardIDProperty) {
            PXLog(@"[model] MGCopyAnswer BoardID(%@) called by app: %@ - original value: %@", 
                propertyString, currentBundleID, originalValue ?: @"<nil>");
            
            NSString *spoofedBoardID = getSpoofedBoardID();
            
            if (spoofedBoardID.length > 0) {
                PXLog(@"[model] Spoofed MGCopyAnswer %@ from: %@ to: %@ for app: %@", 
                    propertyString, originalValue ?: @"<nil>", spoofedBoardID, currentBundleID);
                return [spoofedBoardID copy];
            }
        }
        // Handle hw.model properties
        else if (isHWModelProperty) {
            PXLog(@"[model] MGCopyAnswer HWModel(%@) called by app: %@ - original value: %@", 
                propertyString, currentBundleID, originalValue ?: @"<nil>");
            
            NSString *spoofedHWModel = getSpoofedHWModel();
            
            if (spoofedHWModel.length > 0) {
                PXLog(@"[model] Spoofed MGCopyAnswer %@ from: %@ to: %@ for app: %@", 
                    propertyString, originalValue ?: @"<nil>", spoofedHWModel, currentBundleID);
                return [spoofedHWModel copy];
            }
        }
    }
    
    // For all other properties, pass through to the original implementation
    return originalValue;
}

// Hook for UIDevice methods - many apps use combinations of these
%hook UIDevice

- (NSString *)model {
    NSString *originalModel = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!bundleID) {
        return originalModel;
    }
    
    // Always log access to help with debugging
    PXLog(@"[model] App %@ checked UIDevice model: %@", bundleID, originalModel);
    
    // Only spoof if enabled for this app
    if (isDeviceModelSpoofingEnabled()) {
        NSString *spoofedModel = getSpoofedDeviceModel();
        if (spoofedModel.length > 0) {
            PXLog(@"[model] Spoofing UIDevice model from %@ to %@ for app: %@", 
                  originalModel, spoofedModel, bundleID);
            return spoofedModel;
        }
    }
    
    return originalModel;
}

- (NSString *)name {
    // Enable spoofing for device name
    NSString *originalName = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!bundleID) {
        return originalName;
    }
    
    // Always log access
    PXLog(@"[model] App %@ checked UIDevice name: %@", bundleID, originalName);
    
    if (isDeviceModelSpoofingEnabled()) {
        // For privacy, we often want to spoof the device name to a generic one
        // or a custom name if configured
        NSString *spoofedName = nil;
        
        // Try to get custom name from profile
        // Using existing helper if available or implementing a basic lookup
        @try {
            // Re-use logic to find profile settings
            NSString *profilesPath = @"/var/mobile/Library/WeaponX/Profiles";
            NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
            NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
            NSString *profileId = centralInfo[@"ProfileId"];
            
            if (profileId) {
                NSString *identityDir = [profilesPath stringByAppendingPathComponent:profileId];
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                
                spoofedName = deviceIds[@"DeviceName"];
            }
        } @catch (NSException *e) {}
        
        // Fallback to generic name if no custom name set
        if (!spoofedName || spoofedName.length == 0) {
            spoofedName = @"iPhone";
        }
        
        PXLog(@"[model] Spoofing UIDevice name from %@ to %@ for app: %@", 
              originalName, spoofedName, bundleID);
        return spoofedName;
    }
    
    return originalName;
}

- (NSString *)systemName {
    // Just log access but don't spoof - this is iOS, not device model
    NSString *originalName = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (bundleID && isDeviceModelSpoofingEnabled()) {
        PXLog(@"[model] App %@ checked UIDevice systemName: %@", bundleID, originalName);
    }
    
    return originalName;
}

- (NSString *)localizedModel {
    NSString *originalModel = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    if (!bundleID) {
        return originalModel;
    }
    
    // Always log access to help with debugging
    PXLog(@"[model] App %@ checked UIDevice localizedModel: %@", bundleID, originalModel);
    
    // Only spoof if enabled for this app
    if (isDeviceModelSpoofingEnabled()) {
        NSString *spoofedModel = getSpoofedDeviceModel();
        if (spoofedModel.length > 0) {
            PXLog(@"[model] Spoofing UIDevice localizedModel from %@ to %@ for app: %@", 
                  originalModel, spoofedModel, bundleID);
            return spoofedModel;
        }
    }
    
    return originalModel;
}

%end

// Add NSDictionary+machineName hook - a common extension in iOS apps to map device model codes
%hook NSDictionary

+ (NSDictionary *)dictionaryWithContentsOfURL:(NSURL *)url {
    NSDictionary *result = %orig;
    
    if (isDeviceModelSpoofingEnabled() && url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"device"] || [urlStr containsString:@"model"]) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            PXLog(@"[model] App %@ loaded dictionary with URL: %@", bundleID, urlStr);
        }
    }
    
    return result;
}

%end



// Helper method to log device model access
static void logDeviceModelAccess(const char* method, NSString* bundleID) {
    static NSMutableSet *loggedApps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggedApps = [NSMutableSet set];
    });
    
    // Create a unique key for this method+bundleID combination
    NSString *accessKey = [NSString stringWithFormat:@"%s-%@", method, bundleID];
    
    // Only log once per method+bundleID combination to avoid log spam
    @synchronized(loggedApps) {
        if (![loggedApps containsObject:accessKey]) {
            // IMPORTANT: Don't call uname() directly here as it could cause infinite recursion
            // Instead, log a simple message about the access
            NSString *spoofedModel = getSpoofedDeviceModel();
            PXLog(@"[model] App %@ accessed device model via %s - Spoofed: %@", 
                  bundleID, method, spoofedModel ?: @"Not set");
            
            [loggedApps addObject:accessKey];
        }
    }
}

%ctor {
    @autoreleasepool {
        PXLog(@"[model] Initializing device model spoofing hooks");
        
        // CRITICAL SAFETY CHECK: Only initialize hooks if we can get a valid bundle ID
        // This prevents hooks from running during early boot process or in system services
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!currentBundleID) {
            PXLog(@"[model] No bundle ID available, not initializing device model hooks");
            return;
        }
        
        // Don't hook system processes
        if ([currentBundleID hasPrefix:@"com.apple."] || 
            [currentBundleID isEqualToString:@"com.hydra.projectx"] || 
            [currentBundleID isEqualToString:@"com.hydra.weaponx"]) {
            PXLog(@"[model] Not hooking system process: %@", currentBundleID);
            return;
        }
        
        // Check if this app is even enabled for spoofing before initializing hooks
        IdentifierManager *manager = [%c(IdentifierManager) sharedManager];
        if (!manager || ![manager isApplicationEnabled:currentBundleID]) {
            PXLog(@"[model] App %@ is not enabled for spoofing, not initializing hooks", currentBundleID);
            return;
        }
        
        // Use our optimized check function for determining if this app should be hooked
        if (!isDeviceModelSpoofingEnabled()) {
            PXLog(@"[model] Device model spoofing not enabled for app %@, not initializing hooks", currentBundleID);
            return;
        } else {
            PXLog(@"[model] Device model spoofing is enabled for app %@", currentBundleID);
        }
        
        // Test if we can retrieve a spoofed model before proceeding
        NSString *testModel = getSpoofedDeviceModel();
        if (!testModel) {
            PXLog(@"[model] WARNING: Could not retrieve spoofed model, not initializing hooks");
            return;
        }
        
        PXLog(@"[model] Successfully retrieved spoofed model: %@", testModel);

        // Initialize the hooks with error handling
        @try {
            MSHookFunction(uname, hook_uname, (void **)&orig_uname);
            PXLog(@"[model] Hooked uname() successfully");
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking uname(): %@", e);
        }
        
        @try {
            MSHookFunction(sysctlbyname, hook_sysctlbyname, (void **)&orig_sysctlbyname);
            PXLog(@"[model] Hooked sysctlbyname() successfully");
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking sysctlbyname(): %@", e);
        }
        
        @try {
            void *sysctlPtr = dlsym(RTLD_DEFAULT, "sysctl");
            if (sysctlPtr) {
                MSHookFunction(sysctlPtr, (void *)hook_sysctl, (void **)&orig_sysctl);
                PXLog(@"[model] Hooked sysctl() successfully");
            } else {
                PXLog(@"[model] Could not find sysctl symbol");
            }
        } @catch (NSException *e) {
            PXLog(@"[model] ERROR hooking sysctl(): %@", e);
        }
        
        // Look up IOKit functions dynamically
        void *IOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (IOKitHandle) {
            void *IORegEntryCreateCFPropertyPtr = dlsym(IOKitHandle, "IORegistryEntryCreateCFProperty");
            if (IORegEntryCreateCFPropertyPtr) {
                @try {
                    MSHookFunction(IORegEntryCreateCFPropertyPtr, (void *)hook_IORegistryEntryCreateCFProperty, (void **)&orig_IORegistryEntryCreateCFProperty);
                    PXLog(@"[model] Hooked IORegistryEntryCreateCFProperty successfully");
                } @catch (NSException *e) {
                    PXLog(@"[model] ERROR hooking IORegistryEntryCreateCFProperty: %@", e);
                }
            } else {
                PXLog(@"[model] Could not find IORegistryEntryCreateCFProperty symbol");
            }
            dlclose(IOKitHandle);
        } else {
            PXLog(@"[model] Could not open IOKit framework");
        }
    }
}
