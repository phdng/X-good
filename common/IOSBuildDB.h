#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Loads iOS build metadata from external JSON and allows querying per device.
/// Schema (v1):
/// {
///   "schemaVersion": 1,
///   "buildToMeta": { "22F79": {"version": "18.5", "darwin": "24.5.0", "xnu": "...", "kernel_version": "..." }, ... },
///   "deviceToBuilds": { "iPhone16,2": ["22F79", ...], ... }
/// }
@interface IOSBuildDB : NSObject

+ (instancetype)sharedManager;

/// Loads the DB from disk if not loaded. Returns NO on error.
- (BOOL)loadIfNeeded:(NSError * _Nullable * _Nullable)error;

/// Returns a random build meta for the given device model, constrained by version range.
/// The returned dictionary includes the selected build under key "build".
- (NSDictionary * _Nullable)randomMetaForDevice:(NSString *)productType
                                            min:(NSString *)minVersion
                                            max:(NSString *)maxVersion
                                          error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
