#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UptimeManager : NSObject

// Singleton accessor
+ (instancetype)sharedManager;

// System Uptime Generation (legacy)
- (NSTimeInterval)generateUptime;
- (NSTimeInterval)currentUptime;
- (void)setCurrentUptime:(NSTimeInterval)uptime;

// Boot Time Generation (legacy)
- (NSDate *)generateBootTime;
- (NSDate *)currentBootTime;
- (void)setCurrentBootTime:(NSDate *)bootTime;


// Data validation
- (BOOL)validateBootTimeConsistencyForProfile:(NSString *)profilePath;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end

NS_ASSUME_NONNULL_END 