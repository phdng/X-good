#import <Foundation/Foundation.h>
#import "IdentifierManager.h"

#define IsScope() [[AppScopeManager sharedManager] isScope]

@interface AppScopeManager : NSObject
+ (instancetype)sharedManager;

- (BOOL) isScope;
- (NSMutableSet *)loadPreferences;
- (void)savePreferences:(NSMutableSet *)scopedApps;
@end 