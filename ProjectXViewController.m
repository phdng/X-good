#import "ProjectX.h"
#import "IdentifierManager.h"
#import "UptimeManager.h"
#import "CopyHelper.h"
#import "BottomButtons.h"
#import "AppVersionManager.h"
#import "ProfileManager.h"
#import "StorageManager.h"
#import "BatteryManager.h"
#import <UIKit/UIKit.h>
#import "ProgressHUDView.h"
#import <spawn.h>
#import <sys/wait.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "AppScopeManager.h"
// Add missing methods via category
@interface LSApplicationWorkspace (ProjectX)
- (NSArray *)allInstalledApplications;
@end

// Add missing properties via category
@interface LSApplicationProxy (ProjectX)
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSString *buildVersionString;  // Add this line to get build number
@end

@interface ProjectXViewController () <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) ProgressHUDView *progressHUD;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;

@property (nonatomic, strong) NSMutableDictionary *identifierSwitches;
@property (nonatomic, strong) UITableView *appsTableView;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) UIButton *scrollToBottomButton;

// Trial offer banner properties
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// Method declarations
- (void)showError:(NSError *)error;
- (void)loadSettings;
- (void)setupUI;
- (void)addIdentifierSection:(NSString *)type title:(NSString *)title;
- (void)addAppManagementSection;
- (UIView *)createSectionHeaderWithTitle:(NSString *)title;
- (instancetype)init;
// Add this new method to directly update identifier values
- (void)directUpdateIdentifierValue:(NSString *)identifierType withValue:(NSString *)value;


// Helper methods for finding view controllers
- (UIViewController *)findTopViewController;
- (UITabBarController *)findTabBarController;

@property (nonatomic, strong) NSMutableArray *profiles;



// Add helper methods for finding buttons by tag
- (UIButton *)buttonWithTag:(NSInteger)tag;
- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view;

// Add property to track advanced identifiers visibility in the @interface section
@property (nonatomic, assign) BOOL showAdvancedIdentifiers;
@property (nonatomic, strong) UIButton *showAdvancedButton;
@property (nonatomic, strong) NSMutableArray *advancedIdentifierViews;

// Modify setupUI method to add a "Show Advanced" button and initially hide the advanced identifier sections
- (void)setupUI;

// Add a version of addIdentifierSection that adds to our tracking array and hides them initially
- (void)addAdvancedIdentifierSection:(NSString *)type title:(NSString *)title;

// Handle toggle of advanced identifiers
- (void)toggleAdvancedIdentifiers:(UIButton *)sender;
@end

@implementation ProjectXViewController

- (void)floatingScrollButtonTapped:(UIButton *)sender {
    CGFloat y = self.scrollView.contentOffset.y;
    CGFloat maxY = self.scrollView.contentSize.height - self.scrollView.bounds.size.height;
    if (maxY <= 0) return;
    if (y <= maxY * 0.20) {
        // Scroll to bottom
        CGFloat bottomOffset = self.scrollView.contentSize.height - self.scrollView.bounds.size.height + self.scrollView.contentInset.bottom;
        if (bottomOffset > 0) {
            [self.scrollView setContentOffset:CGPointMake(0, bottomOffset) animated:YES];
        }
    } else if (y >= maxY * 0.80) {
        // Scroll to top
        [self.scrollView setContentOffset:CGPointZero animated:YES];
    }
    // Hide the button after tap
    [UIView animateWithDuration:0.2 animations:^{
        self.scrollToBottomButton.alpha = 0.0;
    }];
}

// Show/hide scrollToBottomButton based on scroll position
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat y = scrollView.contentOffset.y;
    CGFloat maxY = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxY <= 0) {
        self.scrollToBottomButton.alpha = 0.0;
        return;
    }
    UIImage *downArrow = [[UIImage systemImageNamed:@"arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *upArrow = [[UIImage systemImageNamed:@"arrow.up"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (y <= maxY * 0.20) {
        // Top 20%: show button to scroll to bottom
        [self.scrollToBottomButton setImage:downArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to bottom";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else if (y >= maxY * 0.80) {
        // Bottom 20%: show button to scroll to top
        [self.scrollToBottomButton setImage:upArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to top";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 0.0;
        }];
    }
}

#pragma mark - Helper Methods

// Helper method to find top view controller without using keyWindow
- (UIViewController *)findTopViewController {
    UIViewController *rootVC = nil;
    
    // Get the key window using the modern approach for iOS 13+
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        rootVC = window.rootViewController;
                        break;
                    }
                }
                if (rootVC) break;
            }
        }
        
        // Fallback if we couldn't find the key window
        if (!rootVC) {
            UIWindowScene *windowScene = (UIWindowScene *)[connectedScenes anyObject];
            rootVC = windowScene.windows.firstObject.rootViewController;
        }
    } else {
        // Fallback for iOS 12 and below (though this is less likely to be used in iOS 15)
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    return rootVC;
}

- (UIViewController *)findTopViewControllerFromViewController:(UIViewController *)viewController {
    if (viewController.presentedViewController) {
        return [self findTopViewControllerFromViewController:viewController.presentedViewController];
    } else if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)viewController;
        return [self findTopViewControllerFromViewController:navigationController.topViewController];
    } else if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)viewController;
        return [self findTopViewControllerFromViewController:tabController.selectedViewController];
    } else {
        return viewController;
    }
}

- (UITabBarController *)findTabBarController {
    UIViewController *rootViewController = [self findTopViewController];
    
    // Check if root is a tab bar controller
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController;
    }
    
    // Check if root is a navigation controller with a tab bar controller
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)rootViewController;
        if ([navController.viewControllers.firstObject isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)navController.viewControllers.firstObject;
        }
    }
    
    // Check if tab bar controller is presented
    if ([rootViewController.presentedViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController.presentedViewController;
    }
    
    return nil;
}


#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add iPad-specific layout adaptations
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // Use regular width size class layout for iPad
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        
        // Create container view for iPad layout
        UIView *containerView = [[UIView alloc] init];
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:containerView];
        
        // Center container with max width for iPad
        [NSLayoutConstraint activateConstraints:@[
            [containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [containerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [containerView.widthAnchor constraintLessThanOrEqualToConstant:768], // iPad-appropriate max width
            [containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
            [containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
            [containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20]
        ]];
        
        // Move existing content to container
        for (UIView *subview in self.view.subviews) {
            if (subview != containerView) {
                [containerView addSubview:subview];
            }
        }
    }
    
    self.title = @"Project X";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    
    if (@available(iOS 15.0, *)) {
        // Modern button style for iOS 15+
        UIButtonConfiguration *filesConfig = [UIButtonConfiguration plainButtonConfiguration];
        filesConfig.title = @"Files";
        filesConfig.image = [UIImage systemImageNamed:@"arrow.down.circle"];
        filesConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        filesConfig.imagePadding = 4;
        filesConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        filesConfig.baseForegroundColor = [UIColor systemBlueColor];
    } else {
        // Fallback for iOS 14 and below without using deprecated properties
        // Create a container view to hold the image and text
        UIView *buttonContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
        
        // Add icon image view
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]];
        iconImageView.tintColor = [UIColor systemBlueColor];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [buttonContentView addSubview:iconImageView];
        
        // Add text label
        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.text = @"Files";
        textLabel.font = [UIFont systemFontOfSize:16];
        textLabel.textColor = [UIColor systemBlueColor];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [buttonContentView addSubview:textLabel];
        
        // Set up constraints
        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.leadingAnchor constraintEqualToAnchor:buttonContentView.leadingAnchor],
            [iconImageView.centerYAnchor constraintEqualToAnchor:buttonContentView.centerYAnchor],
            [iconImageView.widthAnchor constraintEqualToConstant:20],
            [iconImageView.heightAnchor constraintEqualToConstant:20],
            
            [textLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor constant:4],
            [textLabel.trailingAnchor constraintEqualToAnchor:buttonContentView.trailingAnchor],
            [textLabel.centerYAnchor constraintEqualToAnchor:buttonContentView.centerYAnchor]
        ]];
        

    }
        
    
    // Initialize managers
    self.manager = [IdentifierManager sharedManager];
    self.identifierSwitches = [NSMutableDictionary dictionary];
    
    // Add tap gesture recognizer to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    // Add long press gesture to show debug info for trial banner
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showTrialBannerDebugInfo:)];
    longPressGesture.minimumPressDuration = 2.0; // 2 seconds
    [self.view addGestureRecognizer:longPressGesture];
    
    // Register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    
    // Register for profile changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(handleProfileChanged:)
                                                name:@"com.hydra.projectx.profileChanged"
                                              object:nil];
    
    [self setupUI];
    [self loadSettings];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ... existing code ...
    
    // Check if we should refresh the trial offer banner
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

