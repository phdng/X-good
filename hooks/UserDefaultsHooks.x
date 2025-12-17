#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProjectXLogging.h"
#import "UserDefaultsUUIDManager.h"
#import "ProfileManager.h"

// Function declarations
static NSString *getSpoofedUserDefaultsUUID();
static BOOL isUUIDKey(NSString *key);
static id processDictionaryValues(id object);


// Add function to get spoofed UserDefaults UUID from manager
static NSString *getSpoofedUserDefaultsUUID() {
    // Use the UserDefaultsUUIDManager for consistent values across the app and hooks
    UserDefaultsUUIDManager *manager = [UserDefaultsUUIDManager sharedManager];
    NSString *uuid = [manager currentUserDefaultsUUID];
    
    if (uuid && uuid.length > 0) {
        return uuid;
    }
    

    // Build path to the profile's identity directory
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    
    // Read from device_ids.plist first (combined identifiers file)
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    if (deviceIds && deviceIds[@"UserDefaultsUUID"]) {
        PXLog(@"[WeaponX] 🔍 Found UserDefaults UUID in device_ids.plist: %@", deviceIds[@"UserDefaultsUUID"]);
        return deviceIds[@"UserDefaultsUUID"];
    }
    
    // Try specific userdefaults_uuid.plist as fallback
    NSString *userDefaultsUUIDPath = [identityDir stringByAppendingPathComponent:@"userdefaults_uuid.plist"];
    NSDictionary *userDefaultsInfo = [NSDictionary dictionaryWithContentsOfFile:userDefaultsUUIDPath];
    if (userDefaultsInfo && userDefaultsInfo[@"value"]) {
        PXLog(@"[WeaponX] 🔍 Found UserDefaults UUID in userdefaults_uuid.plist: %@", userDefaultsInfo[@"value"]);
        return userDefaultsInfo[@"value"];
    }
       
    
    // If all else fails, use a persistent fallback UUID
    NSString *fallbackUUIDPath = @"/var/jb/var/mobile/Library/WeaponX/fallback_userdefaults_uuid.plist";
    NSMutableDictionary *fallbackDict = [NSMutableDictionary dictionaryWithContentsOfFile:fallbackUUIDPath];
    
    if (!fallbackDict) {
        fallbackDict = [NSMutableDictionary dictionary];
    }
    
    NSString *fallbackUUID = fallbackDict[@"UserDefaultsUUID"];
    if (!fallbackUUID) {
        // Generate new UUID only if we don't have one saved
        fallbackUUID = [[NSUUID UUID] UUIDString];
        fallbackDict[@"UserDefaultsUUID"] = fallbackUUID;
        [fallbackDict writeToFile:fallbackUUIDPath atomically:YES];
        PXLog(@"[WeaponX] 🔍 Generated and saved persistent fallback UUID: %@", fallbackUUID);
    } else {
        PXLog(@"[WeaponX] 🔍 Using existing fallback UUID: %@", fallbackUUID);
    }
    
    return fallbackUUID;
}

// Function to recursively process dictionary values and replace UUIDs
static id processDictionaryValues(id object) {
    // Base case: not a dictionary or array
    if (!object || (![object isKindOfClass:[NSDictionary class]] && ![object isKindOfClass:[NSArray class]])) {
        return object;
    }
    
    // For dictionaries, check each key and recursively process values
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        
        NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
        
        for (id key in dict) {
            // Check if this key is UUID-related
            if ([key isKindOfClass:[NSString class]] && isUUIDKey(key)) {
                id value = dict[key];
                // If value is a string and looks like a UUID, replace it
                if ([value isKindOfClass:[NSString class]]) {
                    NSString *strValue = (NSString *)value;
                    // If the value matches a UUID pattern or is more than 8 chars and contains only hex
                    if ([strValue rangeOfString:@"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" 
                                         options:NSRegularExpressionSearch].location != NSNotFound ||
                        (strValue.length > 8 && [strValue rangeOfString:@"^[0-9a-f]+$" 
                                                               options:NSRegularExpressionSearch].location != NSNotFound)) {
                        result[key] = spoofedUUID;
                        continue;
                    }
                }
            }
            
            // Recursively process the value
            result[key] = processDictionaryValues(dict[key]);
        }
        
        return result;
    }
    
    // For arrays, recursively process each element
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)object;
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
        
        for (id item in array) {
            [result addObject:processDictionaryValues(item)];
        }
        
        return result;
    }
    
    // Shouldn't reach here, but just in case
    return object;
}

