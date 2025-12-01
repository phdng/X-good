#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProjectXLogging.h"
#import "IdentifierManager.h"
#import "SystemUUIDManager.h"
#import "DyldCacheUUIDManager.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/dyld_images.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <pthread.h>
#import "ProfileManager.h"
#import <substrate.h>
#import "AppScopeManager.h"
// Macro for iOS version checking
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

// Global variables to track state
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 600.0; // 10 minutes for better performance
static dispatch_queue_t cacheQueue = nil; // Queue for thread-safe access to cache
static BOOL isInitialized = NO;


// Direct check for SystemBootUUID being enabled
static BOOL isSystemBootUUIDEnabled() {
    // Check settings file directly
    NSArray *preferencesLocations = @[
        @"/var/jb/var/mobile/Library/Preferences",
        @"/var/jb/private/var/mobile/Library/Preferences",
        @"/var/mobile/Library/Preferences"
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSString *prefsPath in preferencesLocations) {
        NSString *settingsPath = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
        if ([fileManager fileExistsAtPath:settingsPath]) {
            NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
            NSDictionary *enabledIdentifiers = settingsDict[@"EnabledIdentifiers"];
            
            if (enabledIdentifiers) {
                BOOL isEnabled = [enabledIdentifiers[@"SystemBootUUID"] boolValue];
                PXLog(@"[WeaponX] 🔍 SystemBootUUID enabled status from plist: %@", isEnabled ? @"YES" : @"NO");
                return isEnabled;
            }
        }
    }
    
    PXLog(@"[WeaponX] ⚠️ Could not find settings.plist file, assuming SystemBootUUID is disabled");
    return NO;
}

// Direct check for DyldCacheUUID being enabled
static BOOL isDyldCacheUUIDEnabled() {
    // Check settings file directly
    NSArray *preferencesLocations = @[
        @"/var/jb/var/mobile/Library/Preferences",
        @"/var/jb/private/var/mobile/Library/Preferences",
        @"/var/mobile/Library/Preferences"
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSString *prefsPath in preferencesLocations) {
        NSString *settingsPath = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
        if ([fileManager fileExistsAtPath:settingsPath]) {
            NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
            NSDictionary *enabledIdentifiers = settingsDict[@"EnabledIdentifiers"];
            
            if (enabledIdentifiers) {
                BOOL isEnabled = [enabledIdentifiers[@"DyldCacheUUID"] boolValue];
                PXLog(@"[WeaponX] 🔍 DyldCacheUUID enabled status from plist: %@", isEnabled ? @"YES" : @"NO");
                return isEnabled;
            }
        }
    }
    
    PXLog(@"[WeaponX] ⚠️ Could not find settings.plist file, assuming DyldCacheUUID is disabled");
    return NO;
}

// Add functions to get spoofed UUIDs from managers
static NSString *getSpoofedSystemBootUUID() {
    @try {
        // Use the SystemUUIDManager for consistent values across the app and hooks
        SystemUUIDManager *manager = [SystemUUIDManager sharedManager];
        if (!manager) {
            // Generate a safer fallback if manager is unavailable
            return [[NSUUID UUID] UUIDString];
        }
        
        NSString *uuid = [manager currentBootUUID];
        
        // Validate UUID format
        if (uuid && uuid.length > 0 && ![uuid isEqualToString:@"(null)"]) {
            // Check if it's a valid UUID format (basic validation)
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                    options:NSRegularExpressionCaseInsensitive 
                                                                                      error:nil];
            if ([regex numberOfMatchesInString:uuid 
                                       options:0 
                                         range:NSMakeRange(0, uuid.length)] > 0) {
                return uuid;
            }
        }
        
        
        NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
        
        if (identityDir) {
            // First try the combined device_ids.plist
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            NSString *value = deviceIds[@"SystemBootUUID"];
            
            if (value && value.length > 0 && ![value isEqualToString:@"(null)"]) {
                // Basic validation for UUID format
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                        options:NSRegularExpressionCaseInsensitive 
                                                                                          error:nil];
                if ([regex numberOfMatchesInString:value 
                                           options:0 
                                             range:NSMakeRange(0, value.length)] > 0) {
                    PXLog(@"[WeaponX] 🔄 Got SystemBootUUID from device_ids.plist: %@", value);
                    // Update the manager for future consistency
                    if ([manager respondsToSelector:@selector(setCurrentBootUUID:)]) {
                        [manager setCurrentBootUUID:value];
                    }
                    return value;
                }
            }
            
            // Try the specific uuid file
            NSString *uuidPath = [identityDir stringByAppendingPathComponent:@"system_boot_uuid.plist"];
            NSDictionary *uuidDict = [NSDictionary dictionaryWithContentsOfFile:uuidPath];
            if (uuidDict && uuidDict[@"value"] && [uuidDict[@"value"] length] > 0 && ![uuidDict[@"value"] isEqualToString:@"(null)"]) {
                // Validate UUID format
                NSString *uuidValue = uuidDict[@"value"];
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                        options:NSRegularExpressionCaseInsensitive 
                                                                                          error:nil];
                if ([regex numberOfMatchesInString:uuidValue 
                                           options:0 
                                             range:NSMakeRange(0, uuidValue.length)] > 0) {
                    PXLog(@"[WeaponX] 🔄 Got SystemBootUUID from system_boot_uuid.plist: %@", uuidValue);
                    // Update the manager for future consistency
                    if ([manager respondsToSelector:@selector(setCurrentBootUUID:)]) {
                        [manager setCurrentBootUUID:uuidValue];
                    }
                    return uuidValue;
                }
            }
        }
        
        // If we still don't have a UUID, generate a new one rather than using zeros
        uuid = [[NSUUID UUID] UUIDString];
        PXLog(@"[WeaponX] 🔄 Generated fallback UUID: %@", uuid);
        
        // Store this for future consistency
        if ([manager respondsToSelector:@selector(setCurrentBootUUID:)]) {
            [manager setCurrentBootUUID:uuid];
        }
        
        return uuid;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in getSpoofedSystemBootUUID: %@", exception);
        return [[NSUUID UUID] UUIDString];
    }
}

