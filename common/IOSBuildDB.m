#import "IOSBuildDB.h"
#import "VersionCompare.h"
#import "DBDebugLogger.h"
#import <Security/Security.h>

static NSString *const kIOSBuildDBErrorDomain = @"com.hydra.projectx.ios_build_db";

static NSUInteger PXRandomIndex(NSUInteger upperBoundExclusive) {
    if (upperBoundExclusive == 0) return 0;
    uint32_t r = 0;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(r), (uint8_t *)&r) == errSecSuccess) {
        return (NSUInteger)(r % (uint32_t)upperBoundExclusive);
    }
    return (NSUInteger)arc4random_uniform((uint32_t)upperBoundExclusive);
}

static NSDictionary * _Nullable PXLoadJSONDictionaryAtPath(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;

    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON root (expected dictionary)"}];
        }
        return nil;
    }
    return (NSDictionary *)obj;
}

@interface IOSBuildDB ()
@property (nonatomic, strong) NSDictionary *db;
@property (nonatomic, strong) NSDictionary *buildToMeta;
@property (nonatomic, strong) NSDictionary *deviceToBuilds;
@end

@implementation IOSBuildDB

+ (instancetype)sharedManager {
    static IOSBuildDB *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[IOSBuildDB alloc] init];
    });
    return shared;
}

- (BOOL)loadIfNeeded:(NSError **)error {
    if (self.db) return YES;

    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/WeaponX/Data/ios_build_db.json",
        @"/private/var/mobile/Library/WeaponX/Data/ios_build_db.json"
    ];

    NSError *lastErr = nil;
    NSDictionary *root = nil;
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            root = PXLoadJSONDictionaryAtPath(p, &lastErr);
            if (root) break;
        }
    }

    if (!root) {
        if (error) {
            *error = lastErr ?: [NSError errorWithDomain:kIOSBuildDBErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"ios_build_db.json not found"}];
        }
        PXDBLog(@"IOSBuildDB: failed to load JSON (paths=%@) err=%@", paths, lastErr.localizedDescription ?: @"nil");
        return NO;
    }

    NSNumber *schema = root[@"schemaVersion"];
    if (![schema isKindOfClass:[NSNumber class]] || schema.integerValue != 1) {
        if (error) {
            *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported schemaVersion"}];
        }
        PXDBLog(@"IOSBuildDB: unsupported schemaVersion=%@", schema);
        return NO;
    }

    NSDictionary *btm = root[@"buildToMeta"];
    NSDictionary *dtb = root[@"deviceToBuilds"];
    if (![btm isKindOfClass:[NSDictionary class]] || ![dtb isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: @"Missing buildToMeta/deviceToBuilds"}];
        }
        PXDBLog(@"IOSBuildDB: missing buildToMeta/deviceToBuilds (btm=%@ dtb=%@)", NSStringFromClass([btm class]), NSStringFromClass([dtb class]));
        return NO;
    }

    self.db = root;
    self.buildToMeta = btm;
    self.deviceToBuilds = dtb;
    return YES;
}

- (NSDictionary *)randomMetaForDevice:(NSString *)productType
                                   min:(NSString *)minVersion
                                   max:(NSString *)maxVersion
                                 error:(NSError **)error {
    if (![self loadIfNeeded:error]) return nil;
    if (productType.length == 0) {
        if (error) *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:5 userInfo:@{NSLocalizedDescriptionKey: @"Missing productType"}];
        return nil;
    }

    id buildsObj = self.deviceToBuilds[productType];
    if (![buildsObj isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:6 userInfo:@{NSLocalizedDescriptionKey: @"No builds for device"}];
        PXDBLog(@"IOSBuildDB: no deviceToBuilds entry for device=%@", productType);
        return nil;
    }

    NSArray *builds = (NSArray *)buildsObj;
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSUInteger missingMeta = 0;
    NSUInteger missingFields = 0;
    NSUInteger kernelMismatch = 0;
    NSUInteger outOfRange = 0;

    for (id b in builds) {
        if (![b isKindOfClass:[NSString class]]) continue;
        NSString *build = (NSString *)b;
        NSDictionary *meta = self.buildToMeta[build];
        if (![meta isKindOfClass:[NSDictionary class]]) {
            missingMeta += 1;
            continue;
        }

        NSString *version = meta[@"version"];
        NSString *darwin = meta[@"darwin"];
        NSString *xnu = meta[@"xnu"];
        NSString *kernel = meta[@"kernel_version"];

        if (![version isKindOfClass:[NSString class]] || ![darwin isKindOfClass:[NSString class]] || ![xnu isKindOfClass:[NSString class]] || ![kernel isKindOfClass:[NSString class]]) {
            missingFields += 1;
            continue;
        }

        if (!PXVersionInRange(version, minVersion, maxVersion)) {
            outOfRange += 1;
            continue;
        }

        // Guardrails: kernel string must match darwin/xnu
        NSString *darwinNeedle = [NSString stringWithFormat:@"Darwin Kernel Version %@", darwin];
        NSString *xnuNeedle = [NSString stringWithFormat:@"xnu-%@", xnu];
        if ([kernel rangeOfString:darwinNeedle].location == NSNotFound || [kernel rangeOfString:xnuNeedle].location == NSNotFound) {
            kernelMismatch += 1;
            continue;
        }

        NSMutableDictionary *full = [meta mutableCopy];
        full[@"build"] = build;
        [candidates addObject:full];
    }

    if (candidates.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kIOSBuildDBErrorDomain code:7 userInfo:@{NSLocalizedDescriptionKey: @"No compatible iOS builds in range for this device"}];
        }
        PXDBLog(@"IOSBuildDB: no candidates for device=%@ range=[%@..%@] totalBuilds=%lu missingMeta=%lu missingFields=%lu outOfRange=%lu kernelMismatch=%lu", productType, minVersion, maxVersion, (unsigned long)builds.count, (unsigned long)missingMeta, (unsigned long)missingFields, (unsigned long)outOfRange, (unsigned long)kernelMismatch);
        return nil;
    }

    NSDictionary *pick = candidates[PXRandomIndex(candidates.count)];
    return pick;
}

@end
