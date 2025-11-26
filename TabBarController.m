#import "TabBarController.h"
#import "ProjectXViewController.h"
#import "SecurityTabViewController.h"
#import <objc/runtime.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>

@interface TabBarController ()
// Add a property to hold the Account nav controller
// @property (nonatomic, strong) UINavigationController *accountNavController;
@property (nonatomic, strong) UILabel *networkStatusLabel;
@property (nonatomic, strong) NSMutableDictionary *tabVerificationStatus; // Track which tabs have been verified
@property (nonatomic, strong) NSMutableDictionary *tabLastVerificationTime; // Track when tabs were last verified
@property (nonatomic, assign) BOOL isIPad; // Property to track if device is iPad
@end

@implementation TabBarController

// Helper method to determine if the current device is an iPad
- (BOOL)isDeviceIPad {
    // Use both model check and user interface idiom for better detection
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set iPad flag
    self.isIPad = [self isDeviceIPad];
    NSLog(@"[WeaponX] Device detected: %@", self.isIPad ? @"iPad" : @"iPhone");
    
    // Initialize verification status tracking
    self.tabVerificationStatus = [NSMutableDictionary dictionaryWithDictionary:@{
        @"map_tab": @NO,
        @"security_tab": @NO
    }];
    
    // Initialize last verification time tracking
    self.tabLastVerificationTime = [NSMutableDictionary dictionary];
    
    // Don't automatically clear verification data on startup since this breaks offline functionality
    // Only clear verification if there's a specific need, like after login/logout or when the plan changes
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    
    // Store configurable grace period if not set
    if ([defaults doubleForKey:@"WeaponXOfflineGracePeriod"] <= 0) {
        // Default to 24 hours (in seconds)
        [defaults setDouble:(24 * 60 * 60) forKey:@"WeaponXOfflineGracePeriod"];
    }
    
    // Set delegate to self for tab change notifications
    self.delegate = self;
    
    // Register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(accountTabDidFinish:)
                                                name:@"accountTabDidFinish"
                                              object:nil];

    
    
    // Create view controllers
    ProjectXViewController *identityVC = [[ProjectXViewController alloc] init];
    SecurityTabViewController *securityVC = [[SecurityTabViewController alloc] init];

    // AccountViewController *accountVC = [[AccountViewController alloc] init];
    
    // Wrap each view controller in a navigation controller
    UINavigationController *identityNav = [[UINavigationController alloc] initWithRootViewController:identityVC];
    UINavigationController *securityNav = [[UINavigationController alloc] initWithRootViewController:securityVC];
    
    // Create account nav controller but don't add it to tab bar
    // self.accountNavController = [[UINavigationController alloc] initWithRootViewController:accountVC];
    
    // Configure tab bar items (excluding account)
    identityNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[UIImage systemImageNamed:@"house.fill"] tag:1];
    securityNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"shield.checkerboard"] tag:2];
    
    // Set view controllers (excluding account)
    self.viewControllers = @[identityNav, securityNav];
    
    // Set Home tab as default selected tab
    self.selectedIndex = 0;
    
    // Configure tab bar appearance
    self.tabBar.tintColor = [UIColor systemBlueColor];
    self.tabBar.backgroundColor = [UIColor systemBackgroundColor];
    
    // iPad-specific UI adjustments - don't use SplitViewController directly in tabs
    if (self.isIPad) {
        // For iPad, adjust tab bar size and appearance for better use of screen space
        self.tabBar.itemWidth = 120; // Give more space for tab items on iPad
        self.tabBar.itemPositioning = UITabBarItemPositioningCentered;
        
        // Add additional iPad-specific UI setup if needed
        NSLog(@"[WeaponX] Applied iPad-specific TabBar customizations");
    }
    
    
    
}



- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    
    // Post notification that this view controller did appear
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UIViewController_DidAppear" 
                                                        object:self 
                                                      userInfo:nil];
    
    // Verify authentication status whenever tab bar controller appears
    static BOOL firstAppearance = YES;
    
    // Only run this check once during the app launch sequence to avoid 
    // duplicate login screen presentations
    
    firstAppearance = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    // Determine which tab was selected
    NSInteger selectedIndex = tabBarController.selectedIndex;
    NSString *tabName = @"Unknown";
    
    // Get the appropriate tab name based on the selected index
    switch (selectedIndex) {
        case 0:
            tabName = @"Map Tab";
            break;
        case 1:
            tabName = @"Home Tab";
            break;
        case 2:
            tabName = @"Security Tab";
            break;
        case 3:
            tabName = @"Support Tab";
            break;
        default:
            tabName = [NSString stringWithFormat:@"Tab %ld", (long)selectedIndex];
            break;
    }
    
    NSLog(@"[WeaponX] 🔄 User switched to %@", tabName);
    
    // Post a notification about the tab change
    NSDictionary *userInfo = @{
        @"selectedIndex": @(selectedIndex),
        @"tabName": tabName,
        @"viewController": viewController
    };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TabBarSelectionChangedNotification" 
                                                        object:self 
                                                      userInfo:userInfo];
}



// Simple convenience method that calls the full implementation
- (void)showToastMessage:(NSString *)message success:(BOOL)success {
    [self showToastMessage:message withDuration:(success ? 3.0 : 2.0) isSuccess:success];
}

// Enhanced method to show a beautiful toast message
- (void)showToastMessage:(NSString *)message withDuration:(CGFloat)duration isSuccess:(BOOL)isSuccess {
    // Create container view for better styling
    UIView *toastContainer = [[UIView alloc] init];
    
    // Set background color based on success/failure
    if (isSuccess) {
        toastContainer.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:0.95];
    } else {
        toastContainer.backgroundColor = [UIColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:0.95];
    }
    
    toastContainer.layer.cornerRadius = 20;
    toastContainer.clipsToBounds = YES;
    toastContainer.alpha = 0.0;
    
    // Add drop shadow for better visibility
    toastContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    toastContainer.layer.shadowOffset = CGSizeMake(0, 4);
    toastContainer.layer.shadowOpacity = 0.3;
    toastContainer.layer.shadowRadius = 5;
    
    // Create icon view (checkmark for success, wifi.slash for error)
    UIImageView *iconView = [[UIImageView alloc] init];
    
    // Use SF Symbols if available (iOS 13+)
    if (@available(iOS 13.0, *)) {
        NSString *iconName = isSuccess ? @"checkmark.circle.fill" : @"wifi.slash";
        UIImage *icon = [UIImage systemImageNamed:iconName];
        iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        // Fallback for older iOS versions - use a simple circle view
        UIView *circleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        circleView.backgroundColor = [UIColor whiteColor];
        circleView.layer.cornerRadius = 12;
        [toastContainer addSubview:circleView];
    }
    
    iconView.tintColor = [UIColor whiteColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    
    // Create toast message label with improved typography
    UILabel *toastLabel = [[UILabel alloc] init];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.textAlignment = NSTextAlignmentLeft;
    toastLabel.text = message;
    
    // Use system font for better readability
    if (@available(iOS 13.0, *)) {
        toastLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    } else {
        toastLabel.font = [UIFont boldSystemFontOfSize:15];
    }
    
    // Get the key window
    UIWindow *window = nil;
    
    // Modern way (iOS 13+)
    if (@available(iOS 13.0, *)) {
        NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *candidateWindow in windowScene.windows) {
                    if (candidateWindow.isKeyWindow) {
                        window = candidateWindow;
                        break;
                    }
                }
                if (window) break;
            }
        }
        
        // Fallback to first window if no key window found
        if (!window && connectedScenes.count > 0) {
            UIScene *scene = [connectedScenes anyObject];
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.windows.count > 0) {
                    window = windowScene.windows.firstObject;
                }
            }
        }
    } else {
        // Older way (pre-iOS 13)
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        window = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    if (!window) {
        NSLog(@"[WeaponX] ⚠️ Cannot show toast - no window found");
        return;
    }
    
    // Add views to container
    [toastContainer addSubview:iconView];
    [toastContainer addSubview:toastLabel];
    [window addSubview:toastContainer];
    
    // Setup auto layout
    toastContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    toastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Layout constraints for container - position at top of screen with proper margins
    [NSLayoutConstraint activateConstraints:@[
        [toastContainer.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [toastContainer.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:20],
        [toastContainer.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor constant:-40],
        [toastContainer.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    
    // Layout constraints for icon - proper spacing and size
    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:toastContainer.leadingAnchor constant:15],
        [iconView.centerYAnchor constraintEqualToAnchor:toastContainer.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:24],
        [iconView.heightAnchor constraintEqualToConstant:24]
    ]];
    
    // Layout constraints for label - proper spacing and alignment
    [NSLayoutConstraint activateConstraints:@[
        [toastLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
        [toastLabel.trailingAnchor constraintEqualToAnchor:toastContainer.trailingAnchor constant:-15],
        [toastLabel.topAnchor constraintEqualToAnchor:toastContainer.topAnchor constant:12],
        [toastLabel.bottomAnchor constraintEqualToAnchor:toastContainer.bottomAnchor constant:-12]
    ]];
    
    // Use spring animation for a nicer effect
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        toastContainer.alpha = 1.0;
        
        // Add a slight pop effect
        toastContainer.transform = CGAffineTransformMakeScale(1.05, 1.05);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            toastContainer.transform = CGAffineTransformIdentity;
        }];
        
        // Hide after delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastContainer.alpha = 0.0;
                toastContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
            } completion:^(BOOL finished) {
                [toastContainer removeFromSuperview];
            }];
        });
    }];
}