static NSString *getSpoofedDyldCacheUUID() {
    @try {
        // Use the DyldCacheUUIDManager for consistent values across the app and hooks
        DyldCacheUUIDManager *manager = [DyldCacheUUIDManager sharedManager];
        if (!manager) {
            // Generate a safer fallback if manager is unavailable
            return [[NSUUID UUID] UUIDString];
        }
        
        NSString *uuid = [manager currentDyldCacheUUID];
        
        // Validate UUID format
        if (uuid && uuid.length > 0 && ![uuid isEqualToString:@"(null)"]) {
            // Check if it's a valid UUID format (basic validation)
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                    options:NSRegularExpressionCaseInsensitive 
                                                                                      error:nil];
            if ([regex numberOfMatchesInString:uuid 
                                       options:0 
                                         range:NSMakeRange(0, uuid.length)] > 0) {
                return uuid;
            }
        }
        
        // Try to read directly from plist files
 
        
        NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
        
        if (identityDir) {
            // First try the combined device_ids.plist
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            NSString *value = deviceIds[@"DyldCacheUUID"];
            
            if (value && value.length > 0 && ![value isEqualToString:@"(null)"]) {
                // Basic validation for UUID format
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                        options:NSRegularExpressionCaseInsensitive 
                                                                                          error:nil];
                if ([regex numberOfMatchesInString:value 
                                           options:0 
                                             range:NSMakeRange(0, value.length)] > 0) {
                    PXLog(@"[WeaponX] 🔄 Got DyldCacheUUID from device_ids.plist: %@", value);
                    // Update the manager for future consistency
                    if ([manager respondsToSelector:@selector(setCurrentDyldCacheUUID:)]) {
                        [manager setCurrentDyldCacheUUID:value];
                    }
                    return value;
                }
            }
            
            // Try the specific uuid file
            NSString *uuidPath = [identityDir stringByAppendingPathComponent:@"dyld_cache_uuid.plist"];
            NSDictionary *uuidDict = [NSDictionary dictionaryWithContentsOfFile:uuidPath];
            if (uuidDict && uuidDict[@"value"] && [uuidDict[@"value"] length] > 0 && ![uuidDict[@"value"] isEqualToString:@"(null)"]) {
                // Validate UUID format
                NSString *uuidValue = uuidDict[@"value"];
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                        options:NSRegularExpressionCaseInsensitive 
                                                                                          error:nil];
                if ([regex numberOfMatchesInString:uuidValue 
                                           options:0 
                                             range:NSMakeRange(0, uuidValue.length)] > 0) {
                    PXLog(@"[WeaponX] 🔄 Got DyldCacheUUID from dyld_cache_uuid.plist: %@", uuidValue);
                    // Update the manager for future consistency
                    if ([manager respondsToSelector:@selector(setCurrentDyldCacheUUID:)]) {
                        [manager setCurrentDyldCacheUUID:uuidValue];
                    }
                    return uuidValue;
                }
            }
        }
        
        // If we still don't have a UUID, generate a new one rather than using zeros
        uuid = [[NSUUID UUID] UUIDString];
        PXLog(@"[WeaponX] 🔄 Generated fallback UUID: %@", uuid);
        
        // Store this for future consistency
        if ([manager respondsToSelector:@selector(setCurrentDyldCacheUUID:)]) {
            [manager setCurrentDyldCacheUUID:uuid];
        }
        
        return uuid;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in getSpoofedDyldCacheUUID: %@", exception);
        return [[NSUUID UUID] UUIDString];
    }
}

