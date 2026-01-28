#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Loads iPhone model specifications from external JSON.
/// Schema (v1):
/// {
///   "schemaVersion": 1,
///   "models": [ {"productType": "iPhone8,1", "name": "iPhone 6s", "minIOS": "13.0", "maxIOS": "15.8.5", ...}, ... ]
/// }
@interface IPhoneModelDB : NSObject

+ (instancetype)sharedManager;

- (BOOL)loadIfNeeded:(NSError * _Nullable * _Nullable)error;

/// Returns a random model whose maxIOS >= minIOS (inclusive).
- (NSDictionary * _Nullable)randomModelMinIOS:(NSString *)minIOS error:(NSError * _Nullable * _Nullable)error;

/// Returns the model spec for the exact productType.
- (NSDictionary * _Nullable)specForProductType:(NSString *)productType;

/// Returns YES if a productType exists in the DB.
- (BOOL)containsProductType:(NSString *)productType;

@end

NS_ASSUME_NONNULL_END
