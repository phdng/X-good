#import "IdentifierManager.h"
#import "DeviceModelManager.h"
#import "IDFAManager.h"
#import "IDFVManager.h"
#import "DeviceNameManager.h"
#import "SerialNumberManager.h"
#import "IOSVersionInfo.h"
#import "ProjectXLogging.h"
#import "WiFiManager.h"
#import "StorageManager.h"
#import "BatteryManager.h"
#import "SystemUUIDManager.h"
#import "DyldCacheUUIDManager.h"
#import "PasteboardUUIDManager.h"
#import "KeychainUUIDManager.h"
#import "UserDefaultsUUIDManager.h"
#import "AppGroupUUIDManager.h"
#import "UptimeManager.h"
#import "CoreDataUUIDManager.h"
#import "AppInstallUUIDManager.h"
#import "AppContainerUUIDManager.h"
#import <Security/Security.h>
#import "ProfileManager.h"

@interface LSApplicationWorkspace
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

@interface LSApplicationProxy
+ (id)applicationProxyForIdentifier:(id)identifier;
@property(readonly) NSString *applicationIdentifier;
@property(readonly) NSString *localizedName;
@property(readonly) NSString *shortVersionString;
@property(readonly) NSString *bundleVersion;
@end

@interface IdentifierManager ()
@property (nonatomic, strong) NSMutableDictionary *settings;
@property (nonatomic, strong) NSMutableDictionary *scopedApps;
@property (nonatomic, strong) NSError *error;
@end

@implementation IdentifierManager{
    NSMutableDictionary *_deviceData;
}

#pragma mark - Device Model

- (NSString *)generateDeviceModel {
    NSString *deviceModel = [[DeviceModelManager sharedManager] generateDeviceModel];
    if (!deviceModel) {
        self.error = [[DeviceModelManager sharedManager] lastError];
        return nil;
    }
    
    // Get all device specifications from DeviceModelManager
    DeviceModelManager *deviceManager = [DeviceModelManager sharedManager];
    NSString *deviceModelName = [deviceManager deviceModelNameForString:deviceModel];
    NSString *screenResolution = [deviceManager screenResolutionForModel:deviceModel];
    NSString *viewportResolution = [deviceManager viewportResolutionForModel:deviceModel];
    CGFloat devicePixelRatio = [deviceManager devicePixelRatioForModel:deviceModel];
    NSInteger screenDensity = [deviceManager screenDensityForModel:deviceModel];
    NSString *cpuArchitecture = [deviceManager cpuArchitectureForModel:deviceModel];
    
    // New device specifications
    NSInteger deviceMemory = [deviceManager deviceMemoryForModel:deviceModel];
    NSString *gpuFamily = [deviceManager gpuFamilyForModel:deviceModel];
    NSDictionary *webGLInfo = [deviceManager webGLInfoForModel:deviceModel];
    NSInteger cpuCoreCount = [deviceManager cpuCoreCountForModel:deviceModel];
    NSString *metalFeatureSet = [deviceManager metalFeatureSetForModel:deviceModel];
    
    // Get Board ID and hw.model
    NSString *boardID = [deviceManager boardIDForModel:deviceModel];
    NSString *hwModel = [deviceManager hwModelForModel:deviceModel];
    
    // Save to profile-specific path
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    if (identityDir) {
        // Create a full dictionary with all device specs
        NSDictionary *modelDict = @{
            @"value": deviceModel ?: @"",
            @"name": deviceModelName ?: @"",
            @"screenResolution": screenResolution ?: @"",
            @"viewportResolution": viewportResolution ?: @"",
            @"devicePixelRatio": @(devicePixelRatio),
            @"screenDensity": @(screenDensity),
            @"cpuArchitecture": cpuArchitecture ?: @"",
            @"deviceMemory": @(deviceMemory),
            @"gpuFamily": gpuFamily ?: @"",
            @"cpuCoreCount": @(cpuCoreCount),
            @"metalFeatureSet": metalFeatureSet ?: @"Unknown",
            @"webGLInfo": webGLInfo ?: @{},
            @"boardID": boardID ?: @"Unknown",
            @"hwModel": hwModel ?: @"Unknown",
            @"lastUpdated": [NSDate date]
        };
        

        // Also update the combined device_ids.plist
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
        
        // Add all device specs to the device_ids.plist file
        deviceIds[@"DeviceModel"] = deviceModel ?: @"";
        deviceIds[@"DeviceModelName"] = deviceModelName ?: @"";
        deviceIds[@"ScreenResolution"] = screenResolution ?: @"";
        deviceIds[@"ViewportResolution"] = viewportResolution ?: @"";
        deviceIds[@"DevicePixelRatio"] = @(devicePixelRatio);
        deviceIds[@"ScreenDensityPPI"] = @(screenDensity);
        deviceIds[@"CPUArchitecture"] = cpuArchitecture ?: @"";
        deviceIds[@"DeviceMemory"] = @(deviceMemory);
        deviceIds[@"CPUCoreCount"] = @(cpuCoreCount);
        deviceIds[@"MetalFeatureSet"] = metalFeatureSet ?: @"Unknown";
        deviceIds[@"GPUFamily"] = gpuFamily ?: @"";
        // Simplified WebGL info for combined file
        deviceIds[@"WebGLVendor"] = webGLInfo[@"webglVendor"] ?: @"Apple";
        deviceIds[@"WebGLRenderer"] = webGLInfo[@"webglRenderer"] ?: @"Apple GPU";
        deviceIds[@"BoardID"] = boardID ?: @"Unknown";
        deviceIds[@"HwModel"] = hwModel ?: @"Unknown";
        
        [deviceIds writeToFile:deviceIdsPath atomically:YES];
    }
    return deviceModel;
}

- (BOOL)setCustomDeviceModel:(NSString *)value {
    if (![[DeviceModelManager sharedManager] isValidDeviceModel:value]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" code:2003 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Device Model"}];
        return NO;
    }
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    BOOL success = NO;
    
    // Get all device specifications
    DeviceModelManager *deviceManager = [DeviceModelManager sharedManager];
    NSString *deviceModelName = [deviceManager deviceModelNameForString:value];
    NSString *screenResolution = [deviceManager screenResolutionForModel:value];
    NSString *viewportResolution = [deviceManager viewportResolutionForModel:value];
    CGFloat devicePixelRatio = [deviceManager devicePixelRatioForModel:value];
    NSInteger screenDensity = [deviceManager screenDensityForModel:value];
    NSString *cpuArchitecture = [deviceManager cpuArchitectureForModel:value];
    
    // New device specifications
    NSInteger deviceMemory = [deviceManager deviceMemoryForModel:value];
    NSString *gpuFamily = [deviceManager gpuFamilyForModel:value];
    NSDictionary *webGLInfo = [deviceManager webGLInfoForModel:value];
    NSInteger cpuCoreCount = [deviceManager cpuCoreCountForModel:value];
    NSString *metalFeatureSet = [deviceManager metalFeatureSetForModel:value];
    
    // Get Board ID and hw.model
    NSString *boardID = [deviceManager boardIDForModel:value];
    NSString *hwModel = [deviceManager hwModelForModel:value];
    
    if (identityDir) {
        // Create a comprehensive dictionary with all device specifications
        NSDictionary *modelDict = @{
            @"value": value ?: @"",
            @"name": deviceModelName ?: @"",
            @"screenResolution": screenResolution ?: @"",
            @"viewportResolution": viewportResolution ?: @"",
            @"devicePixelRatio": @(devicePixelRatio),
            @"screenDensity": @(screenDensity),
            @"cpuArchitecture": cpuArchitecture ?: @"",
            @"deviceMemory": @(deviceMemory),
            @"gpuFamily": gpuFamily ?: @"",
            @"cpuCoreCount": @(cpuCoreCount),
            @"metalFeatureSet": metalFeatureSet ?: @"Unknown",
            @"webGLInfo": webGLInfo ?: @{},
            @"boardID": boardID ?: @"Unknown",
            @"hwModel": hwModel ?: @"Unknown",
            @"lastUpdated": [NSDate date]
        };
        

        // Also update the combined device_ids.plist
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
        
        // Add all device specifications to the device_ids.plist
        deviceIds[@"DeviceModel"] = value ?: @"";
        deviceIds[@"DeviceModelName"] = deviceModelName ?: @"";
        deviceIds[@"ScreenResolution"] = screenResolution ?: @"";
        deviceIds[@"ViewportResolution"] = viewportResolution ?: @"";
        deviceIds[@"DevicePixelRatio"] = @(devicePixelRatio);
        deviceIds[@"ScreenDensityPPI"] = @(screenDensity);
        deviceIds[@"CPUArchitecture"] = cpuArchitecture ?: @"";
        deviceIds[@"DeviceMemory"] = @(deviceMemory);
        deviceIds[@"CPUCoreCount"] = @(cpuCoreCount);
        deviceIds[@"MetalFeatureSet"] = metalFeatureSet ?: @"Unknown";
        deviceIds[@"GPUFamily"] = gpuFamily ?: @"";
        // Simplified WebGL info for combined file
        deviceIds[@"WebGLVendor"] = webGLInfo[@"webglVendor"] ?: @"Apple";
        deviceIds[@"WebGLRenderer"] = webGLInfo[@"webglRenderer"] ?: @"Apple GPU";
        deviceIds[@"BoardID"] = boardID ?: @"Unknown";
        deviceIds[@"HwModel"] = hwModel ?: @"Unknown";
        
        success = [deviceIds writeToFile:deviceIdsPath atomically:YES];
    }
    if (success) {
        [[DeviceModelManager sharedManager] setCurrentDeviceModel:value];
    }
    return success;
}


+ (instancetype)sharedManager {
    static IdentifierManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
        [sharedManager loadSettings];
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        _settings = [NSMutableDictionary dictionary];
        _scopedApps = [NSMutableDictionary dictionary];
    }
    // [self loadScopedApps];
    // 读取配置文件
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] ❌ Failed to get profile identity path");
        return NO;
    }
    
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    _deviceData = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: 
                                        [NSMutableDictionary dictionary];
    return self;
}
- (NSString *)getValueForType:(NSString *)type{
    return _deviceData[type];
}
- (BOOL)setValueForType: (NSString *) value forType:(NSString *)type{
    _deviceData[type] = value;
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] ❌ Failed to get profile identity path");
        return NO;
    }
    // 写入文件
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: 
                                        [NSMutableDictionary dictionary];
    deviceIds[type] = value;
    BOOL success = [deviceIds writeToFile:deviceIdsPath atomically:YES];
    return success;
}
#pragma mark - Profile Integration


#pragma mark - Identifier Management