#pragma mark - UI Setup

- (void)setupUI {
    // Setup scroll view with refresh control
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    
    // Hide vertical scroll indicator (removes the scrollbar line when scrolling)
    self.scrollView.showsVerticalScrollIndicator = NO;
    
    // Set delegate to self to implement scroll restriction
    self.scrollView.delegate = self;
    
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.scrollView.refreshControl = refreshControl;
    [self.view addSubview:self.scrollView];
    
    // Setup main stack view with improved spacing
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 24;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.layoutMargins = UIEdgeInsetsMake(0, 0, 100, 0);
    self.mainStackView.layoutMarginsRelativeArrangement = YES;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // Initialize the advanced identifiers tracking array and flag
    self.advancedIdentifierViews = [NSMutableArray array];
    self.showAdvancedIdentifiers = NO;
    
    // Setup constraints with safe area
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];
    
    
    // Create header stack view for title and generate button
    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.spacing = 8;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.distribution = UIStackViewDistributionEqualSpacing;
    
    

    // Add Generate All button with minimalistic style
    UIButton *generateAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *generateAllConfig = [UIButtonConfiguration plainButtonConfiguration];
    generateAllConfig.title = @"刷新所有参数";
    generateAllConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    generateAllConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
    generateAllConfig.baseForegroundColor = [UIColor systemBlueColor];
    generateAllConfig.contentInsets = NSDirectionalEdgeInsetsMake(2, 4, 2, 4);
    
    // Create a smaller icon that matches the text size
    UIImage *smallIcon = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10]];
    generateAllConfig.image = smallIcon;
    
    generateAllConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    generateAllConfig.imagePadding = 2;
    generateAllButton.configuration = generateAllConfig;
    generateAllButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    generateAllButton.layer.cornerRadius = 8;
    generateAllButton.clipsToBounds = YES;
    [generateAllButton addTarget:self action:@selector(generateAllButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [headerStack addArrangedSubview:generateAllButton];
    
    [self.mainStackView addArrangedSubview:headerStack];
    
    // Add basic identifier sections
    [self addIdentifierSection:@"IDFA" title:@"IDFA"];
    [self addIdentifierSection:@"IDFV" title:@"IDFV"];
    [self addIdentifierSection:@"DeviceName" title:@"设备名"];
    [self addIdentifierSection:@"IOSVersion" title:@"版本号"];
    [self addIdentifierSection:@"WiFi" title:@"WiFi信息"];
    [self addIdentifierSection:@"StorageSystem" title:@"存储信息"];
    [self addIdentifierSection:@"Battery" title:@"电池信息"];
    
    // Add basic UUID sections - moved System Uptime and Boot Time from advanced to basic
    [self addIdentifierSection:@"SystemUptime" title:@"开机时长"];
    [self addIdentifierSection:@"BootTime" title:@"启动时间"];
    
    
    // Add advanced identifier sections (will be initially hidden)
    [self addIdentifierSection:@"KeychainUUID" title:@"Keychain UUID"];
    [self addIdentifierSection:@"UserDefaultsUUID" title:@"UserDefaults UUID"];
    [self addIdentifierSection:@"AppGroupUUID" title:@"App Group UUID"];
    [self addIdentifierSection:@"CoreDataUUID" title:@"Core Data UUID"];
    [self addIdentifierSection:@"AppInstallUUID" title:@"App Install UUID"];
    [self addIdentifierSection:@"AppContainerUUID" title:@"App Container UUID"];
    // Moved Serial Number and Pasteboard UUID from basic to advanced
    [self addIdentifierSection:@"SerialNumber" title:@"Serial Number"];
    [self addIdentifierSection:@"PasteboardUUID" title:@"Pasteboard UUID"];
    // Moved System Boot UUID and Dyld Cache UUID from basic to advanced
    [self addIdentifierSection:@"SystemBootUUID" title:@"System Boot UUID"];
    [self addIdentifierSection:@"DyldCacheUUID" title:@"Dyld Cache UUID"];
        
    
    // Add bottom buttons view
    UIView *bottomButtonsView = [[BottomButtons sharedInstance] createBottomButtonsView];
    [self.view addSubview:bottomButtonsView];
    
    // Setup constraints for bottom buttons view
    [NSLayoutConstraint activateConstraints:@[
        [bottomButtonsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomButtonsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    
}

#pragma mark - Settings Management

- (void)loadSettings {
    // Load identifier states
    UISwitch *idfaSwitch = self.identifierSwitches[@"IDFA"];
    UISwitch *idfvSwitch = self.identifierSwitches[@"IDFV"];
    
    if (idfaSwitch) {
        idfaSwitch.on = [self.manager isIdentifierEnabled:@"IDFA"];
    }
    
    if (idfvSwitch) {
        idfvSwitch.on = [self.manager isIdentifierEnabled:@"IDFV"];
    }
    
}

#pragma mark - Error Handling

- (void)showError:(NSError *)error {
    if (!error) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                 message:error.localizedDescription
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Keyboard Handling

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardFrame.size.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - UI Components

- (void)addIdentifierSection:(NSString *)type title:(NSString *)title {
    // Create section title
    NSArray *shippingboxTypes = @[ @"KeychainUUID", @"UserDefaultsUUID", @"AppGroupUUID", @"CoreDataUUID", @"AppInstallUUID", @"AppContainerUUID" ];
    if (@available(iOS 15.0, *)) {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        
        // Determine which icon to use based on type
        NSString *iconName = [shippingboxTypes containsObject:type] ? @"shippingbox" : @"pencil";
        UIImage *iconImage = [UIImage systemImageNamed:iconName];
        
        if (iconImage) {
            // Tint the icon to match text
            iconImage = [iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            NSTextAttachment *iconAttachment = [[NSTextAttachment alloc] init];
            iconAttachment.image = iconImage;
            CGFloat iconSize = 18;
            iconAttachment.bounds = CGRectMake(0, -3, iconSize, iconSize);
            
            NSAttributedString *space = [[NSAttributedString alloc] initWithString:@"  "];
            NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:title attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightBold],
                NSForegroundColorAttributeName: [UIColor labelColor]
            }];
            
            NSMutableAttributedString *full = [[NSMutableAttributedString alloc] initWithAttributedString:titleString];
            [full appendAttributedString:space];
            [full appendAttributedString:[NSAttributedString attributedStringWithAttachment:iconAttachment]];
            titleLabel.attributedText = full;
            titleLabel.tintColor = [UIColor labelColor];
            
            // Add tap gesture for the label to show edit dialog
            UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(titleIconTapped:)];
            titleLabel.userInteractionEnabled = YES;
            [titleLabel addGestureRecognizer:titleTap];
            objc_setAssociatedObject(titleTap, "identifierType", type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // Unicode fallback
            titleLabel.text = [NSString stringWithFormat:@"%@ \U0001F4E6", title];
        }
        [self.mainStackView addArrangedSubview:titleLabel];
    } else {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        [self.mainStackView addArrangedSubview:titleLabel];
    }
    
    // Reduce spacing between title and container by 50%
    UIView *lastTitleView = nil;
    if (@available(iOS 15.0, *)) {
        if ([shippingboxTypes containsObject:type]) {
            lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleStack
        } else {
            lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleLabel
        }
    } else {
        lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleLabel
    }
    if (lastTitleView) {
        [self.mainStackView setCustomSpacing:4 afterView:lastTitleView];
    }
    
    // Create container view with glassmorphism effect
    UIView *containerView = [[UIView alloc] init];
    
    // Set up glassmorphism effect - works in both light and dark mode
    containerView.backgroundColor = [UIColor clearColor];
    
    // Create blur effect - adapts to light/dark mode automatically
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:blurView];
    
    // Add vibrancy effect for content
    UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
    UIVisualEffectView *vibrancyView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
    vibrancyView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Setup blur view constraints to fill container
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Add subtle border
    containerView.layer.borderWidth = 0.5;
    containerView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.2].CGColor;
    containerView.layer.cornerRadius = 20;
    containerView.clipsToBounds = YES;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow
    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOffset = CGSizeMake(0, 4);
    containerView.layer.shadowRadius = 8;
    containerView.layer.shadowOpacity = 0.1;
    
    // Create vertical stack for identifier and controls
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10;
    contentStack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    contentStack.layoutMarginsRelativeArrangement = YES;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:contentStack];
    
    // Setup content stack constraints
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Create identifier container with background
    UIView *identifierContainer = [[UIView alloc] init];
    identifierContainer.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.1];
    identifierContainer.layer.cornerRadius = 12;
    identifierContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create identifier label
    UILabel *identifierLabel = [[UILabel alloc] init];
    NSString *currentValue = [self.manager currentValueForIdentifier:type];
    identifierLabel.text = currentValue ?: @"Not Set";
    identifierLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
    identifierLabel.textColor = [UIColor labelColor];
    identifierLabel.numberOfLines = 1;
    identifierLabel.adjustsFontSizeToFitWidth = YES;
    identifierLabel.minimumScaleFactor = 0.5;
    identifierLabel.textAlignment = NSTextAlignmentCenter;
    identifierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add padding to identifier label
    [identifierContainer addSubview:identifierLabel];
    [NSLayoutConstraint activateConstraints:@[
        [identifierLabel.topAnchor constraintEqualToAnchor:identifierContainer.topAnchor constant:12],
        [identifierLabel.leadingAnchor constraintEqualToAnchor:identifierContainer.leadingAnchor constant:12],
        [identifierLabel.trailingAnchor constraintEqualToAnchor:identifierContainer.trailingAnchor constant:-12],
        [identifierLabel.bottomAnchor constraintEqualToAnchor:identifierContainer.bottomAnchor constant:-12]
    ]];
    
    [contentStack addArrangedSubview:identifierContainer];
    
    // Create horizontal stack for controls
    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionEqualSpacing;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    
    // Create copy button with enhanced style
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *copyConfig = [UIButtonConfiguration plainButtonConfiguration];
    copyConfig.image = [UIImage systemImageNamed:@"doc.on.doc"];
    copyConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    copyConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    copyConfig.baseForegroundColor = [UIColor systemBlueColor];
    copyConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
    copyButton.configuration = copyConfig;
    
    copyButton.tag = [self tagForIdentifierType:type];
    copyButton.accessibilityValue = currentValue;
    [copyButton addTarget:self action:@selector(copyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Create switch and status container
    UIStackView *switchStatusStack = [[UIStackView alloc] init];
    switchStatusStack.axis = UILayoutConstraintAxisHorizontal;
    switchStatusStack.spacing = 8;
    switchStatusStack.alignment = UIStackViewAlignmentCenter;
    
    // Create status label
    UILabel *stateLabel = [[UILabel alloc] init];
    stateLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    stateLabel.textColor = [UIColor labelColor];
    stateLabel.text = [self.manager isIdentifierEnabled:type] ? @"Enabled" : @"Disabled";
    stateLabel.tag = 100; // Tag to find this label later
    
    // Create switch with modern style
    UISwitch *identifierSwitch = [[UISwitch alloc] init];
    [identifierSwitch setOn:[self.manager isIdentifierEnabled:type] animated:NO];
    identifierSwitch.onTintColor = [UIColor systemBlueColor];
    [identifierSwitch addTarget:self action:@selector(identifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    identifierSwitch.tag = [self tagForIdentifierType:type];
    
    [switchStatusStack addArrangedSubview:stateLabel];
    [switchStatusStack addArrangedSubview:identifierSwitch];
    
    // Create generate button with minimalistic style
    UIButton *generateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *generateConfig = [UIButtonConfiguration plainButtonConfiguration];
    generateConfig.image = [UIImage systemImageNamed:@"arrow.clockwise"];
    generateConfig.title = @"刷新参数";
    generateConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    generateConfig.imagePadding = 4;
    generateConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    generateConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
    generateConfig.baseForegroundColor = [UIColor systemBlueColor];
    generateConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 6, 4, 6);
    generateButton.configuration = generateConfig;
    generateButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    generateButton.layer.cornerRadius = 10;
    generateButton.clipsToBounds = YES;
    
    generateButton.tag = [self tagForIdentifierType:type];
    [generateButton addTarget:self action:@selector(generateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add all elements to controls stack
    [controlsStack addArrangedSubview:copyButton];
    [controlsStack addArrangedSubview:switchStatusStack];
    [controlsStack addArrangedSubview:generateButton];
    
    // Add controls stack to content stack
    [contentStack addArrangedSubview:controlsStack];
    
    // Add container to main stack
    [self.mainStackView addArrangedSubview:containerView];
    
    // Add spacing after the container - reduce by 50% from default spacing
    [self.mainStackView setCustomSpacing:12 afterView:containerView]; // 50% of the default 24 spacing
    
    // Store switch reference
    if (!self.identifierSwitches) {
        self.identifierSwitches = [NSMutableDictionary dictionary];
    }
    self.identifierSwitches[type] = identifierSwitch;
}


- (UIView *)createSectionHeaderWithTitle:(NSString *)title {
    UIView *headerView = [[UIView alloc] init];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:titleLabel];
    
    UIView *separatorView = [[UIView alloc] init];
    separatorView.backgroundColor = [UIColor separatorColor];
    separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:separatorView];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        
        [separatorView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [separatorView.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [separatorView.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        [separatorView.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor],
        [separatorView.heightAnchor constraintEqualToConstant:1]
    ]];
    
    return headerView;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Get the new text that would result from this change
    NSString *newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    // Limit text field to 50 characters (increased from 26)
    if (newText.length > 50) {
        return NO;
    }
    
    // Only allow alphanumeric characters, dots, and hyphens
    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:string];
    return [allowedCharacters isSupersetOfSet:characterSet] || [string isEqualToString:@""];
}



#pragma mark - Switch Actions


- (void)refreshData {
    [self loadSettings];
    [self.scrollView.refreshControl endRefreshing];
}

- (void)generateButtonTapped:(UIButton *)sender {
    // Check if user has an active plan
    BOOL isRestricted = [[NSUserDefaults standardUserDefaults] boolForKey:@"WeaponXRestrictedAccess"];
    
    // Also check associated object as a backup
    if (!isRestricted) {
        UIViewController *topVC = [self findTopViewController];
        NSNumber *restrictedAccess = objc_getAssociatedObject(topVC, "WeaponXRestrictedAccess");
        isRestricted = restrictedAccess ? [restrictedAccess boolValue] : NO;
    }
    
    // Determine which identifier type based on the button's tag
    NSString *identifierType;
    if (sender.tag == 1) {
        identifierType = @"IDFA";
    } else if (sender.tag == 2) {
        identifierType = @"IDFV";
    } else if (sender.tag == 3) {
        identifierType = @"DeviceName";
    } else if (sender.tag == 4) {
        identifierType = @"SerialNumber";
    } else if (sender.tag == 5) {
        identifierType = @"IOSVersion";
    } else if (sender.tag == 6) {
        identifierType = @"WiFi";
    } else if (sender.tag == 7) {
        identifierType = @"StorageSystem";
    } else if (sender.tag == 8) {
        identifierType = @"Battery";
    } else if (sender.tag == 9) {
        identifierType = @"SystemBootUUID";
    } else if (sender.tag == 10) {
        identifierType = @"DyldCacheUUID";
    } else if (sender.tag == 11) {
        identifierType = @"PasteboardUUID";
    } else if (sender.tag == 12) {
        identifierType = @"KeychainUUID";
    } else if (sender.tag == 13) {
        identifierType = @"UserDefaultsUUID";
    } else if (sender.tag == 14) {
        identifierType = @"AppGroupUUID";
    } else if (sender.tag == 15) {
        identifierType = @"SystemUptime";
    } else if (sender.tag == 16) {
        identifierType = @"BootTime";
    } else if (sender.tag == 17) {
        identifierType = @"CoreDataUUID";
    } else if (sender.tag == 18) {
        identifierType = @"AppInstallUUID";
    } else if (sender.tag == 19) {
        identifierType = @"AppContainerUUID";
    } else {
        return;
    }
    
    // Disable button temporarily
    sender.enabled = NO;
    
    // Show loading state
    UIColor *originalColor = sender.tintColor;
    [sender setTitle:@"Generating..." forState:UIControlStateNormal];
    [sender setTintColor:[UIColor systemGrayColor]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Generate only the specific identifier that was tapped
        NSString *newValue = nil;
        if ([identifierType isEqualToString:@"IDFA"]) {
            newValue = [self.manager generateIDFA];
        } else if ([identifierType isEqualToString:@"IDFV"]) {
            newValue = [self.manager generateIDFV];
        } else if ([identifierType isEqualToString:@"DeviceName"]) {
            newValue = [self.manager generateDeviceName];
        } else if ([identifierType isEqualToString:@"SerialNumber"]) {
            newValue = [self.manager generateSerialNumber];
        } else if ([identifierType isEqualToString:@"IOSVersion"]) {
            // Generate iOS Version and then get the string representation
            [self.manager generateIOSVersion];
            newValue = [self.manager currentValueForIdentifier:@"IOSVersion"];
        } else if ([identifierType isEqualToString:@"WiFi"]) {
            newValue = [self.manager generateWiFiInformation];
        } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
            newValue = [self.manager generateSystemBootUUID];
        } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
            newValue = [self.manager generateDyldCacheUUID];
        } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
            newValue = [self.manager generatePasteboardUUID];
        } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
            newValue = [self.manager generateKeychainUUID];
        } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
            newValue = [self.manager generateUserDefaultsUUID];
        } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
            newValue = [self.manager generateAppGroupUUID];
        } else if ([identifierType isEqualToString:@"StorageSystem"]) {
            // Get StorageManager class
            Class storageManagerClass = NSClassFromString(@"StorageManager");
            if (storageManagerClass && [storageManagerClass respondsToSelector:@selector(sharedManager)]) {
                id storageManager = [storageManagerClass sharedManager];
                if (storageManager) {
                    // Generate a random storage capacity (either 64GB or 128GB)
                    NSString *capacity = [storageManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                       [storageManager randomizeStorageCapacity] : @"64";
                    
                    // Generate the storage information based on the capacity
                    if ([storageManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                        NSDictionary *storageInfo = [storageManager generateStorageForCapacity:capacity];
                        if (storageInfo) {
                            // Update the StorageManager with the generated values
                            [storageManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                            [storageManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                            [storageManager setFilesystemType:storageInfo[@"FilesystemType"]];
                            
                            // Format the value for display
                            newValue = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                      storageInfo[@"TotalStorage"], 
                                      storageInfo[@"FreeStorage"]];
                        }
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                BOOL use128GB = (arc4random_uniform(100) < 60);
                newValue = use128GB ? @"Total: 128 GB, Free: 38.4 GB" : @"Total: 64 GB, Free: 19.8 GB";
            }
        } else if ([identifierType isEqualToString:@"Battery"]) {
            // Get BatteryManager class
            Class batteryManagerClass = NSClassFromString(@"BatteryManager");
            if (batteryManagerClass && [batteryManagerClass respondsToSelector:@selector(sharedManager)]) {
                id batteryManager = [batteryManagerClass sharedManager];
                if (batteryManager && [batteryManager respondsToSelector:@selector(generateBatteryInfo)]) {
                    NSDictionary *batteryInfo = [batteryManager generateBatteryInfo];
                    if (batteryInfo) {
                        // Update display value - just show battery percentage now
                        NSString *level = batteryInfo[@"BatteryLevel"];
                        float levelFloat = [level floatValue];
                        int percentage = (int)(levelFloat * 100);
                        
                        newValue = [NSString stringWithFormat:@"%d%%", percentage];
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                int randomPercentage = 20 + arc4random_uniform(81); // 20-100%
                newValue = [NSString stringWithFormat:@"%d%%", randomPercentage];
            }
        } else if ([identifierType isEqualToString:@"SystemUptime"]) {
            newValue = [self.manager generateSystemUptime];
        } else if ([identifierType isEqualToString:@"BootTime"]) {
            newValue = [self.manager generateBootTime];
        } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
            newValue = [self.manager generateCoreDataUUID];
        } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
            newValue = [self.manager generateAppInstallUUID];
        } else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
            newValue = [self.manager generateAppContainerUUID];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Re-enable button
            sender.enabled = YES;
            [sender setTitle:@"刷新参数" forState:UIControlStateNormal];
            [sender setTintColor:originalColor];
            
            if ([self.manager lastError]) {
                [self showError:[self.manager lastError]];
                return;
            }
            
            // Save settings after generating new value
            [self.manager saveSettings];
            
            // Use our direct update method for immediate UI update
            [self directUpdateIdentifierValue:identifierType withValue:newValue];
            
            // Enable this identifier's switch if it's not already enabled
            UISwitch *identifierSwitch = self.identifierSwitches[identifierType];
            if (identifierSwitch && !identifierSwitch.isOn) {
                identifierSwitch.on = YES;
                [self.manager setIdentifierEnabled:YES forType:identifierType];
                [self.manager saveSettings];
                
                // Update the status label
                UIStackView *switchStatusStack = (UIStackView *)identifierSwitch.superview;
                if ([switchStatusStack isKindOfClass:[UIStackView class]]) {
                    UILabel *stateLabel = [switchStatusStack.arrangedSubviews filteredArrayUsingPredicate:
                        [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                            return [object isKindOfClass:[UILabel class]] && ((UILabel *)object).tag == 100;
                        }]].firstObject;
                    
                    if (stateLabel) {
                        stateLabel.text = @"Enabled";
                    }
                }
            }
            
            // Show success feedback
            [sender setTintColor:[UIColor systemGreenColor]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    [sender setTintColor:originalColor];
                }];
            });
        });
    });
}

