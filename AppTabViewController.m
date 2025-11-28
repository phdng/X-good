#import "AppTabViewController.h"
#import "AppTabViewController.h"
#import "AppScopeManager.h"

@implementation AppTabViewController
- (void)loadPreferences
{
    NSMutableSet * scoped = [[AppScopeManager sharedManager] loadPreferences];
    if(!scoped){
        [super loadPreferences];
    }

}

- (void)savePreferences
{
    [[AppScopeManager sharedManager] savePreferences:_selectedApplications];
}

@end 
