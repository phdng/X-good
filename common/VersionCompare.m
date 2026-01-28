#import "VersionCompare.h"

typedef struct {
    NSInteger major;
    NSInteger minor;
    NSInteger patch;
    BOOL valid;
} PXVersion;

static PXVersion PXParseVersion(NSString *s) {
    PXVersion v = {0, 0, 0, NO};
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return v;

    NSArray<NSString *> *parts = [s componentsSeparatedByString:@"."];
    if (parts.count == 0) return v;

    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSInteger nums[3] = {0, 0, 0};
    for (NSUInteger i = 0; i < 3; i++) {
        if (i >= parts.count) break;
        NSString *p = parts[i];
        if (p.length == 0) return v;
        // Ensure all digits (avoid accepting "15a" etc.)
        if ([p rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) {
            return v;
        }
        nums[i] = (NSInteger)p.integerValue;
    }

    v.major = nums[0];
    v.minor = nums[1];
    v.patch = nums[2];
    v.valid = YES;
    return v;
}

NSComparisonResult PXCompareVersions(NSString *a, NSString *b) {
    PXVersion va = PXParseVersion(a);
    PXVersion vb = PXParseVersion(b);
    if (!va.valid && !vb.valid) return NSOrderedSame;
    if (!va.valid) return NSOrderedAscending;
    if (!vb.valid) return NSOrderedDescending;

    if (va.major != vb.major) return (va.major < vb.major) ? NSOrderedAscending : NSOrderedDescending;
    if (va.minor != vb.minor) return (va.minor < vb.minor) ? NSOrderedAscending : NSOrderedDescending;
    if (va.patch != vb.patch) return (va.patch < vb.patch) ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

BOOL PXVersionInRange(NSString *version, NSString *minVersion, NSString *maxVersion) {
    if (PXCompareVersions(version, minVersion) == NSOrderedAscending) return NO;
    if (PXCompareVersions(version, maxVersion) == NSOrderedDescending) return NO;
    return YES;
}