- (void)updateValueLabel:(NSString *)identifierType withValue:(NSString *)value {
    // Find the container view for this specific identifier type
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Skip non-container views (like labels and spacers)
        if (![view isKindOfClass:[UIView class]] || 
            ![view.subviews.firstObject isKindOfClass:[UIVisualEffectView class]]) {
            continue;
        }
        
        // Get the content stack view
        UIStackView *contentStack = nil;
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIStackView class]]) {
                contentStack = (UIStackView *)subview;
                break;
            }
        }
        
        if (!contentStack) continue;
        
        // Get the controls stack to find which identifier this is
        if (contentStack.arrangedSubviews.count < 2) continue;
        
        UIStackView *controlsStack = contentStack.arrangedSubviews.lastObject;
        if (![controlsStack isKindOfClass:[UIStackView class]]) continue;
        
        // Find the generate button to check its tag
        UIButton *generateButton = nil;
        for (UIView *control in controlsStack.arrangedSubviews) {
            if ([control isKindOfClass:[UIButton class]] && 
                [[(UIButton *)control currentTitle] isEqualToString:@"刷新参数"]) {
                generateButton = (UIButton *)control;
                break;
            }
        }
        
        if (!generateButton) continue;
        
        // Check if this is the container we want based on the tag
        BOOL isTargetContainer = (generateButton.tag == [self tagForIdentifierType:identifierType]);
        
        if (isTargetContainer) {
            // Get the identifier container
            if (contentStack.arrangedSubviews.count < 1) continue;
            
            UIView *identifierContainer = contentStack.arrangedSubviews.firstObject;
            if (![identifierContainer isKindOfClass:[UIView class]]) continue;
            
            // Get the identifier label
            UILabel *identifierLabel = nil;
            for (UIView *subview in identifierContainer.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    identifierLabel = (UILabel *)subview;
                    break;
                }
            }
            
            if (!identifierLabel) continue;
            
            // Update the label text with animation
            [UIView transitionWithView:identifierLabel
                              duration:0.3
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                identifierLabel.text = value ?: @"Not Set";
                            }
                            completion:nil];
            
            // Also update the copy button's accessibility value
            UIButton *copyButton = controlsStack.arrangedSubviews.firstObject;
            if ([copyButton isKindOfClass:[UIButton class]]) {
                copyButton.accessibilityValue = value;
            }
            
            // Found and updated the target container, no need to continue
            break;
        }
    }
}

