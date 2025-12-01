#import <UIKit/UIKit.h>
#import "ProjectX.h"
#import "TabBarController.h"
#import <UserNotifications/UserNotifications.h>


@interface AppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set notification delegate
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    
    TabBarController *tabBarController = [[TabBarController alloc] init];
    
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Set a flag to indicate the app is resuming from recents
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"WeaponXIsResuming"];
    [defaults synchronize];
    
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    
    
    // Reset the resuming flag after a delay to ensure it's used by all components
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [defaults setBool:NO forKey:@"WeaponXIsResuming"];
        [defaults synchronize];
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Use an atomic flag to prevent multiple concurrent auth checks
 
}

- (void)applicationWillTerminate:(UIApplication *)application {
    
    // Clean up notification center if needed
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}




// New method to directly detect the current screen/tab
- (void)detectAndUpdateCurrentScreen {
    static NSString *lastDetectedScreen = nil;
    static NSDate *lastDetectionTime = nil;
    
    // Add debouncing - don't update if the same screen was detected recently
    NSDate *now = [NSDate date];
    
    if (lastDetectedScreen && lastDetectionTime) {
        NSTimeInterval timeSinceLastDetection = [now timeIntervalSinceDate:lastDetectionTime];
        if (timeSinceLastDetection < 0.5) { // 500ms debounce time
            // Skip detection if it's too soon after the last one
            return;
        }
    }
    
    // Get the root view controller
    UIViewController *rootVC = self.window.rootViewController;
    NSString *screenName = @"Unknown";
    
    // Check for modally presented controllers first (like Account view)
    if (rootVC.presentedViewController) {
        // Check if it's a navigation controller with AccountViewController
        if ([rootVC.presentedViewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navController = (UINavigationController *)rootVC.presentedViewController;
            if ([navController.viewControllers.firstObject isKindOfClass:NSClassFromString(@"AccountViewController")]) {
                screenName = @"Account Tab (Modal)";
                
                // Check if it's the same as the last detected screen
                if (lastDetectedScreen && [lastDetectedScreen isEqualToString:screenName]) {
                    // Skip update if the screen hasn't changed
                    return;
                }
                
                // Store current detection info
                lastDetectedScreen = screenName;
                lastDetectionTime = now;
                
                [self updateCurrentScreen:screenName];
                return;
            }
        }
    }
    
    // Check if it's a tab bar controller
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootVC;
        NSInteger selectedIndex = tabBarController.selectedIndex;
        
        // Map tab indices to descriptive names
        switch (selectedIndex) {
            case 0:
                screenName = @"Map Tab";
                break;
            case 1:
                screenName = @"Home Tab";
                break;
            case 2:
                screenName = @"Security Tab";
                break;
            case 3:
                screenName = @"Account Tab";
                break;
            default:
                screenName = [NSString stringWithFormat:@"Tab %ld", (long)selectedIndex];
                break;
        }
    } else {
        // Not a tab bar controller, just use the class name
        screenName = NSStringFromClass([rootVC class]);
    }
    
    // Check if it's the same as the last detected screen
    if (lastDetectedScreen && [lastDetectedScreen isEqualToString:screenName]) {
        // Skip update if the screen hasn't changed
        return;
    }
    
    // Store current detection info
    lastDetectedScreen = screenName;
    lastDetectionTime = now;
    
    // Update the screen name
    [self updateCurrentScreen:screenName];
}

// Handle tab bar selection changes from notification
- (void)tabBarSelectionChanged:(NSNotification *)notification {
    static NSString *lastTabName = nil;
    static NSDate *lastTabChangeTime = nil;
    
    NSDate *now = [NSDate date];
    
    if (notification.userInfo) {
        NSString *tabName = notification.userInfo[@"tabName"];
        
        // Skip if the tab name is nil or the same as before within a short time window
        if (!tabName || (lastTabName && [lastTabName isEqualToString:tabName] && 
                         lastTabChangeTime && [now timeIntervalSinceDate:lastTabChangeTime] < 0.5)) {
            return;
        }
        
        // Update the tracking variables
        lastTabName = tabName;
        lastTabChangeTime = now;
        
        if (tabName) {
            [self updateCurrentScreen:tabName];
        }
    }
    
    // As a fallback, don't run our own detection immediately to avoid conflicts
    // Instead, schedule it after a slight delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectAndUpdateCurrentScreen];
    });
}

- (void)appDidBecomeActiveNotification:(NSNotification *)notification {
    // When app becomes active, detect the current screen
    [self detectAndUpdateCurrentScreen];
}

// Helper method to use APIManager's setCurrentScreen method if it exists
- (void)updateCurrentScreen:(NSString *)screenName {

}

// Helper method to get the top most view controller
- (UIViewController *)topViewController {
    // Modern approach for iOS 13+ to get the key window
    UIWindow *keyWindow = nil;
    
    // Get the connected scenes
    NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
    for (UIScene *scene in scenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && 
            [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }
    
    // Fallback for older iOS versions - without using deprecated APIs
    if (!keyWindow) {
        // Try to find any available window from connected scenes
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.windows.count > 0) {
                    keyWindow = windowScene.windows.firstObject;
                    break;
                }
            }
        }
        
        // Last resort for older iOS versions
        if (!keyWindow) {
            // Use a different approach that doesn't rely on deprecated APIs
            keyWindow = [[UIApplication sharedApplication] delegate].window;
        }
    }
    
    if (!keyWindow) {
        return nil;
    }
    
    UIViewController *rootViewController = keyWindow.rootViewController;
    return [self findTopViewControllerFromController:rootViewController];
}

