#import "UptimeManager.h"
#import <sys/sysctl.h>
#import "ProjectXLogging.h"
#import "IdentifierManager.h"
// File paths for persistent storage
// Removed global paths. All methods now require a profile-specific path.

// Keys for plist dictionaries
static NSString * const kBootTimeKey = @"bootTime";
static NSString * const kUptimeKey = @"uptime";
static NSString * const kCreationTimeKey = @"creationTime";

#ifndef kUptimeVersionKey
#define kUptimeVersionKey @"version"
#endif

@interface UptimeManager ()
@property (nonatomic, strong) NSDate *bootTimeValue;
@property (nonatomic, assign) NSTimeInterval uptimeValue;
@property (nonatomic, strong) NSDate *cacheTime;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
@end

@implementation UptimeManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static UptimeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize with default values
        _bootTimeValue = nil;
        _uptimeValue = 0;
        _cacheTime = nil;
        _concurrentQueue = dispatch_queue_create("com.weaponx.UptimeManager", DISPATCH_QUEUE_CONCURRENT);
        
        // Load saved values if they exist

    }
    return self;
}

#pragma mark - Uptime Generation



- (void)setCurrentUptime:(NSTimeInterval)uptime {
    if (uptime <= 0) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                         code:1001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Uptime must be greater than 0"}];
        return;
    }
    self.uptimeValue = uptime;
    self.cacheTime = [NSDate date];
    self.bootTimeValue = [NSDate dateWithTimeIntervalSinceNow:-uptime];
    PXLog(@"[WeaponX] 🕒 Set system uptime: %.2f hours", uptime / 3600.0);
}

#pragma mark - Boot Time Generation



- (void)setCurrentBootTime:(NSDate *)bootTime {
    if (!bootTime) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Boot time cannot be nil"}];
        return;
    }
    self.bootTimeValue = bootTime;
    self.cacheTime = [NSDate date];
    NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootTime];
    self.uptimeValue = uptime;
    PXLog(@"[WeaponX] 🕒 Set boot time: %@", bootTime);
}

#pragma mark - Consistent Uptime Generation

// Implementation already defined at the top of file

#pragma mark - Error Handling

- (NSError *)lastError {
    return self.error;
}

#pragma mark - Helper Methods

// Legacy API: stub implementations to satisfy linker, but not used in profile-specific logic
- (NSTimeInterval)generateUptime {
        NSTimeInterval minUptime = 12 * 3600; // 12 hours
        NSTimeInterval maxUptime = 48 * 3600; // 48 hours
        NSTimeInterval uptimeRange = maxUptime - minUptime;
        NSTimeInterval randomPart = arc4random_uniform((uint32_t)uptimeRange);
        NSTimeInterval extraSeconds = arc4random_uniform(60 * 45);
        NSTimeInterval uptime = minUptime + randomPart + extraSeconds;
        
        // Check real uptime to ensure spoofed value isn't higher
        struct timeval boottv = {0};
        size_t sz = sizeof(boottv);
        int mib[2] = {CTL_KERN, KERN_BOOTTIME};
        int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
        if (sysctlResult == 0) {
            NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
            NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
            if (uptime > realUptime - 60) {
                uptime = realUptime - 60;
            }
            if (uptime < minUptime) uptime = minUptime;
        }
        

        // Also save to system_uptime.plist for apps that might look there
        // NSString *uptimeString = [NSString stringWithFormat:@"%.0f", uptime];
  
        self.uptimeValue = uptime;
        return uptime;
}
- (NSTimeInterval)currentUptime {
    NSTimeInterval uptime = [[[IdentifierManager sharedManager] getValueForType:@"SystemUptime"] doubleValue];
    return uptime;
}
- (NSDate *)generateBootTime {
     // Generate a random uptime between 12-48 hours with added randomness
    NSTimeInterval minUptime = 12 * 3600; // 12 hours
    NSTimeInterval maxUptime = 48 * 3600; // 48 hours
    NSTimeInterval uptimeRange = maxUptime - minUptime;
    NSTimeInterval randomPart = arc4random_uniform((uint32_t)uptimeRange);
    NSTimeInterval extraSeconds = arc4random_uniform(60 * 45);
    NSTimeInterval uptime = minUptime + randomPart + extraSeconds;
    
    // Check real uptime to ensure spoofed value isn't higher
    struct timeval boottv = {0};
    size_t sz = sizeof(boottv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
    if (sysctlResult == 0) {
        NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
        NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
        if (uptime > realUptime - 60) {
            uptime = realUptime - 60;
        }
        if (uptime < minUptime) uptime = minUptime;
    }
    
    // Calculate boot time based on generated uptime
    NSDate *now = [NSDate date];
    NSDate *bootTime = [NSDate dateWithTimeIntervalSinceNow:-uptime];
    

    // Set cache values for use in other methods
    self.bootTimeValue = bootTime;
    self.cacheTime = now;
    return bootTime;
}
- (NSDate *)currentBootTime {
    NSTimeInterval timestamp = [[[IdentifierManager sharedManager] getValueForType:@"BootTime"] doubleValue];
    if (timestamp > 0) {
        return [NSDate dateWithTimeIntervalSince1970:timestamp];
    }
    return [NSDate dateWithTimeIntervalSinceNow:-(12 * 3600)]; // 12 hours ago as safe default
}

- (NSString *)debugSpoofedUptimeInfo {
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"Spoofed Uptime: %.0f seconds (%.2f hours)\n", self.uptimeValue, self.uptimeValue/3600.0];
    [result appendFormat:@"Spoofed Boot Time: %@ (timestamp: %.0f)\n", self.bootTimeValue, [self.bootTimeValue timeIntervalSince1970]];
    // Try to get real uptime
    struct timeval boottv = {0};
    size_t sz = sizeof(boottv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
    if (sysctlResult == 0) {
        NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
        NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
        [result appendFormat:@"Real Uptime: %.0f seconds (%.2f hours)\n", realUptime, realUptime/3600.0];
        [result appendFormat:@"Real Boot Time: %@ (timestamp: %.0f)\n", realBoot, [realBoot timeIntervalSince1970]];
    }
    [result appendFormat:@"Cache Time: %@\n", self.cacheTime];
    return result;
}

- (BOOL)validateBootTimeConsistencyForProfile:(NSString *)profilePath {
    if (!profilePath || [profilePath length] == 0) {
        return NO;
    }
    
    NSDate *bootTimeFromPlist = nil;
    NSTimeInterval bootTimeFromDeviceIds = 0;
    
    // Read boot time from boot_time.plist
    NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
    NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        bootTimeFromPlist = bootTimeDict[@"value"];
    }
    
    // Read boot time from device_ids.plist
    NSString *deviceIdsPath = [profilePath stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    if (deviceIds && deviceIds[@"BootTime"]) {
        bootTimeFromDeviceIds = [deviceIds[@"BootTime"] doubleValue];
    }
    
    // Check consistency (allow 1 second tolerance)
    if (bootTimeFromPlist && bootTimeFromDeviceIds > 0) {
        NSTimeInterval difference = fabs([bootTimeFromPlist timeIntervalSince1970] - bootTimeFromDeviceIds);
        BOOL isConsistent = difference <= 1.0;
        
        if (!isConsistent) {
            PXLog(@"[WeaponX] ⚠️ Boot time inconsistency detected in profile %@: plist=%.0f, device_ids=%.0f (diff=%.2f)", 
                  profilePath, [bootTimeFromPlist timeIntervalSince1970], bootTimeFromDeviceIds, difference);
        }
        
        return isConsistent;
    }
    
    return NO;
}

@end 