- (void)copyButtonTapped:(UIButton *)sender {
    NSString *value = sender.accessibilityValue;
    if (value && ![value isEqualToString:@"Not Set"]) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:value];
        
        // Enhanced visual feedback for copy action
        UIColor *originalColor = sender.tintColor;
        
        // Create a checkmark configuration for success feedback
        UIButtonConfiguration *originalConfig = sender.configuration;
        UIButtonConfiguration *successConfig = [originalConfig copy];
        successConfig.image = [UIImage systemImageNamed:@"checkmark"];
        successConfig.baseForegroundColor = [UIColor systemGreenColor];
        
        // Animate the change
        [UIView animateWithDuration:0.2 animations:^{
            sender.configuration = successConfig;
        } completion:^(BOOL finished) {
            // Show success state for a moment
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Animate back to original state
                [UIView animateWithDuration:0.2 animations:^{
                    UIButtonConfiguration *revertConfig = [originalConfig copy];
                    revertConfig.baseForegroundColor = originalColor;
                    sender.configuration = revertConfig;
                }];
            });
        }];
    }
}


- (void)directUpdateIdentifierValue:(NSString *)identifierType withValue:(NSString *)value {
    // Find all identifier cells
    BOOL foundContainer = NO;
    
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Skip if not a view or doesn't have subviews
        if (![view isKindOfClass:[UIView class]] || view.subviews.count == 0) {
            continue;
        }
        
        // Find the content stack view
        UIStackView *contentStack = nil;
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIStackView class]]) {
                contentStack = (UIStackView *)subview;
                break;
            }
        }
        
        if (!contentStack || contentStack.arrangedSubviews.count < 2) {
            continue;
        }
        
        // Get the controls stack
        UIStackView *controlsStack = contentStack.arrangedSubviews.lastObject;
        if (![controlsStack isKindOfClass:[UIStackView class]]) continue;
        
        // Find the generate button to check its tag
        UIButton *generateButton = nil;
        for (UIView *control in controlsStack.arrangedSubviews) {
            if ([control isKindOfClass:[UIButton class]]) {
                UIButton *button = (UIButton *)control;
                NSString *buttonTitle = [button titleForState:UIControlStateNormal];
                if ([buttonTitle isEqualToString:@"刷新参数"] || 
                    [button.configuration.title isEqualToString:@"刷新参数"]) {
                    generateButton = button;
                    break;
                }
            }
        }
        
        if (!generateButton) {
            continue;
        }
        
        // Check if this is the container we want based on the tag
        BOOL isTargetContainer = (generateButton.tag == [self tagForIdentifierType:identifierType]);
        
        if (isTargetContainer) {
            NSLog(@"[WeaponX] ✅ Found container for %@ (tag: %ld)", identifierType, (long)generateButton.tag);
            foundContainer = YES;
            
            // Get the identifier container (first subview in content stack)
            UIView *identifierContainer = contentStack.arrangedSubviews.firstObject;
            if (![identifierContainer isKindOfClass:[UIView class]]) {
                NSLog(@"[WeaponX] ❌ Identifier container is not a UIView");
                continue;
            }
            
            // Find the label within the container
            UILabel *identifierLabel = nil;
            for (UIView *subview in identifierContainer.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    identifierLabel = (UILabel *)subview;
                    break;
                }
            }
            
            if (identifierLabel) {
                NSLog(@"[WeaponX] 🔄 Updating label from '%@' to '%@'", identifierLabel.text, value);
                
                // Ensure the update happens on the main thread
                if ([NSThread isMainThread]) {
                    identifierLabel.text = value ?: @"Not Set";
                    NSLog(@"[WeaponX] ✅ Label updated directly on main thread");
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        identifierLabel.text = value ?: @"Not Set";
                        NSLog(@"[WeaponX] ✅ Label updated via dispatch to main thread");
                    });
                }
                
                // Update the copy button's accessibility value
                UIButton *copyButton = controlsStack.arrangedSubviews.firstObject;
                if ([copyButton isKindOfClass:[UIButton class]]) {
                    copyButton.accessibilityValue = value;
                }
                
                return;
            } else {
                NSLog(@"[WeaponX] ❌ Could not find label in container");
            }
        }
    }
    
    if (!foundContainer) {
        NSLog(@"[WeaponX] ❌ Could not find container for %@", identifierType);
    }
}