#pragma mark - NSUUID Hooks

%hook NSUUID

// Hook NSUUID's UUID method to intercept system UUID requests
+ (instancetype)UUID {
    @try {
        // Use direct check instead of manager
        if (isSystemBootUUIDEnabled()) {
            NSString *bootUUID = getSpoofedSystemBootUUID();
            if (bootUUID && bootUUID.length > 0) {
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:bootUUID];
                if (uuid) {
                    PXLog(@"[WeaponX] 🔄 Spoofing NSUUID with: %@", bootUUID);
                    return uuid;
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in NSUUID+UUID: %@", exception);
    }
    
    return %orig;
}

// Hook UUIDString method to intercept UUID string requests
- (NSString *)UUIDString {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
            // Use direct check instead of manager
            if (isSystemBootUUIDEnabled()) {
                // Only spoof if this is a system UUID (we can check by comparing with the actual system UUID)
                uuid_t bytes;
                [self getUUIDBytes:bytes];
                
                // Create a string from the original UUID bytes
                CFUUIDRef cfuuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, *((CFUUIDBytes *)bytes));
                if (!cfuuid) {
                    return %orig;
                }
                
                NSString *originalUUID = (NSString *)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, cfuuid));
                CFRelease(cfuuid);
                
                // Determine if this is likely a system UUID (can be enhanced with more checks)
                io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
                if (ioRegistryRoot) {
                    CFStringRef platformUUID = (CFStringRef)IORegistryEntryCreateCFProperty(
                        ioRegistryRoot, 
                        CFSTR("IOPlatformUUID"), 
                        kCFAllocatorDefault, 
                        0);
                    IOObjectRelease(ioRegistryRoot);
                    
                    if (platformUUID) {
                        NSString *systemUUID = (__bridge_transfer NSString *)platformUUID;
                        if ([originalUUID isEqualToString:systemUUID]) {
                            NSString *bootUUID = getSpoofedSystemBootUUID();
                            if (bootUUID && bootUUID.length > 0) {
                                PXLog(@"[WeaponX] 🔄 Spoofing UUIDString with: %@", bootUUID);
                                return bootUUID;
                            }
                        }
                    }
                }
            }
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in UUIDString: %@", exception);
    }
    
    return %orig;
}

// Add additional initialization methods beyond what we already hook
- (instancetype)initWithUUIDBytes:(const uuid_t)bytes {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (isSystemBootUUIDEnabled()) {
            // Create string from bytes to see if it matches the system UUID
            CFUUIDRef cfuuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, *((CFUUIDBytes *)bytes));
            if (!cfuuid) {
                return %orig;
            }
            
            NSString *originalUUID = (NSString *)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, cfuuid));
            CFRelease(cfuuid);
            
            // Check if this might be system UUID
            io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
            if (ioRegistryRoot) {
                CFStringRef platformUUID = (CFStringRef)IORegistryEntryCreateCFProperty(
                    ioRegistryRoot, 
                    CFSTR("IOPlatformUUID"), 
                    kCFAllocatorDefault, 
                    0);
                IOObjectRelease(ioRegistryRoot);
                
                if (platformUUID) {
                    NSString *systemUUID = (__bridge_transfer NSString *)platformUUID;
                    if ([originalUUID isEqualToString:systemUUID]) {
                        NSString *bootUUID = getSpoofedSystemBootUUID();
                        if (bootUUID && bootUUID.length > 0) {
                            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:bootUUID];
                            PXLog(@"[WeaponX] 🔄 Spoofing NSUUID initWithUUIDBytes with: %@", bootUUID);
                            return uuid ?: %orig;
                        }
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in NSUUID initWithUUIDBytes: %@", exception);
    }
    
    return %orig;
}

