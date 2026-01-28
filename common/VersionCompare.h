#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Compares semantic iOS-style versions (major.minor.patch).
/// Missing minor/patch components are treated as 0.
/// Returns NSOrderedAscending if a < b, etc.
FOUNDATION_EXPORT NSComparisonResult PXCompareVersions(NSString *a, NSString *b);

/// Returns YES if version is within [minVersion, maxVersion] (inclusive).
FOUNDATION_EXPORT BOOL PXVersionInRange(NSString *version, NSString *minVersion, NSString *maxVersion);

NS_ASSUME_NONNULL_END