- (void)generateAllButtonTapped:(UIButton *)sender {
    // Disable button temporarily
    sender.enabled = NO;
    
    // Show loading state
    UIColor *originalColor = sender.tintColor;
    [sender setTintColor:[UIColor systemGrayColor]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Regenerate all enabled identifiers
        [self.manager regenerateAllEnabledIdentifiers];
        
        // Get the new values for UI update
        NSString *newIDFA = [self.manager getValueForType:@"IDFA"];
        NSString *newIDFV = [self.manager getValueForType:@"IDFV"];
        NSString *newDeviceName = [self.manager currentValueForIdentifier:@"DeviceName"];
        NSString *newSerialNumber = [self.manager currentValueForIdentifier:@"SerialNumber"];
        NSString *newIOSVersion = [self.manager currentValueForIdentifier:@"IOSVersion"];
        NSString *newWiFiInfo = [self.manager currentValueForIdentifier:@"WiFi"];
        NSString *newStorageInfo = [self.manager currentValueForIdentifier:@"StorageSystem"];
        NSString *newBatteryInfo = [self.manager currentValueForIdentifier:@"Battery"];
        NSString *newSystemBootUUID = [self.manager currentValueForIdentifier:@"SystemBootUUID"];
        NSString *newDyldCacheUUID = [self.manager currentValueForIdentifier:@"DyldCacheUUID"];
        NSString *newPasteboardUUID = [self.manager currentValueForIdentifier:@"PasteboardUUID"];
        NSString *newKeychainUUID = [self.manager currentValueForIdentifier:@"KeychainUUID"];
        NSString *newUserDefaultsUUID = [self.manager currentValueForIdentifier:@"UserDefaultsUUID"];
        NSString *newAppGroupUUID = [self.manager currentValueForIdentifier:@"AppGroupUUID"];
        NSString *newDeviceModel = [self.manager currentValueForIdentifier:@"DeviceModel"];
        NSString *newSystemUptime = [self.manager currentValueForIdentifier:@"SystemUptime"];
        NSString *newBootTime = [self.manager currentValueForIdentifier:@"BootTime"];
        NSString *newCoreDataUUID = [self.manager generateCoreDataUUID];
        NSString *newAppInstallUUID = [self.manager currentValueForIdentifier:@"AppInstallUUID"];
        NSString *newAppContainerUUID = [self.manager currentValueForIdentifier:@"AppContainerUUID"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Re-enable button
            sender.enabled = YES;
            [sender setTintColor:originalColor];
            
            // Update UI with new values
            if ([self.manager isIdentifierEnabled:@"IDFA"]) {
                [self directUpdateIdentifierValue:@"IDFA" withValue:newIDFA];
            }
            
            if ([self.manager isIdentifierEnabled:@"IDFV"]) {
                [self directUpdateIdentifierValue:@"IDFV" withValue:newIDFV];
            }
            
            if ([self.manager isIdentifierEnabled:@"DeviceName"]) {
                [self directUpdateIdentifierValue:@"DeviceName" withValue:newDeviceName];
            }
            
            if ([self.manager isIdentifierEnabled:@"SerialNumber"]) {
                [self directUpdateIdentifierValue:@"SerialNumber" withValue:newSerialNumber];
            }
            
            if ([self.manager isIdentifierEnabled:@"IOSVersion"]) {
                [self directUpdateIdentifierValue:@"IOSVersion" withValue:newIOSVersion];
            }
            
            if ([self.manager isIdentifierEnabled:@"WiFi"]) {
                [self directUpdateIdentifierValue:@"WiFi" withValue:newWiFiInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"StorageSystem"]) {
                [self directUpdateIdentifierValue:@"StorageSystem" withValue:newStorageInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"Battery"]) {
                [self directUpdateIdentifierValue:@"Battery" withValue:newBatteryInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"SystemBootUUID"]) {
                [self directUpdateIdentifierValue:@"SystemBootUUID" withValue:newSystemBootUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"DyldCacheUUID"]) {
                [self directUpdateIdentifierValue:@"DyldCacheUUID" withValue:newDyldCacheUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"PasteboardUUID"]) {
                [self directUpdateIdentifierValue:@"PasteboardUUID" withValue:newPasteboardUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"KeychainUUID"]) {
                [self directUpdateIdentifierValue:@"KeychainUUID" withValue:newKeychainUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"UserDefaultsUUID"]) {
                [self directUpdateIdentifierValue:@"UserDefaultsUUID" withValue:newUserDefaultsUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppGroupUUID"]) {
                [self directUpdateIdentifierValue:@"AppGroupUUID" withValue:newAppGroupUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"SystemUptime"]) {
                [self directUpdateIdentifierValue:@"SystemUptime" withValue:newSystemUptime];
            }
      
            if ([self.manager isIdentifierEnabled:@"BootTime"]) {
                [self directUpdateIdentifierValue:@"BootTime" withValue:newBootTime];
            }
            
            if ([self.manager isIdentifierEnabled:@"CoreDataUUID"]) {
                [self directUpdateIdentifierValue:@"CoreDataUUID" withValue:newCoreDataUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppInstallUUID"]) {
                [self directUpdateIdentifierValue:@"AppInstallUUID" withValue:newAppInstallUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppContainerUUID"]) {
                [self directUpdateIdentifierValue:@"AppContainerUUID" withValue:newAppContainerUUID];
            }
            
            // Always update the device model
            [self directUpdateIdentifierValue:@"DeviceModel" withValue:newDeviceModel];
            
      
            
            // Show success feedback
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"Success" 
                message:@"All enabled identifiers have been regenerated" 
                preferredStyle:UIAlertControllerStyleAlert];
            
            [self presentViewController:alert animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [alert dismissViewControllerAnimated:YES completion:nil];
                });
            }];
        });
    });
}