// Add this to catch UIDevice's identifierForVendor
- (NSString *)description {
    NSString *origDescription = %orig;
    
    @try {
        // Check if we need to spoof
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (isSystemBootUUIDEnabled()) {
            // Generally we don't want to modify all descriptions, only ones that might be system UUIDs
            // We'll check if the description matches the UUID pattern first
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" 
                                                                                  options:NSRegularExpressionCaseInsensitive 
                                                                                    error:nil];
            if ([regex numberOfMatchesInString:origDescription options:0 range:NSMakeRange(0, origDescription.length)] > 0) {
                // It's a UUID string, now check if it's the system UUID
                io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
                if (ioRegistryRoot) {
                    CFStringRef platformUUID = (CFStringRef)IORegistryEntryCreateCFProperty(
                        ioRegistryRoot, 
                        CFSTR("IOPlatformUUID"), 
                        kCFAllocatorDefault, 
                        0);
                    IOObjectRelease(ioRegistryRoot);
                    
                    if (platformUUID) {
                        NSString *systemUUID = (__bridge_transfer NSString *)platformUUID;
                        if ([origDescription isEqualToString:systemUUID]) {
                            NSString *bootUUID = getSpoofedSystemBootUUID();
                            if (bootUUID && bootUUID.length > 0) {
                                PXLog(@"[WeaponX] 🔄 Spoofing NSUUID description from %@ to %@", origDescription, bootUUID);
                                return bootUUID;
                            }
                        }
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in NSUUID description: %@", exception);
    }
    
    return origDescription;
}

%end

#pragma mark - NSString UUID Hooks

%hook NSString

+ (NSString *)stringWithUUID:(uuid_t)bytes {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Use direct check instead of manager
        if (isSystemBootUUIDEnabled()) {
            NSString *bootUUID = getSpoofedSystemBootUUID();
            if (bootUUID && bootUUID.length > 0) {
                PXLog(@"[WeaponX] 🔄 Spoofing System Boot UUID with: %@", bootUUID);
                return bootUUID;
            }
        }
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in stringWithUUID: %@", exception);
    }
    
    // Call original if we're not spoofing
    return %orig;
}

%end

#pragma mark - IOKit Platform UUID Hooks

// Hook the IOKit function to intercept platform UUID requests
%hookf(CFTypeRef, IORegistryEntryCreateCFProperty, io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    @try {
        // Check if we're looking for the platform UUID
        if (key && [(__bridge NSString *)key isEqualToString:@"IOPlatformUUID"]) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            
            // Use direct check instead of manager
            if (isSystemBootUUIDEnabled()) {
                NSString *bootUUID = getSpoofedSystemBootUUID();
                if (bootUUID && bootUUID.length > 0) {
                    PXLog(@"[WeaponX] 🔄 Spoofing IOPlatformUUID with: %@", bootUUID);
                    return (__bridge_retained CFStringRef)bootUUID;
                }
            }
        }
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in IORegistryEntryCreateCFProperty: %@", exception);
    }
    
    return %orig;
}

// Hook IORegistryEntryCreateCFProperties to intercept multiple properties at once
%hookf(IOReturn, IORegistryEntryCreateCFProperties, io_registry_entry_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, IOOptionBits options) {
    IOReturn result = %orig;
    
    @try {
        // If successful and we get properties back
        if (result == kIOReturnSuccess && properties && *properties) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            
            // Use direct check instead of manager
            if (isSystemBootUUIDEnabled()) {
                NSMutableDictionary *props = (__bridge NSMutableDictionary *)*properties;
                
                // Check if the dictionary has IOPlatformUUID
                if (props[@"IOPlatformUUID"]) {
                    NSString *bootUUID = getSpoofedSystemBootUUID();
                    if (bootUUID && bootUUID.length > 0) {
                        PXLog(@"[WeaponX] 🔄 Spoofing IOPlatformUUID in properties with: %@", bootUUID);
                        props[@"IOPlatformUUID"] = bootUUID;
                    }
                }
            }
            
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in IORegistryEntryCreateCFProperties: %@", exception);
    }
    
    return result;
}

#pragma mark - Dyld Cache UUID Hooks

// Function pointer for _dyld_get_shared_cache_uuid
static bool (*orig_dyld_get_shared_cache_uuid)(uuid_t uuid_out) = NULL;

// Replacement function for _dyld_get_shared_cache_uuid
static bool replaced_dyld_get_shared_cache_uuid(uuid_t uuid_out) {
    @try {
        // First check if we need to spoof at all
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ( !isDyldCacheUUIDEnabled() || !uuid_out) {
            // Call original if we're not spoofing
            if (orig_dyld_get_shared_cache_uuid) {
                return orig_dyld_get_shared_cache_uuid(uuid_out);
            }
            return false;
        }
        
        // Get the UUID from the manager to ensure we're consistent with other hooks
        DyldCacheUUIDManager *manager = [DyldCacheUUIDManager sharedManager];
        NSString *dyldUUID = [manager currentDyldCacheUUID];
        
        // If we got a valid UUID, use it
        if (dyldUUID && dyldUUID.length > 0) {
            // Parse UUID string
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:dyldUUID];
            if (uuid) {
                [uuid getUUIDBytes:uuid_out];
                
                // Only log occasionally to reduce spam
                static NSTimeInterval lastLogTime = 0;
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                if (now - lastLogTime > 5.0) { // Log at most every 5 seconds
                    PXLog(@"[WeaponX] 🔄 Spoofing Dyld Cache UUID with: %@", dyldUUID);
                    lastLogTime = now;
                }
                
                return true;
            }
        }
        
        // Fallback: try to get a new UUID if the manager didn't have one
        dyldUUID = getSpoofedDyldCacheUUID();
        if (dyldUUID && dyldUUID.length > 0) {
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:dyldUUID];
            if (uuid) {
                [uuid getUUIDBytes:uuid_out];
                
                // Update the manager with this UUID for future consistency
                [manager setCurrentDyldCacheUUID:dyldUUID];
                
                PXLog(@"[WeaponX] 🔄 Spoofing Dyld Cache UUID (fallback) with: %@", dyldUUID);
                return true;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in replaced_dyld_get_shared_cache_uuid: %@", exception);
    }
    
    // Call original if spoofing failed
    if (orig_dyld_get_shared_cache_uuid) {
        return orig_dyld_get_shared_cache_uuid(uuid_out);
    }
    
    return false;
}

// Additional hook for dyld_get_all_image_infos which can be used to get dyld cache info
static const struct dyld_all_image_infos* (*orig_dyld_get_all_image_infos)(void) = NULL;

// Version of the struct with only the fields we need to copy
typedef struct {
    uint32_t version;
    uint32_t infoArrayCount;
    const void* infoArray;
    const void* notification;
    bool processDetachedFromSharedRegion;
    bool libSystemInitialized;
    const void* dyldImageLoadAddress;
    void* jitInfo;
    const void* dyldVersion;
    const void* errorMessage;
    uintptr_t terminationFlags;
    void* coreSymbolicationShmPage;
    uintptr_t systemOrderFlag;
    uintptr_t uuidArrayCount;
    const void* uuidArray;
    const void* dyldAllImageInfosAddress;
    uintptr_t initialImageCount;
    uintptr_t errorKind;
    const void* errorClientOfDylibPath;
    const void* errorTargetDylibPath;
    const void* errorSymbol;
    const uuid_t* sharedCacheUUID;
    // Remaining fields are not needed for our spoofing
} simplified_dyld_all_image_infos;

// Create a thread-local storage for per-thread cache to avoid "1 image on all image" problem
static NSMutableDictionary *threadLocalCaches() {
    static NSMutableDictionary *allCaches = nil;
    static dispatch_once_t onceToken;
    static NSLock *cachesLock = nil;
    
    dispatch_once(&onceToken, ^{
        allCaches = [NSMutableDictionary dictionary];
        cachesLock = [[NSLock alloc] init];
    });
    
    [cachesLock lock];
    
    // Get current thread ID
    NSString *threadKey = [NSString stringWithFormat:@"%p", (void *)pthread_self()];
    NSMutableDictionary *threadCache = allCaches[threadKey];
    
    if (!threadCache) {
        threadCache = [NSMutableDictionary dictionary];
        allCaches[threadKey] = threadCache;
    }
    
    [cachesLock unlock];
    return threadCache;
}

// Create a copy of the image infos structure with spoofed UUID
static const struct dyld_all_image_infos* replaced_dyld_get_all_image_infos(void) {
    @try {
        const struct dyld_all_image_infos *original = orig_dyld_get_all_image_infos();
        if (!original) return NULL;
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Use direct check instead of manager
        // The compiler warns about comparing sharedCacheUUID with NULL because it's an array pointer
        // Instead, we'll check if the version is high enough to safely access this field
        if (isDyldCacheUUIDEnabled() && original->version >= 15) {
            // Using per-bundle caching to ensure consistent but unique UUIDs across apps
            DyldCacheUUIDManager *manager = [DyldCacheUUIDManager sharedManager];
            NSString *dyldUUID = [manager currentDyldCacheUUID];
            
            if (!dyldUUID || dyldUUID.length == 0) {
                // If no UUID is available, try to get one from the manager
                dyldUUID = getSpoofedDyldCacheUUID();
                if (!dyldUUID || dyldUUID.length == 0) {
                    // Fall back to original if we can't get a valid UUID
                    return original;
                }
            }
            
            // Get thread-local storage for this image info
            NSMutableDictionary *threadCache = threadLocalCaches();
            NSString *cacheKey = [NSString stringWithFormat:@"image_info_%@", bundleID];
            
            // Check if we already have a cached struct for this thread + bundle
            NSDictionary *cachedInfo = threadCache[cacheKey];
            id cachedUUIDObj = threadCache[[NSString stringWithFormat:@"uuid_%@", bundleID]];
            uuid_t *cachedUUIDPtr = NULL;
            if (cachedUUIDObj) {
                cachedUUIDPtr = (uuid_t *)[cachedUUIDObj pointerValue];
            }
            
            // Only create a new struct if needed
            if (cachedInfo && cachedUUIDPtr) {
                // Update last access time
                NSMutableDictionary *updatedCache = [cachedInfo mutableCopy];
                [updatedCache setObject:[NSDate date] forKey:@"lastAccess"];
                threadCache[cacheKey] = updatedCache;
                
                struct dyld_all_image_infos* spoofedInfos = (struct dyld_all_image_infos*)[cachedInfo[@"pointer"] pointerValue];
                
                // Replace the UUID in the original struct before returning
                if (spoofedInfos && spoofedInfos->uuidArray) {
                    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"15.0")) {
                        // Use proper struct access for dyld_uuid_info
                        struct dyld_uuid_info *uuidInfo = (struct dyld_uuid_info *)spoofedInfos->uuidArray;
                        for (int i = 0; i < original->uuidArrayCount; i++) {
                            // Use direct access to uuid field in dyld_uuid_info struct
                            if (cachedUUIDPtr) {
                                memcpy((void*)uuidInfo[i].imageUUID, cachedUUIDPtr, sizeof(uuid_t));
                            }
                        }
                    } else {
                        // For older iOS versions
                        struct dyld_uuid_info *uuidInfo = (struct dyld_uuid_info *)spoofedInfos->uuidArray;
                        if (cachedUUIDPtr) {
                            memcpy((void*)uuidInfo[0].imageUUID, cachedUUIDPtr, sizeof(uuid_t));
                        }
                    }
                }
                
                return (const struct dyld_all_image_infos*)spoofedInfos;
            }
        }
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in replaced_dyld_get_all_image_infos: %@", exception);
    }
    
    return orig_dyld_get_all_image_infos();
}

