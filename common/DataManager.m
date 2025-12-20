#import "DataManager.h"
#import "DaemonApiManager.h"

@interface DataManager()
@property (nonatomic, strong) PhoneInfo *phoneInfo;
@end

@implementation DataManager
+ (instancetype)sharedManager {
    static DataManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}
-(instancetype) init{
    [self freshCacheData];
    return self;
}
- (PhoneInfo *) getPhoneInfo{
    return _phoneInfo;
}
- (void) freshCacheData{
    _phoneInfo = [PhoneInfo loadFromPrefs];
}
@end