- (UIViewController *)findTopViewControllerFromController:(UIViewController *)controller {
    if (controller.presentedViewController) {
        return [self findTopViewControllerFromController:controller.presentedViewController];
    } else if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)controller;
        return [self findTopViewControllerFromController:navigationController.visibleViewController];
    } else if ([controller isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)controller;
        return [self findTopViewControllerFromController:tabController.selectedViewController];
    } else {
        return controller;
    }
}


- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSLog(@"[WeaponX] Push notification received in background: %@", userInfo);
    
    // For background notification handling
    // This method is called when the app is in the background and a notification arrives
    
    // Process the notification data
    NSDictionary *aps = userInfo[@"aps"];
    NSString *notificationType = userInfo[@"type"];
    
    // Handle different notification types for background processing
    if (aps) {
        if ([notificationType isEqualToString:@"broadcast"]) {
            // Optionally pre-fetch broadcast data in the background
            NSNumber *broadcastId = userInfo[@"broadcast_id"];
            if (broadcastId) {
                NSLog(@"[WeaponX] Received broadcast notification in background for broadcast ID: %@", broadcastId);
                // Here you could pre-fetch the broadcast data
            }
        } else if ([notificationType isEqualToString:@"admin_reply"] || [notificationType isEqualToString:@"ticket_reply"]) {
            // Optionally pre-fetch ticket data in the background
            NSNumber *ticketId = userInfo[@"ticket_id"];
            if (ticketId) {
                NSLog(@"[WeaponX] Received ticket reply notification in background for ticket ID: %@", ticketId);
                // Here you could pre-fetch the ticket data
            }
        }
    }
    
    // Update badge count for the support tab
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateSupportTabBadge];
    });
    
    // Indicate that new data was fetched
    completionHandler(UIBackgroundFetchResultNewData);
}




- (void)updateSupportTabBadge {
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if ([tabBarController isKindOfClass:[TabBarController class]]) {
        [tabBarController updateNotificationBadge];
    }
}





- (NSString *)stringFromDeviceToken:(NSData *)deviceToken {
    NSUInteger length = deviceToken.length;
    if (length == 0) {
        return nil;
    }
    
    const unsigned char *buffer = deviceToken.bytes;
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(length * 2)];
    
    for (int i = 0; i < length; ++i) {
        [hexString appendFormat:@"%02x", buffer[i]];
    }
    
    return [hexString copy];
}



#pragma mark - UNUserNotificationCenterDelegate Methods

// Called when a notification is delivered to a foreground app
- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
       willPresentNotification:(UNNotification *)notification 
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    
    NSLog(@"[WeaponX] Notification received in foreground: %@", notification.request.content.userInfo);
    
    // Parse the notification content
    NSDictionary *userInfo = notification.request.content.userInfo;
    NSString *notificationType = userInfo[@"type"];
    
    // Update badge count for the support tab
    [self updateSupportTabBadge];

}

// Called to let your app know which action was selected by the user
- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
didReceiveNotificationResponse:(UNNotificationResponse *)response 
         withCompletionHandler:(void (^)(void))completionHandler {
    
    NSLog(@"[WeaponX] User responded to notification: %@", response.notification.request.content.userInfo);
    
    // Get the notification data
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSString *notificationType = userInfo[@"type"];
    

    
    // Call the completion handler when done
    completionHandler();
}


// Configure notification categories for actionable notifications
- (void)configureNotificationCategories {
    // Create actions for broadcast notifications
    UNNotificationAction *viewBroadcastAction = [UNNotificationAction actionWithIdentifier:@"VIEW_BROADCAST"
                                                                                     title:@"View"
                                                                                   options:UNNotificationActionOptionForeground];
    
    // Create broadcast category with actions
    UNNotificationCategory *broadcastCategory = [UNNotificationCategory categoryWithIdentifier:@"BROADCAST_CATEGORY"
                                                                                      actions:@[viewBroadcastAction]
                                                                            intentIdentifiers:@[]
                                                                                      options:UNNotificationCategoryOptionNone];
    
    // Create actions for ticket notifications
    UNNotificationAction *viewTicketAction = [UNNotificationAction actionWithIdentifier:@"VIEW_TICKET"
                                                                                  title:@"View"
                                                                                options:UNNotificationActionOptionForeground];
    
    // Create ticket category with actions
    UNNotificationCategory *ticketCategory = [UNNotificationCategory categoryWithIdentifier:@"TICKET_CATEGORY"
                                                                                    actions:@[viewTicketAction]
                                                                          intentIdentifiers:@[]
                                                                                    options:UNNotificationCategoryOptionNone];
    
    // Register the categories with the notification center
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center setNotificationCategories:[NSSet setWithObjects:broadcastCategory, ticketCategory, nil]];
}



@end

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    
    
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}