// Add this method to update notification badges on refresh
- (void)updateNotificationBadges {
    [self updateNotificationBadge];
}

// Helper method to get the top-most view controller
- (UIViewController *)topMostViewController {
    UIViewController *topVC = self;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    // If it's a tab bar controller, get the selected view controller
    if ([topVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)topVC;
        topVC = tabController.selectedViewController;
    }
    
    // If it's a navigation controller, get the top view controller
    if ([topVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)topVC;
        topVC = navController.topViewController;
    }
    
    return topVC;
}




#pragma mark - System Methods




// Generate HMAC signature for string data with enhanced security
- (NSString *)hmacSignatureForString:(NSString *)string withDeviceInfo:(BOOL)includeDeviceInfo {
    // Use a mix of device identifiers as the secret key base
    NSMutableString *secretBase = [NSMutableString string];
    
    // Use the device's name (can't be easily spoofed)
    [secretBase appendString:[[UIDevice currentDevice] name]];
    
    // Add the device's identifierForVendor
    NSString *deviceUUID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (deviceUUID) {
        [secretBase appendString:deviceUUID];
    }
    
    // Add the device model identifier
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *deviceModel = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
    free(machine);
    
    if (deviceModel) {
        [secretBase appendString:deviceModel];
    }
    
    // Generate dynamic salt instead of hardcoded value
    NSMutableString *dynamicSalt = [NSMutableString string];
    
    // Part 1: Derive from bundle identifier
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID) {
        // Extract specific characters based on device identifiers to make it dynamic
        NSUInteger charIndex = MIN(3, bundleID.length - 1);
        if (deviceUUID) {
            // Use last character in UUID to determine which characters to use
            NSString *lastChar = [deviceUUID substringFromIndex:deviceUUID.length - 1];
            unsigned int value;
            [[NSScanner scannerWithString:lastChar] scanHexInt:&value];
            charIndex = value % MAX(1, bundleID.length);
        }
        [dynamicSalt appendString:[bundleID substringFromIndex:charIndex]];
    }
    
    // Part 2: Add device-specific entropy
    NSInteger entropy = (NSInteger)([[NSDate date] timeIntervalSince1970] / 86400); // Days since epoch
    if (deviceModel) {
        // Add device model length as another entropy source
        entropy += deviceModel.length;
    }
    [dynamicSalt appendFormat:@"%ld", (long)entropy];
    
    // Part 3: Add obscured app-specific salt
    // Obfuscate with character manipulation to prevent easy static extraction
    char obfuscatedSalt[] = {
        'W' ^ 0x7F, 'e' ^ 0x1A, 'a' ^ 0x3B, 'p' ^ 0x2C, 
        'o' ^ 0x5D, 'n' ^ 0x4E, 'X' ^ 0x6F, '_' ^ 0x0A,
        'S' ^ 0x17, 'a' ^ 0x3B, 'l' ^ 0x4C, 't' ^ 0x5F,
        '_' ^ 0x0A, 'v' ^ 0x7B, '3' ^ 0x1C
    };
    
    NSMutableString *deobfuscatedSalt = [NSMutableString string];
    for (int i = 0; i < sizeof(obfuscatedSalt)/sizeof(obfuscatedSalt[0]); i++) {
        // XOR back to get the original character
        char c = obfuscatedSalt[i] ^ (0x7F & (i + 0x1A));
        [deobfuscatedSalt appendFormat:@"%c", c];
    }
    
    [dynamicSalt appendString:deobfuscatedSalt];
    
    // Add the dynamic salt
    [secretBase appendString:dynamicSalt];
    
    // Add more device-specific information if requested
    if (includeDeviceInfo) {
        // Add iOS version
        [secretBase appendString:[[UIDevice currentDevice] systemVersion]];
        
        // Add app bundle identifier
        [secretBase appendString:[[NSBundle mainBundle] bundleIdentifier]];
        
        // Add installation date if available
        NSDate *installDate = [[NSFileManager defaultManager] attributesOfItemAtPath:
                               [[NSBundle mainBundle] bundlePath] error:nil][NSFileCreationDate];
        if (installDate) {
            [secretBase appendFormat:@"%.0f", [installDate timeIntervalSince1970]];
        }
    }
    
    // Additional anti-tampering mechanism - incorporate a hash of the hmac method itself
    NSString *methodName = NSStringFromSelector(_cmd);
    [secretBase appendString:methodName];
    
    // Convert the string to data using HMAC SHA256 algorithm
    const char *keyBytes = [secretBase UTF8String];
    const char *dataBytes = [string UTF8String];
    unsigned char hmacResult[CC_SHA256_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA256, 
           keyBytes, 
           strlen(keyBytes), 
           dataBytes, 
           strlen(dataBytes), 
           hmacResult);
    
    // Convert the result to a hex string
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(CC_SHA256_DIGEST_LENGTH * 2)];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hexString appendFormat:@"%02x", hmacResult[i]];
    }
    
    return hexString;
}





