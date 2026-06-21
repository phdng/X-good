#import "ContainerManager.h"
#import "common/PXPaths.h"
#import <Foundation/Foundation.h>

@interface ContainerManager ()
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation ContainerManager

+ (instancetype)sharedManager {
    static ContainerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (instancetype)sharedInstance {
    return [self sharedManager];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

#pragma mark - Path Translation

- (NSString *)translatePath:(NSString *)originalPath forApp:(NSString *)bundleID inProfile:(NSString *)profileID {
    if (!bundleID || !originalPath || originalPath.length == 0) {
        return originalPath;
    }

    if (![self isPathRedirectable:originalPath forApp:bundleID]) {
        return originalPath;
    }
    
    if (!profileID) {
        profileID = [self currentProfileID];
        if (!profileID) {
            return originalPath;
        }
    }
    
    NSString *appDataPath = [self appDataPath:bundleID inProfile:profileID];
    NSArray<NSString *> *prefixes = @[@"/var/mobile/Library", @"/private/var/mobile/Library"];
    for (NSString *prefix in prefixes) {
        if ([originalPath isEqualToString:prefix] || [originalPath hasPrefix:[prefix stringByAppendingString:@"/"]]) {
            NSString *suffix = [originalPath substringFromIndex:prefix.length];
            NSString *redirectBase = [appDataPath stringByAppendingPathComponent:@"Library"];
            return [redirectBase stringByAppendingString:suffix ?: @""];
        }
    }
    return originalPath;
}

- (BOOL)isPathRedirectable:(NSString *)path forApp:(NSString *)bundleID {
    if (!path.length || !bundleID.length) {
        return NO;
    }
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        return NO;
    }
    return [path isEqualToString:@"/var/mobile/Library"] ||
           [path hasPrefix:@"/var/mobile/Library/"] ||
           [path isEqualToString:@"/private/var/mobile/Library"] ||
           [path hasPrefix:@"/private/var/mobile/Library/"];
}

#pragma mark - Directory Structure

- (NSString *)profileBasePath:(NSString *)profileID {
    NSString *basePath = PXProfilesPath();
    return [basePath stringByAppendingPathComponent:profileID];
}

- (NSString *)appBasePath:(NSString *)profileID bundleID:(NSString *)bundleID {
    NSString *profilePath = [self profileBasePath:profileID];
    NSString *appDataPath = [profilePath stringByAppendingPathComponent:@"appdata"];
    return [appDataPath stringByAppendingPathComponent:bundleID];
}

- (NSString *)appDataPath:(NSString *)bundleID inProfile:(NSString *)profileID {
    return [self appBasePath:profileID bundleID:bundleID];
}

#pragma mark - Profile Integration

- (void)profileDidChange:(NSString *)newProfileID {
    _currentProfileID = newProfileID;
}

- (BOOL)prepareProfileDirectory:(NSString *)profileID {
    NSString *basePath = [self profileBasePath:profileID];
    NSError *error = nil;
    BOOL success = [self.fileManager createDirectoryAtPath:basePath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&error];
    
    if (!success) {
        NSLog(@"[WeaponX] Failed to prepare profile directory: %@", error);
    }
    
    return success;
}

#pragma mark - System App Detection

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }
    
    NSString *appPath = [NSString stringWithFormat:@"/Applications/%@.app", bundleID];
    return [self.fileManager fileExistsAtPath:appPath];
}

+ (NSString *)translatePathForEnvironment:(NSString *)path {
    if (!path) {
        return nil;
    }
    
    if ([path hasPrefix:@"/var/mobile/Library"]) {
        NSString *mobileLibrary = PXMobileLibraryPath();
        NSString *suffix = [path substringFromIndex:@"/var/mobile/Library".length];
        return [mobileLibrary stringByAppendingString:suffix ?: @""];
    }
    
    return path;
}

@end