#pragma mark - Additional System UUID Methods

// Hook for gethostuuid system call
static int (*orig_gethostuuid)(uuid_t id, const struct timespec *wait);

static int replaced_gethostuuid(uuid_t id, const struct timespec *wait) {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (isSystemBootUUIDEnabled()) {
            NSString *bootUUID = getSpoofedSystemBootUUID();
            if (bootUUID && bootUUID.length > 0) {
                // Convert string UUID to bytes
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:bootUUID];
                if (uuid) {
                    [uuid getUUIDBytes:id];
                    PXLog(@"[WeaponX] 🔄 Spoofing gethostuuid with: %@", bootUUID);
                    return 0; // Success
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in replaced_gethostuuid: %@", exception);
    }
    
    // Call original if we're not spoofing
    if (orig_gethostuuid) {
        return orig_gethostuuid(id, wait);
    }
    
    return -1; // Error
}

// Hook for sysctlbyname for kern.uuid
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

static int replaced_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    @try {
        // Check if we're looking for kern.uuid
        if (name && strcmp(name, "kern.uuid") == 0) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            
            if (isSystemBootUUIDEnabled()) {
                NSString *bootUUID = getSpoofedSystemBootUUID();
                if (bootUUID && bootUUID.length > 0 && oldp && oldlenp) {
                    // Convert the UUID string to bytes
                    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:bootUUID];
                    if (uuid) {
                        uuid_t bytes;
                        [uuid getUUIDBytes:bytes];
                        
                        // Copy as much as will fit
                        size_t toCopy = MIN(*oldlenp, sizeof(uuid_t));
                        memcpy(oldp, bytes, toCopy);
                        *oldlenp = toCopy;
                        
                        PXLog(@"[WeaponX] 🔄 Spoofing sysctlbyname(kern.uuid) with: %@", bootUUID);
                        return 0; // Success
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in replaced_sysctlbyname: %@", exception);
    }
    
    // Call original
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// Hook CFUUIDCreate to also catch CF-level UUID creation
static CFUUIDRef (*orig_CFUUIDCreate)(CFAllocatorRef alloc);

static CFUUIDRef replaced_CFUUIDCreate(CFAllocatorRef alloc) {
    CFUUIDRef originalUUID = orig_CFUUIDCreate ? orig_CFUUIDCreate(alloc) : NULL;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Only hook for system UUID if we shouldn't spoof for this app or UUID spoofing is disabled
        if (!isSystemBootUUIDEnabled()) {
            return originalUUID;
        }
        
        // Convert UUID to string for logging and comparison
        NSString *originalUUIDString = nil;
        if (originalUUID) {
            CFStringRef uuidStringRef = CFUUIDCreateString(kCFAllocatorDefault, originalUUID);
            if (uuidStringRef) {
                originalUUIDString = (__bridge_transfer NSString *)uuidStringRef;
            }
        }
        
        // Get spoofed UUID
        NSString *bootUUID = getSpoofedSystemBootUUID();
        if (bootUUID && bootUUID.length > 0) {
            // Create a new UUID from our spoofed string
            CFUUIDRef spoofedUUID = CFUUIDCreateFromString(kCFAllocatorDefault, (__bridge CFStringRef)bootUUID);
            if (spoofedUUID) {
                // Release the original UUID
                if (originalUUID) {
                    CFRelease(originalUUID);
                }
                
                PXLog(@"[WeaponX] 🔄 Spoofing CFUUIDCreate from %@ to %@", originalUUIDString ?: @"nil", bootUUID);
                return spoofedUUID;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in replaced_CFUUIDCreate: %@", exception);
    }
    
    return originalUUID;
}

#pragma mark - Constructor - Additional Hooks Setup

static void setupAdditionalSystemUUIDHooks() {
    @try {
        // Hook gethostuuid system call
        void *libc = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libc) {
            void *gethostuuid_sym = dlsym(libc, "gethostuuid");
            if (gethostuuid_sym) {
                MSHookFunction(gethostuuid_sym, 
                                  (void *)replaced_gethostuuid, 
                                  (void **)&orig_gethostuuid);
            } else {
                PXLog(@"[WeaponX] ⚠️ Could not find gethostuuid symbol");
            }
            
            // Hook sysctlbyname
            void *sysctlbyname_sym = dlsym(libc, "sysctlbyname");
            if (sysctlbyname_sym) {
                MSHookFunction(sysctlbyname_sym, 
                                  (void *)replaced_sysctlbyname, 
                                  (void **)&orig_sysctlbyname);
                
                // if (result == 0) {
                //     PXLog(@"[WeaponX] ✅ Successfully hooked sysctlbyname");
                // } else {
                //     PXLog(@"[WeaponX] ⚠️ Failed to hook sysctlbyname: %d", result);
                // }
            } else {
                PXLog(@"[WeaponX] ⚠️ Could not find sysctlbyname symbol");
            }
            
            dlclose(libc);
        } else {
            PXLog(@"[WeaponX] ⚠️ Failed to open libSystem.B.dylib");
        }
        
        // Hook CFUUIDCreate
        void *coreFoundation = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
        if (coreFoundation) {
            void *cfuuidcreate_sym = dlsym(coreFoundation, "CFUUIDCreate");
            if (cfuuidcreate_sym) {
                MSHookFunction(cfuuidcreate_sym, 
                                  (void *)replaced_CFUUIDCreate, 
                                  (void **)&orig_CFUUIDCreate);
                
            } else {
                PXLog(@"[WeaponX] ⚠️ Could not find CFUUIDCreate symbol");
            }
            
            dlclose(coreFoundation);
        } else {
            PXLog(@"[WeaponX] ⚠️ Failed to open CoreFoundation framework");
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ❌ Exception in setupAdditionalSystemUUIDHooks: %@", exception);
    }
}

// Update constructor to initialize the additional hooks
%ctor {
    @autoreleasepool {
        // Delay hook initialization to ensure everything is properly set up
        // This helps avoid early hooking that might cause crashes
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            // Enhanced process filtering - check if this is a process we should hook
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            NSString *executablePath = [[NSBundle mainBundle] executablePath];
            NSString *processName = [executablePath lastPathComponent];
            
            if(!IsScope())return;
            // Perform a more thorough check for iPad-specific processes that might be causing issues
            UIDevice *device = [UIDevice currentDevice];
            BOOL isIPad = [device userInterfaceIdiom] == UIUserInterfaceIdiomPad;
            
            if (isIPad) {
                // Additional processes to skip on iPad to prevent crashes
                if ([processName isEqualToString:@"sharingd"] ||
                    [processName isEqualToString:@"mediaserverd"] ||
                    [processName isEqualToString:@"searchd"] ||
                    [processName isEqualToString:@"identityservicesd"] ||
                    [processName isEqualToString:@"coreduetd"] ||
                    [processName isEqualToString:@"mobiletimerd"] ||
                    [processName containsString:@"app"] ||
                    [processName containsString:@"ctid"] ||
                    [processName containsString:@"trust"] ||
                    [processName containsString:@"xctest"]) {
                    PXLog(@"[WeaponX] 🚫 Skipping UUID hooks for iPad-specific process: %@", processName);
                    return;
                }
            }
            
            
            // If we get here, the app is configured for spoofing, so we can initialize the hooks
            
            // Check iOS version to apply different handling for iOS 18+
            NSOperatingSystemVersion ios18 = {18, 0, 0};
            BOOL isIOS18OrNewer = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios18];
            
            if (isIOS18OrNewer) {
                // Adjust cache validity duration for better performance on newer iOS
                kCacheValidityDuration = 300.0; // 5 minutes for iOS 18+
                PXLog(@"[WeaponX] ⚙️ Using adjusted cache settings for iOS 18+");
            }
            
            // Initialize cache queue with better naming for debugging
            cacheQueue = dispatch_queue_create("com.hydra.projectx.uuidcache", DISPATCH_QUEUE_SERIAL);
            
            // Initialize cache dictionary
            cachedBundleDecisions = [NSMutableDictionary dictionary];
            
            PXLog(@"[WeaponX] 🚀 Initializing UUID hooks for app: %@ (%@)", bundleID, processName);
            
            // Create a separate try-catch block for each hook to prevent one failure from affecting others
            @try {
                // Set up hook for _dyld_get_shared_cache_uuid
                void *handle = dlopen(NULL, RTLD_GLOBAL);
                if (handle) {
                    // Wrap each hook installation in its own try-catch for isolation
                    @try {
                        orig_dyld_get_shared_cache_uuid = dlsym(handle, "_dyld_get_shared_cache_uuid");
                        
                        if (orig_dyld_get_shared_cache_uuid) {
                            MSHookFunction(orig_dyld_get_shared_cache_uuid, 
                                        (void *)replaced_dyld_get_shared_cache_uuid, 
                                        (void **)&orig_dyld_get_shared_cache_uuid);      
                        } else {
                            PXLog(@"[WeaponX] ⚠️ Could not find _dyld_get_shared_cache_uuid symbol");
                        }
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] ❌ Exception when hooking _dyld_get_shared_cache_uuid: %@", exception);
                    }
                    
                    // Separate try-catch for the second hook
                    @try {
                        // Set up hook for dyld_get_all_image_infos
                        orig_dyld_get_all_image_infos = dlsym(handle, "_dyld_get_all_image_infos");
                        
                        if (orig_dyld_get_all_image_infos) {
                                MSHookFunction(orig_dyld_get_all_image_infos, 
                                            (void *)replaced_dyld_get_all_image_infos, 
                                            (void **)&orig_dyld_get_all_image_infos);
                            
                        } else {
                            PXLog(@"[WeaponX] ⚠️ Could not find _dyld_get_all_image_infos symbol");
                        }
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] ❌ Exception when hooking _dyld_get_all_image_infos: %@", exception);
                    }
                    
                    dlclose(handle);
                } else {
                    PXLog(@"[WeaponX] ⚠️ Failed to open dynamic linker handle");
                }
            } @catch (NSException *exception) {
                PXLog(@"[WeaponX] ❌ Exception in UUID hooks setup: %@", exception);
            }
            
            PXLog(@"[WeaponX] ✅ UUID hooks initialization complete for %@", bundleID);
            %init;
            setupAdditionalSystemUUIDHooks();
        });
    }
} 