#pragma mark - NSURLSessionDelegate methods

// Handle authentication challenges (for certificate pinning)
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    // Certificate pinning for weaponx.us domain
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([challenge.protectionSpace.host containsString:@"weaponx.us"]) {
            // Get the server trust
            SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
            
            // Validate the host
            BOOL isValid = NO;
            
            // Use modern API for trust evaluation that's compatible with iOS 15+
            
            // Primary security check - verify certificate chain
            if (@available(iOS 13.0, *)) {
                CFErrorRef cfError = NULL;
                isValid = SecTrustEvaluateWithError(serverTrust, &cfError);
                if (!isValid && cfError) {
                    NSError *trustError = (__bridge_transfer NSError *)cfError;
                    NSLog(@"[WeaponX] ❌ Certificate trust evaluation failed: %@", trustError);
                }
            } else {
                // Fallback for older iOS versions if needed (but likely not used on iOS 15+)
                SecTrustResultType result;
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                SecTrustEvaluate(serverTrust, &result);
                #pragma clang diagnostic pop
                isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
            }
            
            // Additional security check - public key pinning
            if (isValid) {
                // Use modern API to get certificate data
                if (@available(iOS 15.0, *)) {
                    CFArrayRef certChain = SecTrustCopyCertificateChain(serverTrust);
                    if (certChain && CFArrayGetCount(certChain) > 0) {
                        SecCertificateRef certificate = (SecCertificateRef)CFArrayGetValueAtIndex(certChain, 0);
                        NSData *remoteCertificateData = CFBridgingRelease(SecCertificateCopyData(certificate));
                        
                        // Check if we need to initialize the trusted cert data
                        if (!self.trustedServerCertificateData) {
                            // On first run, we trust and store the certificate
                            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                            NSData *storedCertData = [defaults objectForKey:@"WeaponXTrustedCertificateData"];
                            
                            if (storedCertData) {
                                self.trustedServerCertificateData = storedCertData;
                            } else {
                                // First connection - trust this certificate and store it
                                self.trustedServerCertificateData = remoteCertificateData;
                                [defaults setObject:remoteCertificateData forKey:@"WeaponXTrustedCertificateData"];
                                [defaults synchronize];
                                
                                NSLog(@"[WeaponX] 🔒 Stored initial trusted certificate for future validation");
                            }
                        }
                        
                        // Validate against our trusted certificate data
                        isValid = [self.trustedServerCertificateData isEqualToData:remoteCertificateData];
                        CFRelease(certChain);
                    } else {
                        isValid = NO;
                    }
                } else {
                    // Fallback for older iOS versions
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
                    #pragma clang diagnostic pop
                    if (certificate) {
                        NSData *remoteCertificateData = CFBridgingRelease(SecCertificateCopyData(certificate));
                        
                        // Check stored certs as above
                        if (!self.trustedServerCertificateData) {
                            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                            NSData *storedCertData = [defaults objectForKey:@"WeaponXTrustedCertificateData"];
                            
                            if (storedCertData) {
                                self.trustedServerCertificateData = storedCertData;
                            } else {
                                self.trustedServerCertificateData = remoteCertificateData;
                                [defaults setObject:remoteCertificateData forKey:@"WeaponXTrustedCertificateData"];
                                [defaults synchronize];
                            }
                        }
                        
                        isValid = [self.trustedServerCertificateData isEqualToData:remoteCertificateData];
                    } else {
                        isValid = NO;
                    }
                }
            }
            
            if (isValid) {
                NSLog(@"[WeaponX] ✅ Certificate validation successful for server: %@", challenge.protectionSpace.host);
                NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
                completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
                return;
            } else {
                NSLog(@"[WeaponX] ❌ Certificate validation failed for server: %@", challenge.protectionSpace.host);
                completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
                return;
            }
        }
    }
    
    // Default handling for other cases
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