// Enhanced isUUIDKey to detect more UUID patterns
static BOOL isUUIDKey(NSString *key) {
    if (!key) return NO;
    
    NSString *lowercaseKey = [key lowercaseString];
    
    // Common UUID-related key patterns
    NSArray *uuidPatterns = @[
        @"uuid", @"udid", @"deviceid", @"device-id", @"device_id",
        @"uniqueid", @"unique-id", @"unique_id", @"identifier",
        @"vendorid", @"vendor-id", @"vendor_id", 
        @"idfa", @"idfv", @"adid", @"advertisingid",
        @"token", @"tracking", @"device"
    ];
    
    // Check for exact matches or suffixes
    for (NSString *pattern in uuidPatterns) {
        if ([lowercaseKey isEqualToString:pattern] || 
            [lowercaseKey hasSuffix:[@"." stringByAppendingString:pattern]] ||
            [lowercaseKey hasSuffix:[@"-" stringByAppendingString:pattern]] ||
            [lowercaseKey hasSuffix:[@"_" stringByAppendingString:pattern]]) {
            return YES;
        }
    }
    
    // Match UUID pattern (8-4-4-4-12 format)
    return [lowercaseKey rangeOfString:@"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" 
                              options:NSRegularExpressionSearch].location != NSNotFound;
}

#pragma mark - NSUserDefaults Hooks

%hook NSUserDefaults
// TODO 这里貌似会让应用闪退
// Base method for getting objects
- (id)objectForKey:(NSString *)defaultName {
    @try {        
        if (isUUIDKey(defaultName)) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            PXLog(@"[WeaponX] 🔍 Spoofing UserDefaults UUID for key '%@' with: %@", defaultName, spoofedUUID);
            return spoofedUUID;
        }
        
        // Process object and look for UUIDs inside it
        id originalValue = %orig;
        if (
            [originalValue isKindOfClass:[NSDictionary class]] || 
            [originalValue isKindOfClass:[NSArray class]]) {
            return processDictionaryValues(originalValue);
        }
    } @catch (NSException *exception) {
        // Just log and continue with original if there's an exception
        PXLog(@"[WeaponX] ⚠️ Exception in objectForKey hook: %@", exception);
    }
    
    return %orig;
}

// String-specific method
- (NSString *)stringForKey:(NSString *)defaultName {
    @try {        
        if (isUUIDKey(defaultName)) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            PXLog(@"[WeaponX] 🔍 Spoofing UserDefaults string UUID for key '%@' with: %@", defaultName, spoofedUUID);
            return spoofedUUID;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in stringForKey hook: %@", exception);
    }
    
    return %orig;
}

// Dictionary method - use our recursive processor for nested values
- (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)defaultName {
    NSDictionary *originalDict = %orig;
    
    @try {        
        // Don't modify if not spoofing or if the dictionary is empty
        if (!originalDict || originalDict.count == 0) {
            return originalDict;
        }
        
        // Use our recursive processor to handle nested dictionaries
        return processDictionaryValues(originalDict);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in dictionaryForKey hook: %@", exception);
        return originalDict;
    }
}

// Add additional accessor methods

- (NSArray *)arrayForKey:(NSString *)defaultName {
    NSArray *originalArray = %orig;
    
    @try {        
        // Don't modify if not spoofing or if the array is empty
        if (!originalArray || originalArray.count == 0) {
            return originalArray;
        }
        
        // Use our recursive processor to handle arrays containing dictionaries with UUIDs
        return processDictionaryValues(originalArray);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in arrayForKey hook: %@", exception);
        return originalArray;
    }
}

