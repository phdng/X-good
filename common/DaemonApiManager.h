#import <Foundation/Foundation.h>

@interface DaemonApiManager:NSObject

+ (instancetype)sharedManager;

- (NSMutableSet *) getScopeApps;
- (void) saveScopeApps:(NSMutableSet *)apps;
@end