// Method to generate obfuscated keys dynamically
- (NSString *)generateObfuscatedKey:(NSString *)keyName {
    // Mix of device-specific data and runtime data
    NSMutableString *baseData = [NSMutableString string];
    
    // Add some device-specific data
    [baseData appendString:[[UIDevice currentDevice] systemVersion]];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID) {
        [baseData appendString:bundleID];
    }
    
    // Add bundle creation date (won't change after installation)
    NSDate *bundleCreationDate = [[NSFileManager defaultManager] attributesOfItemAtPath:
                               [[NSBundle mainBundle] bundlePath] error:nil][NSFileCreationDate];
    if (bundleCreationDate) {
        // Use just the date part, not time, for stability
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMdd"];
        [baseData appendString:[formatter stringFromDate:bundleCreationDate]];
    }
    
    // Create a synthetic identifier based on the app instance
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    if (bundlePath) {
        // Get characters based on length (more stable than the path itself)
        [baseData appendFormat:@"%lu", (unsigned long)bundlePath.length];
    }
    
    // Use the baseData to transform the keyName
    NSMutableString *result = [NSMutableString string];
    const char *keyChars = [keyName UTF8String];
    const char *baseChars = [baseData UTF8String];
    NSUInteger baseLen = [baseData length];
    
    for (int i = 0; i < strlen(keyChars); i++) {
        char c = keyChars[i];
        char baseChar = baseChars[i % baseLen];
        
        // Simple transformation - XOR with corresponding base char
        char transformed = c ^ (baseChar % 16);
        [result appendFormat:@"%02x", transformed];
    }
    
    return result;
}











@end