#pragma mark - ProfileTabViewControllerDelegate

- (void)ProfileTabViewController:(UIViewController *)viewController didUpdateProfiles:(NSArray<Profile *> *)profiles {
    self.profiles = [profiles mutableCopy];
}

- (void)ProfileTabViewController:(UIViewController *)viewController didSelectProfile:(Profile *)profile {
    // Update the local profiles array
    self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
    
    // Update UI if needed based on the newly selected profile
    // For example, refresh any profile-dependent UI elements
    
    
    // Explicitly notify floating profile indicator to refresh
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ProfileManagerCurrentProfileChanged" 
                                                        object:nil 
                                                      userInfo:nil];
    
    // Also post a Darwin notification for the floating indicator
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, 
                                         CFSTR("com.hydra.projectx.profileChanged"), 
                                         NULL, 
                                         NULL, 
                                         YES);
}



- (void)copyIdentifierValue:(UIButton *)sender {
    // Determine which identifier type this is for
    NSString *identifierType = nil;
    NSUInteger tag = sender.tag;
    
    // Find the identifier type based on the tag
    for (NSString *type in self.identifierSwitches.allKeys) {
        if ([self.identifierSwitches[type] tag] == tag) {
            identifierType = type;
            break;
        }
    }
    
    if (!identifierType) return;
    
    // Get the current value of the identifier
    NSString *value = [self.manager currentValueForIdentifier:identifierType];
    if (value) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:value];
        
        // Show a success message
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Copied!" 
            message:[NSString stringWithFormat:@"%@ copied to clipboard", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [self presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    }
}

- (void)regenerateIdentifier:(UIButton *)sender {
    // Determine which identifier type this is for
    NSString *identifierType = nil;
    NSUInteger tag = sender.tag;
    
    // Find the identifier type based on the tag
    for (NSString *type in self.identifierSwitches.allKeys) {
        if ([self.identifierSwitches[type] tag] == tag) {
            identifierType = type;
            break;
        }
    }
    
    if (!identifierType) return;
    
    // Check if the identifier is enabled first
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Identifier Disabled" 
            message:[NSString stringWithFormat:@"Enable %@ spoofing first", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Generate new value based on identifier type
    if ([identifierType isEqualToString:@"IDFA"]) {
        [self.manager generateIDFA];
    } else if ([identifierType isEqualToString:@"IDFV"]) {
        [self.manager generateIDFV];
    } else if ([identifierType isEqualToString:@"DeviceName"]) {
        [self.manager generateDeviceName];
    } else if ([identifierType isEqualToString:@"SerialNumber"]) {
        [self.manager generateSerialNumber];
    } else if ([identifierType isEqualToString:@"IOSVersion"]) {
        [self.manager generateIOSVersion];
    } else if ([identifierType isEqualToString:@"WiFi"]) {
        [self.manager generateWiFiInformation];
    } else if ([identifierType isEqualToString:@"StorageSystem"]) {
        // ... existing StorageSystem code ...
    } else if ([identifierType isEqualToString:@"Battery"]) {
        // ... existing Battery code ...
    } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
        [self.manager generateSystemBootUUID];
    } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
        [self.manager generateDyldCacheUUID];
    } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
        [self.manager generatePasteboardUUID];
    } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
        [self.manager generateKeychainUUID];
    } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
        [self.manager generateUserDefaultsUUID];
    } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
        [self.manager generateAppGroupUUID];
    } else if ([identifierType isEqualToString:@"SystemUptime"]) {
        [self.manager generateSystemUptime];
    } else if ([identifierType isEqualToString:@"BootTime"]) {
        [self.manager generateBootTime];
    } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
        [self.manager generateCoreDataUUID];
    } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
        [self.manager generateAppInstallUUID];
    } else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
        [self.manager generateAppContainerUUID];
    } else {
        return;
    }
    
    // Check for errors
    if ([self.manager lastError]) {
        [self showError:[self.manager lastError]];
        return;
    }
    
    // Refresh UI to show new value
    [self loadSettings];
    
    // Show a success message
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Regenerated" 
        message:[NSString stringWithFormat:@"%@ has been regenerated", identifierType]
        preferredStyle:UIAlertControllerStyleAlert];
    
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

