#import <Foundation/Foundation.h>

@interface ActionManager : NSObject
+ (instancetype)sharedManager;

- (void) newPhone;
@end