- (NSData *)dataForKey:(NSString *)defaultName {
    @try {        
        // Only handle data that might represent a UUID
        if (isUUIDKey(defaultName)) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            NSData *spoofedData = [spoofedUUID dataUsingEncoding:NSUTF8StringEncoding];
            PXLog(@"[WeaponX] 🔍 Spoofing UserDefaults data UUID for key '%@'", defaultName);
            return spoofedData;
        }
        
        NSData *originalData = %orig;
        
        // Check if the data might be a UUID (16 bytes)
        if (originalData && originalData.length == 16) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            
            // Convert UUID string to 16-byte binary format
            NSString *hexString = [[spoofedUUID stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
            NSMutableData *binaryData = [NSMutableData dataWithCapacity:16];
            
            for (NSInteger i = 0; i < hexString.length; i += 2) {
                NSString *hexByte = [hexString substringWithRange:NSMakeRange(i, 2)];
                NSScanner *scanner = [NSScanner scannerWithString:hexByte];
                unsigned int value;
                [scanner scanHexInt:&value];
                uint8_t byte = value;
                [binaryData appendBytes:&byte length:1];
            }
            
            PXLog(@"[WeaponX] 🔍 Spoofing potential binary UUID data for key '%@'", defaultName);
            return binaryData;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in dataForKey hook: %@", exception);
    }
    
    return %orig;
}

- (NSURL *)URLForKey:(NSString *)defaultName {
    // URL values are rarely UUIDs, so use original
    return %orig;
}

// KVC accessor - important for accessing dictionaries
- (id)valueForKey:(NSString *)key {
    @try {
        // Only override for specific UUID keys to avoid breaking KVC for other properties
        if (isUUIDKey(key)) {
            id result = [self objectForKey:key];
            if (result) {
                return result;
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in valueForKey hook: %@", exception);
    }
    
    return %orig;
}

// Subscript accessor - important for dictionary-style access
- (id)objectForKeyedSubscript:(NSString *)key {
    @try {
        // This is used when accessing NSUserDefaults with subscript notation: userDefaults[key]
        if (isUUIDKey(key)) {
            return [self objectForKey:key];
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in objectForKeyedSubscript hook: %@", exception);
    }
    
    return %orig;
}

// SETTER METHODS

// Base setter method
- (void)setObject:(id)value forKey:(NSString *)defaultName {
    @try {        
        // If setting a UUID value, replace with our spoofed UUID
        if (isUUIDKey(defaultName) && [value isKindOfClass:[NSString class]]) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            PXLog(@"[WeaponX] 🔍 Intercepting and spoofing UUID being saved to UserDefaults for key '%@'", defaultName);
            return %orig(spoofedUUID, defaultName);
        }
        
        // If setting a dictionary or array, process it to replace UUIDs
        if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
            id processedValue = processDictionaryValues(value);
            return %orig(processedValue, defaultName);
        }
    
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setObject:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// String-specific setter
- (void)setString:(NSString *)value forKey:(NSString *)defaultName {
    @try {        
        if (isUUIDKey(defaultName)) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            PXLog(@"[WeaponX] 🔍 Intercepting and spoofing UUID string being saved to UserDefaults for key '%@'", defaultName);
            return %orig(spoofedUUID, defaultName);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setString:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// Dictionary-specific setter
- (void)setDictionary:(NSDictionary<NSString *,id> *)value forKey:(NSString *)defaultName {
    @try {        
        if (value) {
            // Process the dictionary to replace any UUIDs
            NSDictionary *processedDict = processDictionaryValues(value);
            return %orig(processedDict, defaultName);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setDictionary:forKey: hook: %@", exception);
    }
    
    return %orig;
}

// Data-specific setter
- (void)setData:(NSData *)value forKey:(NSString *)defaultName {
    @try {
        
        if (isUUIDKey(defaultName) && value) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            NSData *spoofedData = [spoofedUUID dataUsingEncoding:NSUTF8StringEncoding];
            PXLog(@"[WeaponX] 🔍 Intercepting and spoofing data UUID being saved to UserDefaults for key '%@'", defaultName);
            return %orig(spoofedData, defaultName);
        }
        
        // If the data looks like a UUID (16 bytes), replace it
        if (value && value.length == 16) {
            NSString *spoofedUUID = getSpoofedUserDefaultsUUID();
            
            // Convert UUID string to 16-byte binary format
            NSString *hexString = [[spoofedUUID stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
            NSMutableData *binaryData = [NSMutableData dataWithCapacity:16];
            
            for (NSInteger i = 0; i < hexString.length; i += 2) {
                NSString *hexByte = [hexString substringWithRange:NSMakeRange(i, 2)];
                NSScanner *scanner = [NSScanner scannerWithString:hexByte];
                unsigned int value;
                [scanner scanHexInt:&value];
                uint8_t byte = value;
                [binaryData appendBytes:&byte length:1];
            }
            
            PXLog(@"[WeaponX] 🔍 Spoofing potential binary UUID data being saved for key '%@'", defaultName);
            return %orig(binaryData, defaultName);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setData:forKey: hook: %@", exception);
    }
    
    return %orig;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        // Skip for system processes
        PXLog(@"[WeaponX] 🔍 UserDefaults hooks initialized");
        %init;
    }
} 