// New method to refresh identifier values
- (void)refreshIdentifierValuesInUI {
    // Get the IdentifierManager
    Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
    if (!identifierManagerClass) {
        NSLog(@"[WeaponX] ❌ Could not find IdentifierManager class for refresh");
        return;
    }
    
    id identifierManager = [identifierManagerClass sharedManager];
    if (!identifierManager) {
        NSLog(@"[WeaponX] ❌ Could not get IdentifierManager instance for refresh");
        return;
    }
    
    // Log the current profile path for debugging
    if ([identifierManager respondsToSelector:@selector(profileIdentityPath)]) {
        NSString *profilePath = [identifierManager performSelector:@selector(profileIdentityPath)];
        NSLog(@"[WeaponX] 🔍 Current profile path: %@", profilePath);
    }
    
    // Check if identifiers are enabled and get current values
    SEL isEnabledSel = NSSelectorFromString(@"isIdentifierEnabled:");
    SEL currentValueSel = NSSelectorFromString(@"currentValueForIdentifier:");
    
    if ([identifierManager respondsToSelector:isEnabledSel] && [identifierManager respondsToSelector:currentValueSel]) {
        // Helper method to safely perform selector
        BOOL (^performBoolSelector)(id, SEL, id) = ^(id target, SEL selector, id object) {
            NSMethodSignature *signature = [target methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:target];
            [invocation setSelector:selector];
            if (object) {
                [invocation setArgument:&object atIndex:2];
            }
            [invocation invoke];
            BOOL result = NO;
            [invocation getReturnValue:&result];
            return result;
        };
        
        NSString* (^performStringSelector)(id, SEL, id) = ^(id target, SEL selector, id object) {
            NSMethodSignature *signature = [target methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:target];
            [invocation setSelector:selector];
            if (object) {
                [invocation setArgument:&object atIndex:2];
            }
            [invocation invoke];
            __unsafe_unretained NSString *result = nil;
            [invocation getReturnValue:&result];
            return result;
        };
        
        NSArray *identifierTypes = @[@"IDFA", @"IDFV", @"DeviceName", @"SerialNumber", @"IOSVersion", @"WiFi", @"StorageSystem", @"Battery", @"SystemBootUUID", @"DyldCacheUUID", @"PasteboardUUID", @"KeychainUUID", @"UserDefaultsUUID", @"AppGroupUUID", @"CoreDataUUID", @"SystemUptime", @"BootTime", @"AppInstallUUID", @"AppContainerUUID"];
        
        for (NSString *type in identifierTypes) {
            BOOL isEnabled = performBoolSelector(identifierManager, isEnabledSel, type);
            NSLog(@"[WeaponX] 🔍 Checking %@ - Enabled: %@", type, isEnabled ? @"YES" : @"NO");
            
            if (isEnabled) {
                NSString *value = performStringSelector(identifierManager, currentValueSel, type);
                NSLog(@"[WeaponX] 🔍 %@ current value: %@", type, value ?: @"nil");
                
                if (value) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self directUpdateIdentifierValue:type withValue:value];
                    });
                } else {
                    NSLog(@"[WeaponX] ⚠️ No value found for enabled identifier: %@", type);
                }
            }
        }
    } else {
        NSLog(@"[WeaponX] ❌ IdentifierManager missing required methods");
    }
}

// Replace the identifierDidTap method to handle Battery like other simple identifiers
- (void)identifierDidTap:(UITapGestureRecognizer *)gesture {
    // Get the identifier type from the associated object
    NSString *identifierType = objc_getAssociatedObject(gesture, "identifierType");
    if (!identifierType) {
        return;
    }
    
    // Check if spoofing is enabled for this identifier
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Spoofing Disabled" 
            message:[NSString stringWithFormat:@"Please enable %@ spoofing first.", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // For all identifiers, simply click the generate button
    int tag = 0;
    if ([identifierType isEqualToString:@"IDFA"])
        tag = 1;
    else if ([identifierType isEqualToString:@"IDFV"])
        tag = 2;
    else if ([identifierType isEqualToString:@"DeviceName"])
        tag = 3;
    else if ([identifierType isEqualToString:@"SerialNumber"])
        tag = 4;
    else if ([identifierType isEqualToString:@"IOSVersion"])
        tag = 5;
    else if ([identifierType isEqualToString:@"WiFi"])
        tag = 6;
    else if ([identifierType isEqualToString:@"StorageSystem"])
        tag = 7;
    else if ([identifierType isEqualToString:@"Battery"])
        tag = 8;
    else if ([identifierType isEqualToString:@"SystemBootUUID"])
        tag = 9;
    else if ([identifierType isEqualToString:@"DyldCacheUUID"])
        tag = 10;
    else if ([identifierType isEqualToString:@"PasteboardUUID"])
        tag = 11;
    else if ([identifierType isEqualToString:@"KeychainUUID"])
        tag = 12;
    else if ([identifierType isEqualToString:@"UserDefaultsUUID"])
        tag = 13;
    else if ([identifierType isEqualToString:@"AppGroupUUID"])
        tag = 14;
    else if ([identifierType isEqualToString:@"SystemUptime"])
        tag = 15;
    else if ([identifierType isEqualToString:@"BootTime"])
        tag = 16;
    else if ([identifierType isEqualToString:@"CoreDataUUID"])
        tag = 17;
    else if ([identifierType isEqualToString:@"AppInstallUUID"])
        tag = 18;
    else if ([identifierType isEqualToString:@"AppContainerUUID"])
        tag = 19;
    if (tag > 0) {
        [self generateButtonTapped:[self buttonWithTag:tag]];
    }
}

// Remove unused battery configuration methods
// Delete these methods:
// showBatteryConfigurationUI
// setBatteryLevel:lowPowerMode:
// toggleLowPowerMode
// showCustomBatteryInput
// randomizeBattery

// Add helper methods for finding buttons by tag
- (UIButton *)buttonWithTag:(NSInteger)tag {
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Find buttons with matching tag
        if ([view isKindOfClass:[UIView class]]) {
            NSArray *buttons = [self findSubviewsOfClass:[UIButton class] inView:view];
            for (UIButton *button in buttons) {
                if (button.tag == tag) {
                    return button;
                }
            }
        }
    }
    return nil;
}

- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view {
    NSMutableArray *result = [NSMutableArray array];
    
    if ([view isKindOfClass:cls]) {
        [result addObject:view];
    }
    
    for (UIView *subview in view.subviews) {
        [result addObjectsFromArray:[self findSubviewsOfClass:cls inView:subview]];
    }
    
    return result;
}

// Add this helper method at the end of the @implementation
- (NSInteger)tagForIdentifierType:(NSString *)type {
    if ([type isEqualToString:@"IDFA"]) return 1;
    if ([type isEqualToString:@"IDFV"]) return 2;
    if ([type isEqualToString:@"DeviceName"]) return 3;
    if ([type isEqualToString:@"SerialNumber"]) return 4;
    if ([type isEqualToString:@"IOSVersion"]) return 5;
    if ([type isEqualToString:@"WiFi"]) return 6;
    if ([type isEqualToString:@"StorageSystem"]) return 7;
    if ([type isEqualToString:@"Battery"]) return 8;
    if ([type isEqualToString:@"SystemBootUUID"]) return 9;
    if ([type isEqualToString:@"DyldCacheUUID"]) return 10;
    if ([type isEqualToString:@"PasteboardUUID"]) return 11;
    if ([type isEqualToString:@"KeychainUUID"]) return 12;
    if ([type isEqualToString:@"UserDefaultsUUID"]) return 13;
    if ([type isEqualToString:@"AppGroupUUID"]) return 14;
    if ([type isEqualToString:@"SystemUptime"]) return 15;
    if ([type isEqualToString:@"BootTime"]) return 16;
    if ([type isEqualToString:@"CoreDataUUID"]) return 17;
    if ([type isEqualToString:@"AppInstallUUID"]) return 18;
    if ([type isEqualToString:@"AppContainerUUID"]) return 19;
    return 0;
}

// Add iPad orientation support
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}


