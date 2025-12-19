#import "ActionManager.h"

@implementation ActionManager

+ (instancetype)sharedManager {
    static ActionManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}
- (instancetype) init{
    self = [super init];
    return self;
}
- (void) newPhone{


}
@end