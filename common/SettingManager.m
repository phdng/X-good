#import "SettingManager.h"

@implementation SettingManager
+ (instancetype)sharedManager {
    static SettingManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}


@end