- (NSString *)generateIDFA {
    NSString *idfa = [[IDFAManager sharedManager] generateIDFA];
    if (!idfa) {
        self.error = [[IDFAManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:idfa forType:@"IDFA"];    
    return idfa;
}

- (NSString *)generateIDFV {
    NSString *idfv = [[IDFVManager sharedManager] generateIDFV];
    if (!idfv) {
        self.error = [[IDFVManager sharedManager] lastError];
        return nil;
    }
    
    [self setValueForType:idfv forType:@"IDFV"];    

    return idfv;
}

- (NSString *)generateDeviceName {
    NSString *deviceName = [[DeviceNameManager sharedManager] generateDeviceName];
    if (!deviceName) {
        self.error = [[DeviceNameManager sharedManager] lastError];
        return nil;
    }
    
    [self setValueForType:deviceName forType:@"DeviceName"];    
    return deviceName;
}

- (NSString *)generateSerialNumber {
    self.error = nil;
    
    NSString *serialNumber = [[SerialNumberManager sharedManager] generateSerialNumber];
    if (!serialNumber) {
        self.error = [[SerialNumberManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:serialNumber forType:@"SerialNumber"];    
    
    return serialNumber;
}

- (NSDictionary *)generateIOSVersion {
    self.error = nil;
    
    NSDictionary *versionInfo = [[IOSVersionInfo sharedManager] generateIOSVersionInfo];
    if (!versionInfo) {
        self.error = [[IOSVersionInfo sharedManager] lastError];
        return nil;
    }
    [self setValueForType: versionInfo[@"version"] forType:@"IOSVersion"];    
    [self setValueForType:versionInfo[@"build"] forType:@"IOSBuild"];    

    return versionInfo;
}


- (NSString *)generateSystemBootUUID {
    NSString *bootUUID = [[SystemUUIDManager sharedManager] generateBootUUID];
    if (!bootUUID) {
        self.error = [[SystemUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:bootUUID forType:@"SystemBootUUID"];    
    return bootUUID;
}

- (NSString *)generateDyldCacheUUID {
    NSString *dyldUUID = [[DyldCacheUUIDManager sharedManager] generateDyldCacheUUID];
    if (!dyldUUID) {
        self.error = [[DyldCacheUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:dyldUUID forType:@"DyldCacheUUID"];        
    return dyldUUID;
}

- (NSString *)generatePasteboardUUID {
    NSString *pasteboardUUID = [[PasteboardUUIDManager sharedManager] generatePasteboardUUID];
    if (!pasteboardUUID) {
        self.error = [[PasteboardUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:pasteboardUUID forType:@"PasteboardUUID"];        

    return pasteboardUUID;
}

- (NSString *)generateKeychainUUID {
    NSString *keychainUUID = [[KeychainUUIDManager sharedManager] generateKeychainUUID];
    if (!keychainUUID) {
        self.error = [[KeychainUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:keychainUUID forType:@"KeychainUUID"];        

    return keychainUUID;
}

- (NSString *)generateUserDefaultsUUID {
    NSString *userDefaultsUUID = [[UserDefaultsUUIDManager sharedManager] generateUserDefaultsUUID];
    if (!userDefaultsUUID) {
        self.error = [[UserDefaultsUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:userDefaultsUUID forType:@"UserDefaultsUUID"];        

    return userDefaultsUUID;
}

- (NSString *)generateAppGroupUUID {
    NSString *appGroupUUID = [[AppGroupUUIDManager sharedManager] generateAppGroupUUID];
    if (!appGroupUUID) {
        self.error = [[AppGroupUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:appGroupUUID forType:@"AppGroupUUID"];        
    return appGroupUUID;
}

- (NSString *)generateCoreDataUUID {
    NSString *coreDataUUID = [[CoreDataUUIDManager sharedManager] generateCoreDataUUID];
    if (!coreDataUUID) {
        self.error = [[CoreDataUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:coreDataUUID forType:@"CoreDataUUID"];           
    return coreDataUUID;
}

- (NSString *)generateSystemUptime {
    NSTimeInterval uptime = [[UptimeManager sharedManager] generateUptime];
    if (uptime <= 0) {
        self.error = [[UptimeManager sharedManager] lastError];
        return nil;
    }
    NSString *uptimeString = [NSString stringWithFormat:@"%.0f", uptime];
    [self setValueForType:uptimeString forType:@"SystemUptime"];           

    // Return formatted uptime string (in hours for display)
    return [NSString stringWithFormat:@"%.2f hours", uptime / 3600.0];
}

- (NSString *)generateBootTime {
    NSDate *bootTime = [[UptimeManager sharedManager] generateBootTime];
    if (!bootTime) {
        self.error = [[UptimeManager sharedManager] lastError];
        return nil;
    }
    NSString *bootTimeString = [NSString stringWithFormat:@"%.0f", [bootTime timeIntervalSince1970]];
    [self setValueForType:bootTimeString forType:@"BootTime"];           

    // Return formatted date for display
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:bootTime];
}

- (NSString *)generateAppInstallUUID {
    NSString *appInstallUUID = [[AppInstallUUIDManager sharedManager] generateAppInstallUUID];
    if (!appInstallUUID) {
        self.error = [[AppInstallUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:appInstallUUID forType:@"AppInstallUUID"];
    return appInstallUUID;
}

- (NSString *)generateAppContainerUUID {
    NSString *appContainerUUID = [[AppContainerUUIDManager sharedManager] generateAppContainerUUID];
    if (!appContainerUUID) {
        self.error = [[AppContainerUUIDManager sharedManager] lastError];
        return nil;
    }
    [self setValueForType:appContainerUUID forType:@"AppContainerUUID"];
    return appContainerUUID;
}

- (void)regenerateAllEnabledIdentifiers {
        // For WiFi info: Use the WiFiManager to generate
    Class wifiManagerClass = NSClassFromString(@"WiFiManager");
    if (wifiManagerClass && [wifiManagerClass respondsToSelector:@selector(sharedManager)]) {
        id wifiManager = [wifiManagerClass sharedManager];
        if (wifiManager && [wifiManager respondsToSelector:@selector(generateWiFiInfo)]) {
            // Generate WiFi info
            [wifiManager generateWiFiInfo];
            PXLog(@"[WeaponX] 📶 Generated WiFi information for current profile");
        }
    }
    
    // Continue with other identifiers
    if ([self isIdentifierEnabled:@"IDFA"]) {
        [self generateIDFA];
    }
    if ([self isIdentifierEnabled:@"IDFV"]) {
        [self generateIDFV];
    }
    if ([self isIdentifierEnabled:@"DeviceName"]) {
        [self generateDeviceName];
    }
    if ([self isIdentifierEnabled:@"SerialNumber"]) {
        [self generateSerialNumber];
    }
    if ([self isIdentifierEnabled:@"IMEI"]) {
        NSString *imei = [self generateIMEI];
        if (imei) [self setCustomIMEI:imei];
    }
    if ([self isIdentifierEnabled:@"MEID"]) {
        NSString *meid = [self generateMEID];
        if (meid) [self setCustomMEID:meid];
    }
    
    // Always generate device model regardless of whether it exists or not
    NSString *deviceModel = [self generateDeviceModel];
    if (deviceModel) [self setCustomDeviceModel:deviceModel];
    
    // Always generate device theme if it doesn't exist
    if (![self getValueForType:@"DeviceTheme"]) {
        NSString *deviceTheme = [self generateDeviceTheme];
        if (deviceTheme) {
            [self setCustomDeviceTheme:deviceTheme];
            PXLog(@"[WeaponX] 🎨 Generated device theme: %@", deviceTheme);
        }
    }
    
    if ([self isIdentifierEnabled:@"IOSVersion"]) {
        [self generateIOSVersion];
    }
    if ([self isIdentifierEnabled:@"SystemBootUUID"]) {
        [self generateSystemBootUUID];
    }
    if ([self isIdentifierEnabled:@"DyldCacheUUID"]) {
        [self generateDyldCacheUUID];
    }
    if ([self isIdentifierEnabled:@"PasteboardUUID"]) {
        [self generatePasteboardUUID];
    }

    if ([self isIdentifierEnabled:@"KeychainUUID"]) {
        [self generateKeychainUUID];
    }
    if ([self isIdentifierEnabled:@"UserDefaultsUUID"]) {
        [self generateUserDefaultsUUID];
    }
    if ([self isIdentifierEnabled:@"AppGroupUUID"]) {
        [self generateAppGroupUUID];
    }
    if ([self isIdentifierEnabled:@"CoreDataUUID"]) {
        [self generateCoreDataUUID];
    }
    if ([self isIdentifierEnabled:@"SystemUptime"]) {
        [self generateSystemUptime];
    }
    if ([self isIdentifierEnabled:@"BootTime"]) {
        [self generateBootTime];
    }
    // Even though we already generated WiFi info above, check if it's specifically enabled
    if ([self isIdentifierEnabled:@"WiFi"]) {
        // Use WiFiManager to generate new WiFi info
        id wifiManager = NSClassFromString(@"WiFiManager");
        if (wifiManager && [wifiManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [wifiManager sharedManager];
            if (sharedManager && [sharedManager respondsToSelector:@selector(generateWiFiInfo)]) {
                [sharedManager generateWiFiInfo];
                PXLog(@"Generated new WiFi information");
            }
        }
    }
    if ([self isIdentifierEnabled:@"StorageSystem"]) {
        // Use StorageManager to generate new storage info
        id storageManager = NSClassFromString(@"StorageManager");
        if (storageManager && [storageManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [storageManager sharedManager];
            if (sharedManager && [sharedManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                // Randomly choose between 64GB and 128GB
                NSString *capacity = [sharedManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                       [sharedManager randomizeStorageCapacity] : @"64";
                
                NSDictionary *storageInfo = [sharedManager generateStorageForCapacity:capacity];
                if (storageInfo) {
                    [sharedManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                    [sharedManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                    [sharedManager setFilesystemType:storageInfo[@"FilesystemType"]];
                    PXLog(@"[WeaponX] 💾 Generated new storage information: %@ GB", storageInfo[@"TotalStorage"]);
                }
            }
        }
    }
    if ([self isIdentifierEnabled:@"Battery"]) {
        // Use BatteryManager to generate new battery info
        id batteryManager = NSClassFromString(@"BatteryManager");
        if (batteryManager && [batteryManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [batteryManager sharedManager];
            if (sharedManager && [sharedManager respondsToSelector:@selector(generateBatteryInfo)]) {
                NSDictionary *batteryInfo = [sharedManager generateBatteryInfo];
                if (batteryInfo) {
                    PXLog(@"[WeaponX] 🔋 Generated new battery information: %@%%", 
                         @([batteryInfo[@"BatteryLevel"] floatValue] * 100));
                }
            }
        }
    }
    // Add AppInstallUUID
    if ([self isIdentifierEnabled:@"AppInstallUUID"]) {
        [self generateAppInstallUUID];
    }
    // Add AppContainerUUID
    if ([self isIdentifierEnabled:@"AppContainerUUID"]) {
        [self generateAppContainerUUID];
    }
    // Add DeviceTheme
    if ([self isIdentifierEnabled:@"DeviceTheme"]) {
        [self generateDeviceTheme];
    }
    [self saveSettings];
}

#pragma mark - Settings Management

// Helper methods for file checks
- (BOOL)fileExistsAtPath:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSDictionary *)dictionaryAtPath:(NSString *)path {
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (void)setIdentifierEnabled:(BOOL)enabled forType:(NSString *)type {
    // Set the enabled state in settings
    self.settings[type] = @(enabled);
    
    // If enabling an identifier, check if we need to generate a value
    if (enabled) {
        // Check if a value exists
        NSString *currentValue = [self currentValueForIdentifier:type];
        if (!currentValue) {
            PXLog(@"No value exists for %@ - generating new value...", type);
            
            // Generate a value based on the identifier type
            if ([type isEqualToString:@"IDFA"]) {
                [self generateIDFA];
            } 
            else if ([type isEqualToString:@"IDFV"]) {
                [self generateIDFV];
            }
            else if ([type isEqualToString:@"DeviceName"]) {
                [self generateDeviceName];
            }
            else if ([type isEqualToString:@"SerialNumber"]) {
                [self generateSerialNumber];
            }
            else if ([type isEqualToString:@"IMEI"]) {
                NSString *imei = [self generateIMEI];
                if (imei) [self setCustomIMEI:imei];
            }
            else if ([type isEqualToString:@"MEID"]) {
                NSString *meid = [self generateMEID];
                if (meid) [self setCustomMEID:meid];
            }
            else if ([type isEqualToString:@"IOSVersion"]) {
                [self generateIOSVersion];
            }
            else if ([type isEqualToString:@"SystemBootUUID"]) {
                [self generateSystemBootUUID];
            }
            else if ([type isEqualToString:@"DyldCacheUUID"]) {
                [self generateDyldCacheUUID];
            }
            else if ([type isEqualToString:@"PasteboardUUID"]) {
                [self generatePasteboardUUID];
            }
            else if ([type isEqualToString:@"KeychainUUID"]) {
                [self generateKeychainUUID];
            }
            else if ([type isEqualToString:@"UserDefaultsUUID"]) {
                [self generateUserDefaultsUUID];
            }
            else if ([type isEqualToString:@"AppGroupUUID"]) {
                [self generateAppGroupUUID];
            }
            else if ([type isEqualToString:@"CoreDataUUID"]) {
                [self generateCoreDataUUID];
            }
            else if ([type isEqualToString:@"SystemUptime"]) {
                [self generateSystemUptime];
            }
            else if ([type isEqualToString:@"BootTime"]) {
                [self generateBootTime];
            }
            else if ([type isEqualToString:@"WiFi"]) {
                // Use WiFiManager to generate new WiFi info
                id wifiManager = NSClassFromString(@"WiFiManager");
                if (wifiManager && [wifiManager respondsToSelector:@selector(sharedManager)]) {
                    id sharedManager = [wifiManager sharedManager];
                    if (sharedManager && [sharedManager respondsToSelector:@selector(generateWiFiInfo)]) {
                        [sharedManager generateWiFiInfo];
                        PXLog(@"Generated new WiFi information");
                    }
                }
            }
            else if ([type isEqualToString:@"StorageSystem"]) {
                // Use StorageManager to generate new storage info
                id storageManager = NSClassFromString(@"StorageManager");
                if (storageManager && [storageManager respondsToSelector:@selector(sharedManager)]) {
                    id sharedManager = [storageManager sharedManager];
                    if (sharedManager && [sharedManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                        // Randomly choose between 64GB and 128GB
                        NSString *capacity = [sharedManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                               [sharedManager randomizeStorageCapacity] : @"64";
                        
                        NSDictionary *storageInfo = [sharedManager generateStorageForCapacity:capacity];
                        if (storageInfo) {
                            [sharedManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                            [sharedManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                            [sharedManager setFilesystemType:storageInfo[@"FilesystemType"]];
                            PXLog(@"[WeaponX] 💾 Generated new storage information: %@ GB", storageInfo[@"TotalStorage"]);
                        }
                    }
                }
            }
            else if ([type isEqualToString:@"Battery"]) {
                // Use BatteryManager to generate new battery info
                id batteryManager = NSClassFromString(@"BatteryManager");
                if (batteryManager && [batteryManager respondsToSelector:@selector(sharedManager)]) {
                    id sharedManager = [batteryManager sharedManager];
                    if (sharedManager && [sharedManager respondsToSelector:@selector(generateBatteryInfo)]) {
                        NSDictionary *batteryInfo = [sharedManager generateBatteryInfo];
                        if (batteryInfo) {
                            PXLog(@"[WeaponX] 🔋 Generated new battery information: %@%%", 
                                 @([batteryInfo[@"BatteryLevel"] floatValue] * 100));
                        }
                    }
                }
            }
            else if ([type isEqualToString:@"AppInstallUUID"]) {
                [self generateAppInstallUUID];
            }
            else if ([type isEqualToString:@"AppContainerUUID"]) {
                [self generateAppContainerUUID];
            }
            else if ([type isEqualToString:@"DeviceTheme"]) {
                NSString *theme = [self generateDeviceTheme];
                if (theme) {
                    PXLog(@"[WeaponX] 🎨 Generated device theme: %@", theme);
                }
            }
        }
    }
    
    // Always ensure device model exists
    if (![self getValueForType:@"DeviceModel"]) {
        NSString *deviceModel = [self generateDeviceModel];
        if (deviceModel) [self setCustomDeviceModel:deviceModel];
    }
    
    // For WiFi specifically, also update the SystemConfiguration plist
    if ([type isEqualToString:@"WiFi"]) {
        NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
        NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
        settingsDict[@"wifiSpoofEnabled"] = @(enabled);
        [settingsDict writeToFile:securitySettingsPath atomically:YES];
        
        // Also update in UserDefaults for compatibility
        NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        [settings setBool:enabled forKey:@"wifiSpoofEnabled"];
        [settings synchronize];
        
        // Post notification to inform system about WiFi spoofing change
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                           CFSTR("com.hydra.projectx.toggleWifiSpoof"),
                                           NULL, NULL, YES);
    }
    // For Battery specifically, update the SystemConfiguration plist
    else if ([type isEqualToString:@"Battery"]) {
        NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
        NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
        settingsDict[@"batterySpoofEnabled"] = @(enabled);
        [settingsDict writeToFile:securitySettingsPath atomically:YES];
        
        // Also update in UserDefaults for compatibility
        NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        [settings setBool:enabled forKey:@"batterySpoofEnabled"];
        [settings synchronize];
        
        // Post notification to inform system about Battery spoofing change
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                           CFSTR("com.hydra.projectx.toggleBatterySpoof"),
                                           NULL, NULL, YES);
    }
    // For DeviceTheme, update the SystemConfiguration plist
    else if ([type isEqualToString:@"DeviceTheme"]) {
        NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
        NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
        settingsDict[@"deviceThemeSpoofEnabled"] = @(enabled);
        [settingsDict writeToFile:securitySettingsPath atomically:YES];
        
        // Also update in UserDefaults for compatibility
        NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        [settings setBool:enabled forKey:@"deviceThemeSpoofEnabled"];
        [settings synchronize];
        
        // Post notification to inform system about DeviceTheme spoofing change
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                           CFSTR("com.hydra.projectx.toggleDeviceThemeSpoof"),
                                           NULL, NULL, YES);
    }
    
    [self saveSettings];
}

- (BOOL)isIdentifierEnabled:(NSString *)type {
    return [self.settings[type] boolValue];
}

#pragma mark - Current Values
- (NSTimeInterval) currentUptime{
    NSTimeInterval uptime = [_deviceData[@"SystemUptime"] doubleValue];
    return uptime;
}
- (NSDate *)currentBootTime {
    NSTimeInterval timestamp = [_deviceData[@"BootTime"] doubleValue];
    if (timestamp > 0) {
        return [NSDate dateWithTimeIntervalSince1970:timestamp];
    }
    return [NSDate dateWithTimeIntervalSinceNow:-(12 * 3600)]; // 12 hours ago as safe default
}
- (NSDictionary *)currentIOSVersionInfo {
    NSString *version = [[IdentifierManager sharedManager] getValueForType:@"IOSVersion"];
    NSString *build = [[IdentifierManager sharedManager] getValueForType:@"IOSBuild"];
    return @{
      @"version": version,
      @"build": build
    };
}
// 页面展示用的 里面带格式化
- (NSString *)currentValueForIdentifier:(NSString *)type {
    // Special hardcoded serial number for Filza and ADManager
    // if ([type isEqualToString:@"SerialNumber"]) {
    //     NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    //     if (bundleID) {
    //         if ([bundleID isEqualToString:@"com.tigisoftware.Filza"] || 
    //             [bundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
    //             // Return hardcoded serial number for these specific apps
    //             NSString *hardcodedSerial = @"FCCC15Q4HG04";
    //             PXLog(@"[WeaponX] 📱 Returning hardcoded serial number for %@: %@", bundleID, hardcodedSerial);
    //             return hardcodedSerial;
    //         }
    //     }
    // }
    
    // First try to get from profile-specific storage
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    //   NSString *identityDir = [self profileIdentityPath];
//     if (identityDir) {
//         NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
//         NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
//         NSString *value = deviceIds[type];
        
//         if (value) {
//             PXLog(@"Found %@ value in device_ids.plist: %@", type, value);
//             return value;
//         }
        
//         // If not found in combined file, try type-specific files
//         else if ([type isEqualToString:@"DeviceModel"]) {
//             NSString *modelPath = [identityDir stringByAppendingPathComponent:@"device_model.plist"];
//             NSDictionary *modelDict = [NSDictionary dictionaryWithContentsOfFile:modelPath];
//             if (modelDict && modelDict[@"value"]) {
//                 PXLog(@"Found DeviceModel in device_model.plist: %@", modelDict[@"value"]);
//                 return modelDict[@"value"];
//             }
//         }
//         else if ([type isEqualToString:@"DeviceName"]) {
//             NSString *deviceNamePath = [identityDir stringByAppendingPathComponent:@"device_name.plist"];
//             NSDictionary *deviceNameDict = [NSDictionary dictionaryWithContentsOfFile:deviceNamePath];
//             if (deviceNameDict && deviceNameDict[@"value"]) {
//                 PXLog(@"Found DeviceName in device_name.plist: %@", deviceNameDict[@"value"]);
//                 return deviceNameDict[@"value"];
//             }
//         }
//         else if ([type isEqualToString:@"SerialNumber"]) {
//             NSString *serialPath = [identityDir stringByAppendingPathComponent:@"serial_number.plist"];
//             NSDictionary *serialDict = [NSDictionary dictionaryWithContentsOfFile:serialPath];
//             if (serialDict && serialDict[@"value"]) {
//                 PXLog(@"Found SerialNumber in serial_number.plist: %@", serialDict[@"value"]);
//                 return serialDict[@"value"];
//             }
//         }
//         else if ([type isEqualToString:@"WiFi"]) {
//             // Check for WiFi info in the profile
//             NSString *wifiInfoPath = [identityDir stringByAppendingPathComponent:@"wifi_info.plist"];
//             NSDictionary *wifiInfo = [NSDictionary dictionaryWithContentsOfFile:wifiInfoPath];
//             if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
//                 NSString *formattedValue = [NSString stringWithFormat:@"%@ (%@)", wifiInfo[@"ssid"], wifiInfo[@"bssid"]];
//                 PXLog(@"Found WiFi info in wifi_info.plist: %@", formattedValue);
//                 return formattedValue;
//             }
//         }
//         else if ([type isEqualToString:@"StorageSystem"]) {
//             NSString *storagePath = [identityDir stringByAppendingPathComponent:@"storage.plist"];
//             NSDictionary *storageDict = [NSDictionary dictionaryWithContentsOfFile:storagePath];
//             if (storageDict && storageDict[@"TotalStorage"] && storageDict[@"FreeStorage"]) {
//                 NSString *formattedStorage = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
//                                              storageDict[@"TotalStorage"], 
//                                              storageDict[@"FreeStorage"]];
//                 PXLog(@"Found Storage info in storage.plist: %@", formattedStorage);
//                 return formattedStorage;
//             }
//         }
//         else if ([type isEqualToString:@"BatteryLevel"] || [type isEqualToString:@"LowPowerMode"]) {
//             NSString *batteryPath = [identityDir stringByAppendingPathComponent:@"battery_info.plist"];
//             NSDictionary *batteryDict = [NSDictionary dictionaryWithContentsOfFile:batteryPath];
//             if (batteryDict && batteryDict[type]) {
//                 PXLog(@"Found %@ in battery_info.plist: %@", type, batteryDict[type]);
//                 return batteryDict[type];
//             }
//         }
//         else if ([type isEqualToString:@"SystemUptime"]) {
//             NSString *profilePath = [self profileIdentityPath];
// NSString *uptimePath = [profilePath stringByAppendingPathComponent:@"system_uptime.plist"];
// NSDictionary *uptimeDict = [NSDictionary dictionaryWithContentsOfFile:uptimePath];
// if (uptimeDict && uptimeDict[@"value"]) {
//     NSTimeInterval uptime = [uptimeDict[@"value"] doubleValue];
//     if (uptime > 0) {
//         NSString *formattedUptime = [NSString stringWithFormat:@"%.2f hours", uptime / 3600.0];
//         PXLog(@"[WeaponX] 📄 Showing SystemUptime from system_uptime.plist: %@", formattedUptime);
//         return formattedUptime;
//     }
// }
// return @"Not Set";
//         }
//         else if ([type isEqualToString:@"BootTime"]) {
//             NSString *profilePath = [self profileIdentityPath];
// NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
// NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
// if (bootTimeDict && bootTimeDict[@"value"]) {
//     NSDate *bootTime = bootTimeDict[@"value"];
//     if ([bootTime isKindOfClass:[NSDate class]]) {
//         NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
//         formatter.dateStyle = NSDateFormatterMediumStyle;
//         formatter.timeStyle = NSDateFormatterMediumStyle;
//         NSString *formattedBootTime = [formatter stringFromDate:bootTime];
//         PXLog(@"[WeaponX] 📄 Showing BootTime from boot_time.plist: %@", formattedBootTime);
//         return formattedBootTime;
//     }
// }
// return @"Not Set";
//         }
        
//         PXLog(@"No %@ value found in profile-specific files", type);
//     } else {
//         PXLog(@"Could not access identity directory for profile");
//     }
        

    if ([type isEqualToString:@"SystemUptime"]) {
        NSTimeInterval uptime = [[UptimeManager sharedManager] currentUptime];
        NSString *result = [NSString stringWithFormat:@"%.2f hours", uptime / 3600.0];
        return result;
    }
    else if ([type isEqualToString:@"BootTime"]) {
        NSDate *bootTime = [[UptimeManager sharedManager] currentBootTime];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
        NSString *result = [formatter stringFromDate:bootTime];
        return result;
    }else if([type isEqualToString:@"IOSVersion"]){
        NSDictionary *currentVersion = [self currentIOSVersionInfo];
        if (currentVersion && currentVersion[@"version"] && currentVersion[@"build"]) {
            NSString *formattedVersion = [NSString stringWithFormat:@"%@ (%@)", currentVersion[@"version"], currentVersion[@"build"]];
            return formattedVersion;
        }
    }
    
    NSString *value = _deviceData[type];

    if (value) {
        PXLog(@"Found %@ value in device_ids.plist: %@", type, value);
        return value;
    }
    


    if ([type isEqualToString:@"WiFi"]) {
        // Check for WiFi info in the profile
        NSString *wifiInfoPath = [identityDir stringByAppendingPathComponent:@"wifi_info.plist"];
        NSDictionary *wifiInfo = [NSDictionary dictionaryWithContentsOfFile:wifiInfoPath];
        if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
            NSString *formattedValue = [NSString stringWithFormat:@"%@ (%@)", wifiInfo[@"ssid"], wifiInfo[@"bssid"]];
            PXLog(@"Found WiFi info in wifi_info.plist: %@", formattedValue);
            return formattedValue;
        }
    }
    else if ([type isEqualToString:@"StorageSystem"]) {
        NSString *storagePath = [identityDir stringByAppendingPathComponent:@"storage.plist"];
        NSDictionary *storageDict = [NSDictionary dictionaryWithContentsOfFile:storagePath];
        if (storageDict && storageDict[@"TotalStorage"] && storageDict[@"FreeStorage"]) {
            NSString *formattedStorage = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                            storageDict[@"TotalStorage"], 
                                            storageDict[@"FreeStorage"]];
            PXLog(@"Found Storage info in storage.plist: %@", formattedStorage);
            return formattedStorage;
        }
    }
    else if ([type isEqualToString:@"BatteryLevel"] || [type isEqualToString:@"LowPowerMode"]) {
        NSString *batteryPath = [identityDir stringByAppendingPathComponent:@"battery_info.plist"];
        NSDictionary *batteryDict = [NSDictionary dictionaryWithContentsOfFile:batteryPath];
        if (batteryDict && batteryDict[type]) {
            PXLog(@"Found %@ in battery_info.plist: %@", type, batteryDict[type]);
            return batteryDict[type];
        }
    }

        
    PXLog(@"No %@ value found in profile-specific files", type);
    

    // Special handling for IOS Version which returns a composite string
    if ([type isEqualToString:@"IOSVersion"]) {
        // First try to get from profile-specific storage
        NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
        if (identityDir) {
            // First try to get from device_ids.plist
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            NSString *version = deviceIds[@"IOSVersion"];
            
            // If we have a pre-formatted version string, use it
            if (version && [version containsString:@"("]) {
                PXLog(@"[WeaponX] Found pre-formatted iOS version: %@", version);
                return version;
            }
            
            // If not pre-formatted, try to combine version and build
            NSString *build = deviceIds[@"IOSBuild"];
            if (version && build) {
                NSString *formattedVersion = [NSString stringWithFormat:@"%@ (%@)", version, build];
                PXLog(@"[WeaponX] Formatted iOS version from components: %@", formattedVersion);
                return formattedVersion;
            }
        }
        
        // Fall back to IOSVersionInfo if profile-specific value not found
        NSDictionary *currentVersion = [[IOSVersionInfo sharedManager] currentIOSVersionInfo];
        if (currentVersion && currentVersion[@"version"] && currentVersion[@"build"]) {
            NSString *formattedVersion = [NSString stringWithFormat:@"%@ (%@)", currentVersion[@"version"], currentVersion[@"build"]];
            PXLog(@"[WeaponX] Formatted iOS version from IOSVersionInfo: %@", formattedVersion);
            return formattedVersion;
        }
        
        PXLog(@"[WeaponX] No iOS version information found");
        return nil;
    }
    
    // Special handling for WiFi which needs the WiFiManager
    if ([type isEqualToString:@"WiFi"]) {
        // Try to get WiFi info from WiFiManager
        id wifiManager = NSClassFromString(@"WiFiManager");
        if (wifiManager && [wifiManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [wifiManager sharedManager];
            if (sharedManager) {
                // Get WiFi info based on available methods
                NSString *ssid = nil;
                NSString *bssid = nil;
                
                if ([sharedManager respondsToSelector:@selector(currentSSID)]) {
                    ssid = [sharedManager currentSSID];
                }
                
                if ([sharedManager respondsToSelector:@selector(currentBSSID)]) {
                    bssid = [sharedManager currentBSSID];
                }
                
                if (ssid && bssid) {
                    NSString *formattedValue = [NSString stringWithFormat:@"%@ (%@)", ssid, bssid];
                    PXLog(@"[WeaponX] WiFi info from WiFiManager: %@", formattedValue);
                    return formattedValue;
                } else if (ssid) {
                    PXLog(@"[WeaponX] WiFi SSID only from WiFiManager: %@", ssid);
                    return ssid;
                }
            }
        }
    }
    
    // Special handling for StorageSystem - try to get from StorageManager
    if ([type isEqualToString:@"StorageSystem"]) {
        id storageManager = NSClassFromString(@"StorageManager");
        if (storageManager && [storageManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [storageManager sharedManager];
            if (sharedManager) {
                NSString *totalStorage = nil;
                NSString *freeStorage = nil;
                
                if ([sharedManager respondsToSelector:@selector(totalStorageCapacity)]) {
                    totalStorage = [sharedManager totalStorageCapacity];
                }
                
                if ([sharedManager respondsToSelector:@selector(freeStorageSpace)]) {
                    freeStorage = [sharedManager freeStorageSpace];
                }
                
                if (totalStorage && freeStorage) {
                    NSString *formattedStorage = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                               totalStorage, freeStorage];
                    return formattedStorage;
                }
                
                // Try to generate new values if we couldn't get existing ones
                if ([sharedManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                    // Randomly choose between 64GB and 128GB
                    NSString *capacity = [sharedManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                           [sharedManager randomizeStorageCapacity] : @"64";
                    
                    NSDictionary *storageInfo = [sharedManager generateStorageForCapacity:capacity];
                    if (storageInfo) {
                        [sharedManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                        [sharedManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                        [sharedManager setFilesystemType:storageInfo[@"FilesystemType"]];
                        
                        NSString *formattedStorage = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                                  storageInfo[@"TotalStorage"], 
                                                  storageInfo[@"FreeStorage"]];
                        return formattedStorage;
                    }
                }
            }
        }
        
        // Final fallback for storage - 40% chance for 64GB, 60% chance for 128GB
        BOOL use128GB = (arc4random_uniform(100) < 60);
        NSString *storageCapacity = use128GB ? @"128" : @"64";
        NSString *freeSpaceValue = use128GB ? @"38.4" : @"19.8";
        
        // Save these values to StorageManager to ensure consistency
        if (storageManager && [storageManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [storageManager sharedManager];
            if (sharedManager) {
                [sharedManager setTotalStorageCapacity:storageCapacity];
                [sharedManager setFreeStorageSpace:freeSpaceValue];
                [sharedManager setFilesystemType:@"0x1A"];
            }
        }
        
        return [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", storageCapacity, freeSpaceValue];
    }
    
    // Special handling for Battery info - try to get from BatteryManager
    if ([type isEqualToString:@"BatteryLevel"] || [type isEqualToString:@"LowPowerMode"] || [type isEqualToString:@"Battery"]) {
        id batteryManager = NSClassFromString(@"BatteryManager");
        if (batteryManager && [batteryManager respondsToSelector:@selector(sharedManager)]) {
            id sharedManager = [batteryManager sharedManager];
            if (sharedManager) {
                // Force a reload from disk first to ensure fresh values
                if ([sharedManager respondsToSelector:@selector(loadBatteryInfoFromDisk)]) {
                    [sharedManager loadBatteryInfoFromDisk];
                }
                
                // Handle Battery identifier which includes both level and low power mode
                if ([type isEqualToString:@"Battery"]) {
                    if ([sharedManager respondsToSelector:@selector(batteryLevel)]) {
                        
                        // Use explicit cast to BatteryManager to avoid confusion with UIDevice method
                        NSString *level = [(BatteryManager *)sharedManager batteryLevel];
                        
                        if (level) {
                            float levelFloat = [level floatValue];
                            int percentage = (int)(levelFloat * 100);
                            
                            NSString *displayValue = [NSString stringWithFormat:@"%d%%", percentage];
                                 
                            PXLog(@"[WeaponX] 🔋 Battery info from BatteryManager: %@", displayValue);
                            return displayValue;
                        }
                    }
                    
                    // If we couldn't get both values, try to get a pre-formatted display value
                    if ([sharedManager respondsToSelector:@selector(generateBatteryInfo)]) {
                        NSDictionary *batteryInfo = [sharedManager generateBatteryInfo];
                        if (batteryInfo) {
                            // Check if we have a pre-formatted display value
                            if (batteryInfo[@"DisplayValue"]) {
                                return batteryInfo[@"DisplayValue"];
                            }
                            
                            // Otherwise, format it ourselves
                            NSString *level = batteryInfo[@"BatteryLevel"];
                            
                            if (level) {
                                float levelFloat = [level floatValue];
                                int percentage = (int)(levelFloat * 100);
                                
                                NSString *displayValue = [NSString stringWithFormat:@"%d%%", percentage];
                                     
                                PXLog(@"[WeaponX] 🔋 Generated battery info: %@", displayValue);
                                return displayValue;
                            }
                        }
                    }
                } 
                // Handle individual battery values
                else if ([type isEqualToString:@"BatteryLevel"] && [sharedManager respondsToSelector:@selector(batteryLevel)]) {
                    NSString *level = [(BatteryManager *)sharedManager batteryLevel];
                    if (level) {
                        PXLog(@"[WeaponX] 🔋 Battery level from BatteryManager: %@", level);
                        return level;
                    }
                }
            }
        }
    }
    
    // Special handling for SystemUptime/BootTime
    if ([type isEqualToString:@"SystemUptime"]) {
        NSTimeInterval uptime = [[UptimeManager sharedManager] currentUptime];
        NSString *result = [NSString stringWithFormat:@"%.2f hours", uptime / 3600.0];
        PXLog(@"Default SystemUptime value: %@", result);
        return result;
    }
    else if ([type isEqualToString:@"BootTime"]) {
        NSDate *bootTime = [[UptimeManager sharedManager] currentBootTime];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
        NSString *result = [formatter stringFromDate:bootTime];
        PXLog(@"Default BootTime value: %@", result);
        return result;
    }
    
    // Fallback to the original implementation if profile-specific value not found
    PXLog(@"Falling back to default implementation for %@", type);
    if ([type isEqualToString:@"IDFA"]) {
        NSString *result = [[IDFAManager sharedManager] currentIDFA];
        PXLog(@"Default IDFA value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"IDFV"]) {
        NSString *result = [[IDFVManager sharedManager] currentIDFV];
        PXLog(@"Default IDFV value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"SystemBootUUID"]) {
        NSString *result = [[SystemUUIDManager sharedManager] currentBootUUID];
        PXLog(@"Default SystemBootUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"DyldCacheUUID"]) {
        NSString *result = [[DyldCacheUUIDManager sharedManager] currentDyldCacheUUID];
        PXLog(@"Default DyldCacheUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"PasteboardUUID"]) {
        NSString *result = [[PasteboardUUIDManager sharedManager] currentPasteboardUUID];
        PXLog(@"Default PasteboardUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"KeychainUUID"]) {
        NSString *result = [[KeychainUUIDManager sharedManager] currentKeychainUUID];
        PXLog(@"Default KeychainUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"UserDefaultsUUID"]) {
        NSString *result = [[UserDefaultsUUIDManager sharedManager] currentUserDefaultsUUID];
        PXLog(@"Default UserDefaultsUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"AppGroupUUID"]) {
        NSString *result = [[AppGroupUUIDManager sharedManager] currentAppGroupUUID];
        PXLog(@"Default AppGroupUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"CoreDataUUID"]) {
        NSString *result = [[CoreDataUUIDManager sharedManager] currentCoreDataUUID];
        PXLog(@"Default CoreDataUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"AppInstallUUID"]) {
        NSString *result = [[AppInstallUUIDManager sharedManager] currentAppInstallUUID];
        PXLog(@"Default AppInstallUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"AppContainerUUID"]) {
        NSString *result = [[AppContainerUUIDManager sharedManager] currentAppContainerUUID];
        PXLog(@"Default AppContainerUUID value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"DeviceName"]) {
        NSString *result = [[DeviceNameManager sharedManager] currentDeviceName];
        PXLog(@"Default DeviceName value: %@", result ?: @"nil");
        return result;
    } else if ([type isEqualToString:@"SerialNumber"]) {
        NSString *result = [[SerialNumberManager sharedManager] currentSerialNumber];
        PXLog(@"Default SerialNumber value: %@", result ?: @"nil");
        return result;
    }
    
    PXLog(@"No value found for %@", type);
    return nil;
}

#pragma mark - App Management

- (void)refreshScopedAppsInfoIfNeeded {
    // Iterate through all scoped apps and update their version/build info
    for (NSString *bundleID in self.scopedApps) {
        LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
        if (appProxy) {
            NSString *currentVersion = appProxy.shortVersionString;
            NSString *currentBuild = appProxy.bundleVersion ?: @"";
            NSMutableDictionary *appInfo = self.scopedApps[bundleID];
            BOOL needsUpdate = ![appInfo[@"version"] isEqualToString:currentVersion] ||
                               ![appInfo[@"build"] isEqualToString:currentBuild];
            if (needsUpdate) {
                appInfo[@"version"] = currentVersion ?: @"";
                appInfo[@"build"] = currentBuild ?: @"";
            }
        }
    }
    [self saveSettings];
}

- (void)addApplicationToScope:(NSString *)bundleID {
    if (!bundleID.length) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:3001 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid bundle ID"}];
        return;
    }
    
    // Prevent the WeaponX app itself from being added to the scope list
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:3003 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Cannot add the WeaponX app itself to the scope list"}];
        PXLog(@"[WeaponX] ⚠️ Prevented attempt to add the WeaponX app to the scope list");
        return;
    }
    
    // Get app info using LSApplicationProxy
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!appProxy) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:3002 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Application not found"}];
        return;
    }
    
    NSMutableDictionary *appInfo = [NSMutableDictionary dictionary];
    appInfo[@"name"] = appProxy.localizedName ?: bundleID;
    appInfo[@"version"] = appProxy.shortVersionString ?: @"App Not Found";
    NSString *buildVersion = nil;
    id proxy = (id)appProxy;
    if ([proxy respondsToSelector:@selector(bundleVersion)]) {
        buildVersion = [proxy performSelector:@selector(bundleVersion)];
    } else if ([proxy respondsToSelector:@selector(valueForKey:)]) {
        buildVersion = [proxy valueForKey:@"bundleVersion"];
        if (!buildVersion) {
            buildVersion = [proxy valueForKey:@"CFBundleVersion"];
        }
    }
    appInfo[@"build"] = buildVersion ?: @"Unknown";  // Add build number
    appInfo[@"installed"] = @YES;
    appInfo[@"enabled"] = @YES;
    
    // Store using the original case-sensitive bundle ID
    appInfo[@"bundleID"] = bundleID;
    appInfo[@"originalBundleID"] = bundleID;  // Store original case-sensitive version
    
    // Use the original case-sensitive bundle ID as the dictionary key
    self.scopedApps[bundleID] = appInfo;
    [self saveSettings];
}

- (void)removeApplicationFromScope:(NSString *)bundleID {
    [self.scopedApps removeObjectForKey:bundleID];
    [self saveSettings];
}

- (void)setApplication:(NSString *)bundleID enabled:(BOOL)enabled {
    NSMutableDictionary *appInfo = [self.scopedApps[bundleID] mutableCopy];
    if (appInfo) {
        appInfo[@"enabled"] = @(enabled);
        self.scopedApps[bundleID] = appInfo;
        [self saveSettings];
    }
}

- (NSDictionary *)getApplicationInfo:(NSString *)bundleID {
    if (bundleID) {
        NSDictionary *appInfo = self.scopedApps[bundleID];
        if (appInfo) {
            return [appInfo mutableCopy];
        }
        return nil;
    }
    
    // Return all apps with their original case-preserved bundle IDs
    NSMutableDictionary *displayApps = [NSMutableDictionary dictionary];
    [self.scopedApps enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *appInfo, BOOL *stop) {
        NSMutableDictionary *displayInfo = [appInfo mutableCopy];
        NSString *originalBundleID = appInfo[@"originalBundleID"];
        if (originalBundleID) {
            // Use the original case-sensitive bundle ID
            displayInfo[@"bundleID"] = originalBundleID;
            displayApps[key] = displayInfo;
        } else {
            displayApps[key] = displayInfo;
        }
    }];
    return displayApps;
}

// Cache for application enabled status to reduce frequent lookups and logging
static NSMutableDictionary *_appEnabledCache = nil;
static NSTimeInterval _cacheExpirationTime = 30.0; // Cache results for 30 seconds

- (BOOL)isApplicationEnabled:(NSString *)bundleID {
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _appEnabledCache = [NSMutableDictionary dictionary];
    });
    
    // Check if we have a cached result that's still valid
    NSDictionary *cachedResult = _appEnabledCache[bundleID];
    if (cachedResult) {
        NSTimeInterval timestamp = [cachedResult[@"timestamp"] doubleValue];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        
        // If the cache hasn't expired, use it
        if (now - timestamp < _cacheExpirationTime) {
            return [cachedResult[@"enabled"] boolValue];
        }
    }
    
    // Only log once every 30 seconds per app to avoid spamming logs
    static NSString *lastLoggedApp = nil;
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL shouldLog = ![lastLoggedApp isEqualToString:bundleID] || (now - lastLogTime > 30.0);
    
    if (shouldLog) {
        PXLog(@"[WeaponX] IdentifierManager DEBUG: Checking if app is enabled: %@", bundleID);
        lastLoggedApp = [bundleID copy];
        lastLogTime = now;
    }
    
    // Never consider the WeaponX app itself as enabled for spoofing
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        if (shouldLog) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: WeaponX app itself is never considered enabled for spoofing");
        }
        
        // Cache the result
        _appEnabledCache[bundleID] = @{@"enabled": @NO, @"timestamp": @(now)};
        return NO;
    }
    
    // Direct equality check first for performance
    if (self.scopedApps[bundleID]) {
        BOOL isEnabled = [self.scopedApps[bundleID][@"enabled"] boolValue];
        
        if (shouldLog) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: Found app %@ in scopedApps, enabled = %@", bundleID, isEnabled ? @"YES" : @"NO");
        }
        
        // Cache the result
        _appEnabledCache[bundleID] = @{@"enabled": @(isEnabled), @"timestamp": @(now)};
        return isEnabled;
    }
    
    // Ensure we have the latest scoped apps data
    // Only reload scoped apps if we haven't reloaded recently
    static NSTimeInterval lastReloadTime = 0;
    if (now - lastReloadTime > 60.0) { // Only reload every minute at most
        if (shouldLog) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: App not found directly, reloading scoped apps");
        }
        [self loadScopedApps];
        lastReloadTime = now;
    }
    
    // Check again after potentially reloading the scoped apps
    if (self.scopedApps[bundleID]) {
        BOOL isEnabled = [self.scopedApps[bundleID][@"enabled"] boolValue];
        
        if (shouldLog) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: Found app %@ after reload, enabled = %@", bundleID, isEnabled ? @"YES" : @"NO");
        }
        
        // Cache the result
        _appEnabledCache[bundleID] = @{@"enabled": @(isEnabled), @"timestamp": @(now)};
        return isEnabled;
    }
    
    // Fallback to case-insensitive comparison if needed (this is expensive, so only log if needed)
    if (shouldLog) {
        PXLog(@"[WeaponX] IdentifierManager DEBUG: App still not found, trying case-insensitive match");
    }
    
    NSString *lowercaseBundleID = [bundleID lowercaseString];
    for (NSString *key in self.scopedApps) {
        if ([[key lowercaseString] isEqualToString:lowercaseBundleID]) {
            BOOL isEnabled = [self.scopedApps[key][@"enabled"] boolValue];
            
            if (shouldLog) {
                PXLog(@"[WeaponX] IdentifierManager DEBUG: Found app %@ via case-insensitive match with %@, enabled = %@", 
                      bundleID, key, isEnabled ? @"YES" : @"NO");
            }
            
            // Cache the result using the original bundle ID
            _appEnabledCache[bundleID] = @{@"enabled": @(isEnabled), @"timestamp": @(now)};
            return isEnabled;
        }
    }
    
    // App not found, only log this information sparingly
    if (shouldLog) {
        // Limit the keys we log to avoid excessive memory usage
        NSArray *allKeys = [self.scopedApps allKeys];
        NSArray *limitedKeys = allKeys.count > 10 ? [allKeys subarrayWithRange:NSMakeRange(0, 10)] : allKeys;
        
        PXLog(@"[WeaponX] IdentifierManager DEBUG: App %@ not found in scoped apps list", bundleID);
        PXLog(@"[WeaponX] IdentifierManager DEBUG: First %lu scoped apps: %@", (unsigned long)limitedKeys.count, limitedKeys);
    }
    
    // Cache the negative result
    _appEnabledCache[bundleID] = @{@"enabled": @NO, @"timestamp": @(now)};
    
    return NO;
}

// New method to load scoped apps configuration explicitly
- (void)loadScopedApps {
    // Try rootless path first
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    PXLog(@"[WeaponX] IdentifierManager DEBUG: Trying to load scoped apps from: %@", scopedAppsFile);
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:scopedAppsFile]) {
        PXLog(@"[WeaponX] IdentifierManager DEBUG: First path not found, trying Dopamine 2 path");
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        
        // Fallback to older paths if needed
        if (![fileManager fileExistsAtPath:scopedAppsFile]) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: Dopamine 2 path not found, trying legacy path");
            prefsPath = @"/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        }
    }
    
    PXLog(@"[WeaponX] IdentifierManager DEBUG: Loading scoped apps from: %@", scopedAppsFile);
    PXLog(@"[WeaponX] IdentifierManager DEBUG: File exists: %@", [fileManager fileExistsAtPath:scopedAppsFile] ? @"YES" : @"NO");
    
    // Load scoped apps from the global scope file
    NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
    PXLog(@"[WeaponX] IdentifierManager DEBUG: Loaded dictionary: %@", scopedAppsDict ? @"YES" : @"NO");
    
    NSDictionary *savedApps = scopedAppsDict[@"ScopedApps"];
    PXLog(@"[WeaponX] IdentifierManager DEBUG: Scoped apps entry found in dictionary: %@", savedApps ? @"YES" : @"NO");
    
    if (savedApps) {
        PXLog(@"[WeaponX] IdentifierManager DEBUG: Number of scoped apps found: %lu", (unsigned long)savedApps.count);
        if (savedApps.count > 0) {
            PXLog(@"[WeaponX] IdentifierManager DEBUG: App list includes: %@", [savedApps allKeys]);
        }
        // Make sure we properly update the scoped apps dictionary
        if (!self.scopedApps) {
            self.scopedApps = [savedApps mutableCopy];
        } else {
            [self.scopedApps setDictionary:savedApps];
        }
        PXLog(@"[WeaponX] IdentifierManager: Loaded %lu scoped apps from %@", (unsigned long)savedApps.count, scopedAppsFile);
    } else {
        // Re-initialize the app list if loading failed
        if (!self.scopedApps) {
            self.scopedApps = [NSMutableDictionary dictionary];
        } else {
            [self.scopedApps removeAllObjects];
        }
        PXLog(@"[WeaponX] IdentifierManager: ⚠️ Failed to load scoped apps, using empty list");
    }
}

#pragma mark - Persistence

- (void)saveSettings {
    // Get the proper preferences path
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
    
    // Global settings file for scoped apps (universal across all profiles)
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path first
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsFile]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            
            // If still not found, try the original filename as a fallback
            if (![fileManager fileExistsAtPath:prefsFile]) {
                prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.plist"];
            }
        }
    }
    
    // Ensure preferences directory exists with proper permissions
    NSError *dirError = nil;
    
    // Create all intermediate directories with proper permissions
    if (![fileManager fileExistsAtPath:prefsPath]) {
        NSDictionary *attributes = @{NSFilePosixPermissions: @0755,
                                    NSFileOwnerAccountName: @"mobile"};
        
        if (![fileManager createDirectoryAtPath:prefsPath 
                    withIntermediateDirectories:YES 
                                     attributes:attributes
                                          error:&dirError]) {
            self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                            code:4004 
                                        userInfo:@{NSLocalizedDescriptionKey: 
                                                  [NSString stringWithFormat:@"Failed to create preferences directory: %@", 
                                                   dirError.localizedDescription]}];
            return;
        }
    }
    
    // Create dictionary to save for main settings
    NSMutableDictionary *saveDict = [NSMutableDictionary dictionary];
    
    // Save enabled states - these are still global settings
    saveDict[@"EnabledIdentifiers"] = [self.settings copy];
    
    // Mark settings as initialized
    saveDict[@"SettingsInitialized"] = @YES;
    
    // Save main settings
    BOOL success = [saveDict writeToFile:prefsFile atomically:YES];
    if (!success) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                      code:4005 
                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to save settings"}];
        return;
    }
    
    // Save scoped apps separately in the global scope file
    NSDictionary *scopedAppsDict = @{@"ScopedApps": [self.scopedApps copy]};
    success = [scopedAppsDict writeToFile:scopedAppsFile atomically:YES];
    if (!success) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                      code:4006 
                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to save global scoped apps"}];
        return;
    }
    
    // Set proper permissions for global scope file
    NSError *permError = nil;
    NSDictionary *fileAttributes = @{NSFilePosixPermissions: @0644,
                                   NSFileOwnerAccountName: @"mobile"};
    
    if (![fileManager setAttributes:fileAttributes
                      ofItemAtPath:scopedAppsFile
                             error:&permError]) {
        NSLog(@"[ProjectX] Warning: Failed to set global scope file permissions: %@", permError);
    }

    // Set proper permissions
    if (![fileManager setAttributes:fileAttributes
                      ofItemAtPath:prefsFile
                             error:&permError]) {
        NSLog(@"[ProjectX] Warning: Failed to set preferences file permissions: %@", permError);
    }
}

- (void)loadSettings {
    // Try rootless path first
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsFile]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsFile]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.settings.plist"];
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            
            // If still not found, try the original filename as a fallback
            if (![fileManager fileExistsAtPath:prefsFile]) {
                prefsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.plist"];
            }
        }
    }
    
    // Load dictionary from main settings file
    NSDictionary *loadedDict = [NSDictionary dictionaryWithContentsOfFile:prefsFile];
    
    // Check if settings are initialized
    if (!loadedDict || ![loadedDict[@"SettingsInitialized"] boolValue]) {
        // Initialize with default values
        self.settings = [NSMutableDictionary dictionaryWithDictionary:@{
            @"IDFA": @NO,
            @"IDFV": @NO,
            @"DeviceName": @NO,
            @"SerialNumber": @NO,
            @"UDID": @NO,
            @"IMEI": @NO,
            @"SystemVersion": @NO,
            @"BuildVersion": @NO,
            @"StorageSystem": @NO,
            @"SystemBootUUID": @NO,
            @"DyldCacheUUID": @NO,
            @"PasteboardUUID": @NO,
            @"KeychainUUID": @NO,
            @"UserDefaultsUUID": @NO,
            @"AppGroupUUID": @NO,
            @"CoreDataUUID": @NO,
            @"AppInstallUUID": @NO,
            @"AppContainerUUID": @NO,
            @"SystemUptime": @NO,
            @"BootTime": @NO
        }];
        [self saveSettings];
        return;
    }
    
    // Load enabled states
    NSDictionary *savedSettings = loadedDict[@"EnabledIdentifiers"];
    if (savedSettings) {
        [self.settings setDictionary:savedSettings];
    }
    
    // Load scoped apps from the global scope file
    NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
    NSDictionary *savedApps = scopedAppsDict[@"ScopedApps"];
    
    // If not found in global scope file, try the legacy location
    if (!savedApps && loadedDict[@"ScopedApps"]) {
        savedApps = loadedDict[@"ScopedApps"];
        NSLog(@"[ProjectX] Loaded scoped apps from legacy location, will migrate to global file");
    }
    
    if (savedApps) {
        [self.scopedApps setDictionary:savedApps];
    }
    
    // We no longer load identifier values from global settings as they're profile-specific
}

#pragma mark - Error Handling

- (NSError *)lastError {
    return self.error;
}

- (NSString *)generateWiFiInformation {
    // Use WiFiManager to generate new WiFi info
    id wifiManager = NSClassFromString(@"WiFiManager");
    if (wifiManager && [wifiManager respondsToSelector:@selector(sharedManager)]) {
        id sharedManager = [wifiManager sharedManager];
        if (sharedManager && [sharedManager respondsToSelector:@selector(generateWiFiInfo)]) {
            NSDictionary *wifiInfo = [sharedManager generateWiFiInfo];
            if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
                NSString *formattedValue = [NSString stringWithFormat:@"%@ (%@)", wifiInfo[@"ssid"], wifiInfo[@"bssid"]];
                PXLog(@"Generated new WiFi information: %@", formattedValue);
                return formattedValue;
            }
        }
    }
    
    PXLog(@"Failed to generate WiFi information");
    return nil;
}

- (NSArray *)availableIdentifiers {
    // Return all available identifiers
    NSArray *identifiers = @[
        @"IDFA",
        @"IDFV",
        @"DeviceName",
        @"SerialNumber",
        @"IOSVersion",
        @"WiFi",
        @"StorageSystem",
        @"Battery",
        @"SystemBootUUID",
        @"DyldCacheUUID",
        @"PasteboardUUID",
        @"KeychainUUID",
        @"UserDefaultsUUID",
        @"AppGroupUUID",
        @"CoreDataUUID",
        @"AppInstallUUID",
        @"AppContainerUUID",
        @"SystemUptime",
        @"BootTime"
    ];
    
    return identifiers;
}

- (void)addApplicationWithExtensionsToScope:(NSString *)bundleID {
    if (!bundleID || [bundleID isEqualToString:@"com.hydra.projectx"]) {
        return;
    }
    
    // First add the main app
    [self addApplicationToScope:bundleID];
    
    // Create a more specific extension pattern
    // Instead of just using first component, use the main app's bundle ID as base
    NSString *extensionPattern = [NSString stringWithFormat:@"%@.*", bundleID];
    
    // Store the extension pattern in the app's info
    NSMutableDictionary *appInfo = [self.scopedApps[bundleID] mutableCopy];
    if (appInfo) {
        appInfo[@"extensionPattern"] = extensionPattern;
        self.scopedApps[bundleID] = appInfo;
        [self saveScopedApps];
        
        PXLog(@"[WeaponX] Added extension pattern: %@ for app: %@", extensionPattern, bundleID);
    }
}
- (BOOL)isScope{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    // NSLog(@"%s app",bundleID);
    // if([self isExtensionEnabled:bundleID]){
    //     NSLog(@"%s app is selected",bundleID);
    // }
    // NSLog(@"%s app is not selected",bundleID);
    if (!bundleID) return NO;
    
    // 是自己直接返回 不是则判断是否选中
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        return NO;
    }
    
    // Check each scoped app's extension pattern
    for (NSString *scopedBundleID in self.scopedApps) {
        NSDictionary *appInfo = self.scopedApps[scopedBundleID];
        if (scopedBundleID && [self isBundleIDMatch:bundleID withPattern:scopedBundleID]) {
            // PXLog(@"[WeaponX] Bundle ID %@ matches extension pattern %@ from app %@", bundleID, extensionPattern, scopedBundleID);
            return [appInfo[@"enabled"] boolValue];
        }
    }
    
    return NO;
}
- (BOOL)isBundleIDMatch:(NSString *)targetBundleID withPattern:(NSString *)patternBundleID {
    if (!targetBundleID || !patternBundleID) return NO;
    
    // Convert pattern to regex, escaping all dots except the wildcard
    NSString *regexPattern = [patternBundleID stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
    regexPattern = [regexPattern stringByReplacingOccurrencesOfString:@"\\.*" withString:@".*"];
    regexPattern = [NSString stringWithFormat:@"^%@$", regexPattern];
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&error];
    if (error) {
        PXLog(@"[WeaponX] Error creating regex for pattern %@: %@", patternBundleID, error);
        return NO;
    }
    
    NSRange range = NSMakeRange(0, targetBundleID.length);
    NSTextCheckingResult *match = [regex firstMatchInString:targetBundleID options:0 range:range];
    
    BOOL matches = (match != nil);
    if (matches) {
        PXLog(@"[WeaponX] Bundle ID: %@ matches pattern: %@", targetBundleID, patternBundleID);
    }
    
    return matches;
}


- (void)saveScopedApps {
    // Get the proper preferences path
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path first
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:scopedAppsFile]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        }
    }
    
    // Save scoped apps separately in the global scope file
    NSDictionary *scopedAppsDict = @{@"ScopedApps": [self.scopedApps copy]};
    BOOL success = [scopedAppsDict writeToFile:scopedAppsFile atomically:YES];
    if (!success) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                      code:4006 
                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to save global scoped apps"}];
        return;
    }
    
    // Set proper permissions for global scope file
    NSError *permError = nil;
    NSDictionary *fileAttributes = @{NSFilePosixPermissions: @0644,
                                   NSFileOwnerAccountName: @"mobile"};
    
    if (![fileManager setAttributes:fileAttributes
                      ofItemAtPath:scopedAppsFile
                             error:&permError]) {
        NSLog(@"[ProjectX] Warning: Failed to set global scope file permissions: %@", permError);
    }
}

- (BOOL)isExtensionEnabled:(NSString *)bundleID {
    if (!bundleID) return NO;
    
    // 是自己直接返回 不是则判断是否选中
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        return NO;
    }
    
    // Check each scoped app's extension pattern
    for (NSString *scopedBundleID in self.scopedApps) {
        NSDictionary *appInfo = self.scopedApps[scopedBundleID];
        NSString *extensionPattern = appInfo[@"extensionPattern"];
        NSLog(@"%@ match %@",bundleID,scopedBundleID);
        if (extensionPattern && [self isBundleIDMatch:bundleID withPattern:extensionPattern]) {
            PXLog(@"[WeaponX] Bundle ID %@ matches extension pattern %@ from app %@", bundleID, extensionPattern, scopedBundleID);
            return [appInfo[@"enabled"] boolValue];
        }
    }
    
    return NO;
}

#pragma mark - Custom Values




- (NSString *)generateIMEI {
    // Use a realistic US iPhone TAC (Type Allocation Code)
    NSArray *usTACs = @[ @"353918", @"356938", @"359254", @"353915", @"353920", @"353929", @"353997", @"354994" ];
    NSString *tac = usTACs[arc4random_uniform((uint32_t)usTACs.count)];
    NSMutableString *imei = [NSMutableString stringWithString:tac];
    // 8 digits for SNR
    for (int i = 0; i < 8; i++) {
        [imei appendFormat:@"%d", arc4random_uniform(10)];
    }
    // Luhn check digit
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int digit = [imei characterAtIndex:i] - '0';
        if (i % 2 == 1) digit *= 2;
        if (digit > 9) digit -= 9;
        sum += digit;
    }
    int checkDigit = (10 - (sum % 10)) % 10;
    [imei appendFormat:@"%d", checkDigit];
    [self setValueForType:imei forType:@"IMEI"];
    return imei;
}

- (NSString *)generateMEID {
    // Use a realistic US MEID prefix (A00000, A10000, 990000)
    NSArray *usMEIDPrefixes = @[ @"A00000", @"A10000", @"990000" ];
    NSString *prefix = usMEIDPrefixes[arc4random_uniform((uint32_t)usMEIDPrefixes.count)];
    NSMutableString *meid = [NSMutableString stringWithString:prefix];
    // 8 hex digits for the rest
    for (int i = 0; i < 8; i++) {
        [meid appendFormat:@"%X", arc4random_uniform(16)];
    }
    [self setValueForType:meid forType:@"MEID"];
    return meid;
}

// IMEI validation: 15 digits, Luhn valid, US TAC
- (BOOL)isValidIMEI:(NSString *)imei {
    if (imei.length != 15) return NO;
    if (![self isAllDigits:imei]) return NO;
    // Check TAC
    NSArray *usTACs = @[ @"353918", @"356938", @"359254", @"353915", @"353920", @"353929", @"353997", @"354994" ];
    NSString *tac = [imei substringToIndex:6];
    if (![usTACs containsObject:tac]) return NO;
    // Luhn check
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int digit = [imei characterAtIndex:i] - '0';
        if (i % 2 == 1) digit *= 2;
        if (digit > 9) digit -= 9;
        sum += digit;
    }
    int checkDigit = (10 - (sum % 10)) % 10;
    return (checkDigit == ([imei characterAtIndex:14] - '0'));
}

// MEID validation: 14 hex digits, US prefix
- (BOOL)isValidMEID:(NSString *)meid {
    if (meid.length != 14) return NO;
    NSArray *usMEIDPrefixes = @[ @"A00000", @"A10000", @"990000" ];
    NSString *prefix = [meid substringToIndex:6];
    if (![usMEIDPrefixes containsObject:prefix]) return NO;
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"];
    for (NSUInteger i = 0; i < meid.length; i++) {
        unichar c = [meid characterAtIndex:i];
        if (![hexSet characterIsMember:c]) return NO;
    }
    return YES;
}

- (BOOL)isAllDigits:(NSString *)string {
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return ([string rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
}




- (BOOL)validateUUID:(NSString *)uuid {
    if (!uuid) return NO;
    
    // Verify format: 8-4-4-4-12 hexadecimal characters
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
                                                                           options:NSRegularExpressionCaseInsensitive 
                                                                             error:nil];
    
    NSUInteger matches = [regex numberOfMatchesInString:uuid 
                                                options:0 
                                                  range:NSMakeRange(0, uuid.length)];
    
    return matches == 1;
}

#pragma mark - Device Model Specifications

- (NSDictionary *)getDeviceModelSpecifications {
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    if (!identityDir) return nil;
    
    // First, check the device_model.plist file for detailed specifications
    NSString *modelPath = [identityDir stringByAppendingPathComponent:@"device_model.plist"];
    NSDictionary *modelDict = [NSDictionary dictionaryWithContentsOfFile:modelPath];
    
    if (modelDict && modelDict.count > 0) {
        return modelDict;
    }
    
    // If not found in dedicated file, check the combined device_ids.plist
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    
    if (deviceIds && deviceIds[@"DeviceModel"]) {
        NSMutableDictionary *specs = [NSMutableDictionary dictionary];
        
        specs[@"value"] = deviceIds[@"DeviceModel"];
        specs[@"name"] = deviceIds[@"DeviceModelName"] ?: @"Unknown";
        specs[@"screenResolution"] = deviceIds[@"ScreenResolution"] ?: @"Unknown";
        specs[@"viewportResolution"] = deviceIds[@"ViewportResolution"] ?: @"Unknown";
        specs[@"devicePixelRatio"] = deviceIds[@"DevicePixelRatio"] ?: @(0);
        specs[@"screenDensity"] = deviceIds[@"ScreenDensityPPI"] ?: @(0);
        specs[@"cpuArchitecture"] = deviceIds[@"CPUArchitecture"] ?: @"Unknown";
        specs[@"deviceMemory"] = deviceIds[@"DeviceMemory"] ?: @(0);
        specs[@"gpuFamily"] = deviceIds[@"GPUFamily"] ?: @"Unknown";
        specs[@"cpuCoreCount"] = deviceIds[@"CPUCoreCount"] ?: @(0);
        specs[@"metalFeatureSet"] = deviceIds[@"MetalFeatureSet"] ?: @"Unknown";
        
        // Rebuild webGLInfo from simplified fields
        NSMutableDictionary *webGLInfo = [NSMutableDictionary dictionary];
        webGLInfo[@"webglVendor"] = deviceIds[@"WebGLVendor"] ?: @"Apple";
        webGLInfo[@"webglRenderer"] = deviceIds[@"WebGLRenderer"] ?: @"Apple GPU";
        webGLInfo[@"unmaskedVendor"] = @"Apple Inc.";
        webGLInfo[@"unmaskedRenderer"] = deviceIds[@"GPUFamily"] ?: @"Apple GPU";
        webGLInfo[@"webglVersion"] = @"WebGL 2.0";
        webGLInfo[@"maxTextureSize"] = @(16384);
        webGLInfo[@"maxRenderBufferSize"] = @(16384);
        
        specs[@"webGLInfo"] = webGLInfo;
        
        return specs;
    }
    
    // If still not found, get the current device model and fetch its specs
    NSString *currentDeviceModel = [self currentValueForIdentifier:@"DeviceModel"];
    if (currentDeviceModel) {
        DeviceModelManager *deviceManager = [DeviceModelManager sharedManager];
        NSMutableDictionary *specs = [NSMutableDictionary dictionary];
        
        specs[@"value"] = currentDeviceModel;
        specs[@"name"] = [deviceManager deviceModelNameForString:currentDeviceModel] ?: @"Unknown";
        specs[@"screenResolution"] = [deviceManager screenResolutionForModel:currentDeviceModel] ?: @"Unknown";
        specs[@"viewportResolution"] = [deviceManager viewportResolutionForModel:currentDeviceModel] ?: @"Unknown";
        specs[@"devicePixelRatio"] = @([deviceManager devicePixelRatioForModel:currentDeviceModel]);
        specs[@"screenDensity"] = @([deviceManager screenDensityForModel:currentDeviceModel]);
        specs[@"cpuArchitecture"] = [deviceManager cpuArchitectureForModel:currentDeviceModel] ?: @"Unknown";
        specs[@"deviceMemory"] = @([deviceManager deviceMemoryForModel:currentDeviceModel]);
        specs[@"gpuFamily"] = [deviceManager gpuFamilyForModel:currentDeviceModel] ?: @"Unknown";
        specs[@"cpuCoreCount"] = @([deviceManager cpuCoreCountForModel:currentDeviceModel]);
        specs[@"metalFeatureSet"] = [deviceManager metalFeatureSetForModel:currentDeviceModel] ?: @"Unknown";
        specs[@"webGLInfo"] = [deviceManager webGLInfoForModel:currentDeviceModel] ?: @{};
        
        return specs;
    }
    
    
    return nil;
}

- (NSString *)getScreenResolution {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"screenResolution"] : @"Unknown";
}

- (NSString *)getViewportResolution {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"viewportResolution"] : @"Unknown";
}

- (CGFloat)getDevicePixelRatio {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? [specs[@"devicePixelRatio"] floatValue] : 0.0;
}

- (NSInteger)getScreenDensity {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? [specs[@"screenDensity"] integerValue] : 0;
}

- (NSString *)getCPUArchitecture {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"cpuArchitecture"] : @"Unknown";
}

- (NSInteger)getDeviceMemory {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? [specs[@"deviceMemory"] integerValue] : 0;
}

- (NSString *)getGPUFamily {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"gpuFamily"] : @"Unknown";
}

- (NSDictionary *)getWebGLInfo {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"webGLInfo"] : @{};
}

- (NSInteger)getCPUCoreCount {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? [specs[@"cpuCoreCount"] integerValue] : 0;
}

- (NSString *)getMetalFeatureSet {
    NSDictionary *specs = [self getDeviceModelSpecifications];
    return specs ? specs[@"metalFeatureSet"] : @"Unknown";
}

// Device Theme Methods
- (NSString *)generateDeviceTheme {
    // Generate a random theme (Light or Dark)
    NSArray *themes = @[@"Light", @"Dark"];
    NSInteger randomIndex = arc4random_uniform(2);
    NSString *theme = themes[randomIndex];
    
    // Save the theme to the profile
    [self setCustomDeviceTheme:theme];
    
    return theme;
}

- (NSString *)toggleDeviceTheme {
    // Get current theme
    NSString *currentTheme = [self getValueForType:@"DeviceTheme"];
    
    // Toggle between Light and Dark
    NSString *newTheme;
    if ([currentTheme isEqualToString:@"Light"]) {
        newTheme = @"Dark";
    } else {
        newTheme = @"Light";
    }
    
    // Save the new theme
    [self setCustomDeviceTheme:newTheme];
    
    return newTheme;
}

- (BOOL)setCustomDeviceTheme:(NSString *)value {
    // Validate theme value
    if (![value isEqualToString:@"Light"] && ![value isEqualToString:@"Dark"]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" code:2004 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Device Theme (must be 'Light' or 'Dark')"}];
        return NO;
    }
    
    NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
    BOOL success = NO;
    
    if (identityDir) {
        // Create dictionary with theme value
        NSDictionary *themeDict = @{
            @"value": value,
            @"lastUpdated": [NSDate date]
        };
        
        // Save to device_theme.plist
        NSString *themePath = [identityDir stringByAppendingPathComponent:@"device_theme.plist"];
        success = [themeDict writeToFile:themePath atomically:YES];
        
        // Also update the combined device_ids.plist
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
        
        // Add theme to device_ids.plist
        deviceIds[@"DeviceTheme"] = value;
        
        success = [deviceIds writeToFile:deviceIdsPath atomically:YES];
    }
    
    return success;
}

#pragma mark - Canvas Fingerprinting Protection

- (BOOL)toggleCanvasFingerprintProtection {
    BOOL currentValue = [self isCanvasFingerprintProtectionEnabled];
    BOOL newValue = !currentValue;
    
    // Update settings
    [self setCanvasFingerprintProtection:newValue];
    
    // Notify change
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hydra.projectx.toggleCanvasFingerprint"),
        NULL, NULL, TRUE
    );
    
    PXLog(@"[WeaponX] 🎨 Canvas Fingerprint Protection %@", newValue ? @"ENABLED" : @"DISABLED");
    
    return newValue;
}

- (BOOL)isCanvasFingerprintProtectionEnabled {
    // Read directly from the plist file - SINGLE SOURCE OF TRUTH
    NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
    NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:securitySettingsPath];
    
    if (settingsDict) {
        if (settingsDict[@"canvasFingerprintingEnabled"] != nil) {
            return [settingsDict[@"canvasFingerprintingEnabled"] boolValue];
        }
        if (settingsDict[@"CanvasFingerprint"] != nil) {
            return [settingsDict[@"CanvasFingerprint"] boolValue];
        }
    }
    
    return NO; // Default to disabled if settings file doesn't exist
}

- (BOOL)setCanvasFingerprintProtection:(BOOL)enabled {
    // Read and update the plist file directly - SINGLE SOURCE OF TRUTH
    NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
    NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
    
    // Update with both key names for compatibility
    settingsDict[@"canvasFingerprintingEnabled"] = @(enabled);
    settingsDict[@"CanvasFingerprint"] = @(enabled);
    
    // Write back to the file
    BOOL success = [settingsDict writeToFile:securitySettingsPath atomically:YES];
    
    // Also update our in-memory settings to keep them in sync
    if (success) {
        NSMutableDictionary *updatedSettings = [self.settings mutableCopy];
        updatedSettings[@"canvasFingerprintingEnabled"] = @(enabled);
        updatedSettings[@"CanvasFingerprint"] = @(enabled);
        self.settings = updatedSettings;
    }
    
    // Notify about the change
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hydra.projectx.settings.changed"),
        NULL, NULL, TRUE
    );
    
    return YES;
}

- (void)resetCanvasNoise {
    // Post notification to reset canvas noise seeds
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hydra.projectx.resetCanvasNoise"),
        NULL, NULL, TRUE
    );
    
    PXLog(@"[WeaponX] 🎨 Canvas Fingerprint Noise patterns reset");
}

@end
