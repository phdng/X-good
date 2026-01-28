#import "IPhoneModelDB.h"
#import "VersionCompare.h"
#import "DBDebugLogger.h"
#import <Security/Security.h>

static NSString *const kIPhoneModelDBErrorDomain = @"com.hydra.projectx.iphone_model_db";

static NSUInteger PXRandomIndex2(NSUInteger upperBoundExclusive) {
    if (upperBoundExclusive == 0) return 0;
    uint32_t r = 0;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(r), (uint8_t *)&r) == errSecSuccess) {
        return (NSUInteger)(r % (uint32_t)upperBoundExclusive);
    }
    return (NSUInteger)arc4random_uniform((uint32_t)upperBoundExclusive);
}

static NSDictionary * _Nullable PXLoadJSONDictionaryAtPath2(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON root (expected dictionary)"}];
        }
        return nil;
    }
    return (NSDictionary *)obj;
}

@interface IPhoneModelDB ()
@property (nonatomic, strong) NSDictionary *db;
@property (nonatomic, strong) NSArray<NSDictionary *> *models;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *byProductType;
@end

@implementation IPhoneModelDB

+ (instancetype)sharedManager {
    static IPhoneModelDB *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[IPhoneModelDB alloc] init];
    });
    return shared;
}

- (BOOL)loadIfNeeded:(NSError **)error {
    if (self.db) return YES;

    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/WeaponX/Data/iphone_model_db.json",
        @"/private/var/mobile/Library/WeaponX/Data/iphone_model_db.json"
    ];

    NSError *lastErr = nil;
    NSDictionary *root = nil;
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            root = PXLoadJSONDictionaryAtPath2(p, &lastErr);
            if (root) break;
        }
    }

    if (!root) {
        if (error) {
            *error = lastErr ?: [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"iphone_model_db.json not found"}];
        }
        PXDBLog(@"IPhoneModelDB: failed to load JSON (paths=%@) err=%@", paths, lastErr.localizedDescription ?: @"nil");
        return NO;
    }

    NSNumber *schema = root[@"schemaVersion"];
    if (![schema isKindOfClass:[NSNumber class]] || schema.integerValue != 1) {
        if (error) {
            *error = [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported schemaVersion"}];
        }
        PXDBLog(@"IPhoneModelDB: unsupported schemaVersion=%@", schema);
        return NO;
    }

    id modelsObj = root[@"models"];
    if (![modelsObj isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: @"Missing models array"}];
        }
        PXDBLog(@"IPhoneModelDB: missing models array (type=%@)", NSStringFromClass([modelsObj class]));
        return NO;
    }

    NSMutableArray<NSDictionary *> *models = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *byType = [NSMutableDictionary dictionary];
    NSUInteger total = 0;
    NSUInteger invalid = 0;
    for (id item in (NSArray *)modelsObj) {
        total += 1;
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *m = (NSDictionary *)item;
        NSString *pt = m[@"productType"];
        NSString *maxIOS = m[@"maxIOS"];
        if (![pt isKindOfClass:[NSString class]] || ![pt hasPrefix:@"iPhone"]) { invalid += 1; continue; }
        if (![maxIOS isKindOfClass:[NSString class]] || maxIOS.length == 0) { invalid += 1; continue; }
        [models addObject:m];
        if (!byType[pt]) {
            byType[pt] = m;
        }
    }

    if (models.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:5 userInfo:@{NSLocalizedDescriptionKey: @"No valid iPhone models in DB"}];
        }
        PXDBLog(@"IPhoneModelDB: no valid models (total=%lu invalid=%lu)", (unsigned long)total, (unsigned long)invalid);
        return NO;
    }

    if (invalid > 0) {
        PXDBLog(@"IPhoneModelDB: loaded models=%lu (skipped invalid=%lu)", (unsigned long)models.count, (unsigned long)invalid);
    }

    self.db = root;
    self.models = [models copy];
    self.byProductType = [byType copy];
    return YES;
}

- (NSDictionary *)randomModelMinIOS:(NSString *)minIOS error:(NSError **)error {
    if (![self loadIfNeeded:error]) return nil;
    if (minIOS.length == 0) minIOS = @"0.0";

    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (NSDictionary *m in self.models) {
        NSString *maxIOS = m[@"maxIOS"];
        if (![maxIOS isKindOfClass:[NSString class]]) continue;
        if (PXCompareVersions(maxIOS, minIOS) == NSOrderedAscending) continue;
        [candidates addObject:m];
    }

    if (candidates.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kIPhoneModelDBErrorDomain code:6 userInfo:@{NSLocalizedDescriptionKey: @"No models satisfy minIOS constraint"}];
        }
        PXDBLog(@"IPhoneModelDB: no candidates for minIOS=%@ (models=%lu)", minIOS, (unsigned long)self.models.count);
        return nil;
    }

    return candidates[PXRandomIndex2(candidates.count)];
}

- (NSDictionary *)specForProductType:(NSString *)productType {
    if (!productType.length) return nil;
    // Best-effort load.
    [self loadIfNeeded:nil];
    return self.byProductType[productType];
}

- (BOOL)containsProductType:(NSString *)productType {
    return [self specForProductType:productType] != nil;
}

@end
