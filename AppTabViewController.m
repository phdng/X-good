#import "AppTabViewController.h"
#import "AppTabViewController.h"
#import "AppScopeManager.h"

@implementation AppTabViewController
- (void)loadPreferences
{
    _selectedApplications= [[AppScopeManager sharedManager] loadPreferences];
    if(!_selectedApplications){
        [super loadPreferences];
    }

}

- (void)savePreferences
{
    [[AppScopeManager sharedManager] savePreferences:_selectedApplications];
}

@end 