- (void)titleIconTapped:(UITapGestureRecognizer *)gesture {
    // Get the identifier type from the associated object
    NSString *identifierType = objc_getAssociatedObject(gesture, "identifierType");
    if (!identifierType) {
        return;
    }
    
    // Check if spoofing is enabled for this identifier
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Spoofing Disabled" 
            message:[NSString stringWithFormat:@"Please enable %@ spoofing first.", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Get current value
    NSString *currentValue = [self.manager currentValueForIdentifier:identifierType];
    
    // Create alert with text field to edit value
    UIAlertController *editAlert = [UIAlertController 
        alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", identifierType]
        message:@"Enter a new value or leave blank to auto-generate"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"New Value";
        textField.text = currentValue;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        
        // For UUID types, add validation
        if ([identifierType containsString:@"UUID"]) {
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }
    }];
    
    // Add cancel action
    [editAlert addAction:[UIAlertAction 
        actionWithTitle:@"Cancel" 
        style:UIAlertActionStyleCancel 
        handler:nil]];
    
    // Add save action
    [editAlert addAction:[UIAlertAction 
        actionWithTitle:@"Save" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
            UITextField *textField = editAlert.textFields.firstObject;
            NSString *newValue = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            // If empty, generate a new value
            if (newValue.length == 0) {
                [self generateValueForIdentifier:identifierType];
                return;
            }
            
            // For UUID values, validate format
            if ([identifierType containsString:@"UUID"]) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
                                                                            options:NSRegularExpressionCaseInsensitive 
                                                                            error:nil];
                
                NSUInteger matches = [regex numberOfMatchesInString:newValue 
                                                          options:0 
                                                            range:NSMakeRange(0, newValue.length)];
                
                if (matches != 1) {
                    // Invalid UUID format
                    UIAlertController *errorAlert = [UIAlertController 
                        alertControllerWithTitle:@"Invalid Format" 
                        message:@"Please enter a valid UUID in the format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" 
                        preferredStyle:UIAlertControllerStyleAlert];
                    
                    [errorAlert addAction:[UIAlertAction 
                        actionWithTitle:@"OK" 
                        style:UIAlertActionStyleDefault 
                        handler:nil]];
                    
                    [self presentViewController:errorAlert animated:YES completion:nil];
                    return;
                }
            }
            
            // Update value in manager
            [self setCustomValue:newValue forIdentifier:identifierType];
        }]];
    
    [self presentViewController:editAlert animated:YES completion:nil];
}

- (void)setCustomValue:(NSString *)value forIdentifier:(NSString *)type {
    // This implementation depends on how values can be set in your manager
    // We need to forward it to the appropriate manager
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = YES;
        
        // Save the custom value depending on identifier type
        [self.manager setValueForType:value forType:type];
        
        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // Refresh the value in UI
                NSString *updatedValue = [self.manager currentValueForIdentifier:type];
                [self directUpdateIdentifierValue:type withValue:updatedValue];
                
                // Show success message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Value Updated" 
                    message:[NSString stringWithFormat:@"%@ has been updated.", type]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [self presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    });
                }];
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Update Failed" 
                    message:[NSString stringWithFormat:@"Failed to update %@. Please try again.", type]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                    actionWithTitle:@"OK" 
                    style:UIAlertActionStyleDefault 
                    handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

- (void)generateValueForIdentifier:(NSString *)identifierType {
    // Show loading indicator
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Generate a new value for the specified identifier
        NSString *newValue = nil;
        if ([identifierType isEqualToString:@"IDFA"]) {
            newValue = [self.manager generateIDFA];
        } else if ([identifierType isEqualToString:@"IDFV"]) {
            newValue = [self.manager generateIDFV];
        } else if ([identifierType isEqualToString:@"DeviceName"]) {
            newValue = [self.manager generateDeviceName];
        } else if ([identifierType isEqualToString:@"SerialNumber"]) {
            newValue = [self.manager generateSerialNumber];
        } else if ([identifierType isEqualToString:@"IOSVersion"]) {
            // Generate iOS Version and then get the string representation
            [self.manager generateIOSVersion];
            newValue = [self.manager currentValueForIdentifier:@"IOSVersion"];
        } else if ([identifierType isEqualToString:@"WiFi"]) {
            newValue = [self.manager generateWiFiInformation];
        } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
            newValue = [self.manager generateSystemBootUUID];
        } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
            newValue = [self.manager generateDyldCacheUUID];
        } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
            newValue = [self.manager generatePasteboardUUID];
        } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
            newValue = [self.manager generateKeychainUUID];
        } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
            newValue = [self.manager generateUserDefaultsUUID];
        } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
            newValue = [self.manager generateAppGroupUUID];
        } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
            newValue = [self.manager generateCoreDataUUID];
        } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
            newValue = [self.manager generateAppInstallUUID];
        } else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
            newValue = [self.manager generateAppContainerUUID];
        } else if ([identifierType isEqualToString:@"StorageSystem"]) {
            // Get StorageManager class
            Class storageManagerClass = NSClassFromString(@"StorageManager");
            if (storageManagerClass && [storageManagerClass respondsToSelector:@selector(sharedManager)]) {
                id storageManager = [storageManagerClass sharedManager];
                if (storageManager) {
                    // Generate a random storage capacity (either 64GB or 128GB)
                    NSString *capacity = [storageManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                       [storageManager randomizeStorageCapacity] : @"64";
                    
                    // Generate the storage information based on the capacity
                    if ([storageManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                        NSDictionary *storageInfo = [storageManager generateStorageForCapacity:capacity];
                        if (storageInfo) {
                            // Update the StorageManager with the generated values
                            [storageManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                            [storageManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                            [storageManager setFilesystemType:storageInfo[@"FilesystemType"]];
                            
                            // Format the value for display
                            newValue = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                      storageInfo[@"TotalStorage"], 
                                      storageInfo[@"FreeStorage"]];
                        }
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                BOOL use128GB = (arc4random_uniform(100) < 60);
                newValue = use128GB ? @"Total: 128 GB, Free: 38.4 GB" : @"Total: 64 GB, Free: 19.8 GB";
            }
        } else if ([identifierType isEqualToString:@"Battery"]) {
            // Get BatteryManager class
            Class batteryManagerClass = NSClassFromString(@"BatteryManager");
            if (batteryManagerClass && [batteryManagerClass respondsToSelector:@selector(sharedManager)]) {
                id batteryManager = [batteryManagerClass sharedManager];
                if (batteryManager && [batteryManager respondsToSelector:@selector(generateBatteryInfo)]) {
                    NSDictionary *batteryInfo = [batteryManager generateBatteryInfo];
                    if (batteryInfo) {
                        // Update display value - just show battery percentage now
                        NSString *level = batteryInfo[@"BatteryLevel"];
                        float levelFloat = [level floatValue];
                        int percentage = (int)(levelFloat * 100);
                        
                        newValue = [NSString stringWithFormat:@"%d%%", percentage];
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                int randomPercentage = 20 + arc4random_uniform(81); // 20-100%
                newValue = [NSString stringWithFormat:@"%d%%", randomPercentage];
            }
        } else if ([identifierType isEqualToString:@"SystemUptime"]) {
            newValue = [self.manager generateSystemUptime];
        } else if ([identifierType isEqualToString:@"BootTime"]) {
            newValue = [self.manager generateBootTime];
        }
        
        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ([self.manager lastError]) {
                [self showError:[self.manager lastError]];
                return;
            }
            
            // Save settings
            [self.manager saveSettings];
            
            // Update the UI with the new value
            if (newValue) {
                [self directUpdateIdentifierValue:identifierType withValue:newValue];
                
                // Show success message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Generated" 
                    message:[NSString stringWithFormat:@"New %@ generated", identifierType]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [self presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    });
                }];
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Generation Failed" 
                    message:[NSString stringWithFormat:@"Failed to generate %@. Please try again.", identifierType]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                    actionWithTitle:@"OK" 
                    style:UIAlertActionStyleDefault 
                    handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}



#pragma mark - More Options Button Action


- (void)handleProfileChanged:(NSNotification *)notification {
    // This method is called when the profile changes
    NSLog(@"[WeaponX] Profile changed notification received");
    
    // Refresh all identifier values in the UI
    [self refreshIdentifierValuesInUI];
    
    // Also refresh the apps list in case app scoping has changed
    [self loadSettings];
}

#pragma mark - Memory Management

- (void)dealloc {
    // Remove all notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end