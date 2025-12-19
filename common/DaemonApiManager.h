#import <Foundation/Foundation.h>
#import "PhoneInfo.h"

@interface DaemonApiManager:NSObject

+ (instancetype)sharedManager;

- (NSMutableSet *) getScopeApps;
- (void) saveScopeApps:(NSMutableSet *)apps;
- (PhoneInfo *) requestPhoneInfo;
- (BOOL) savePhoneInfo:(PhoneInfo *)phoneInfo;
@end