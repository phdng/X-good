#import "SecurityTabViewController.h"
#import "ProjectXLogging.h"
#import "DomainBlockingSettings.h"
#import "DomainManagementViewController.h"
#import <notify.h>  // Add this import for Darwin notification functions
#import <CoreLocation/CoreLocation.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <MapKit/MapKit.h>


@interface SecurityTabViewController () <UITextFieldDelegate>

// Domain Blocking Properties
@property (nonatomic, strong) UISwitch *domainBlockingToggleSwitch;
@property (nonatomic, strong) UIButton *domainManagementButton;

// Matrix Rain View (properties declared in header)

@property (nonatomic, strong) UIButton *ipMonitorCheckButton;
@property (nonatomic, strong) UISwitch *ipMonitorToggleSwitch;
// Any private properties go here
@property (nonatomic, strong) UILabel *copyrightLabel;
@property (nonatomic, strong) NSCache *countryCache;
@property (nonatomic, strong) NSTimer *timeUpdateTimer;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NSString *currentTimeZoneId;
@property (nonatomic, strong) UITextField *localIPv6Field;
@property (nonatomic, strong) UIButton *localIPv6GenerateButton;

@end

@implementation SecurityTabViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.countryCache = [[NSCache alloc] init];
        [self.countryCache setCountLimit:50]; // Limit cache size
    }
    return self;
}



- (void)refreshPinnedCoordinates {
    // Set the main title directly
    self.title = @"设置";
    
    // Remove any existing barButtonItems to prevent duplication
    self.navigationItem.rightBarButtonItems = nil;
    self.navigationItem.leftBarButtonItems = nil;
    
    // Create a custom view for the right bar button item (coordinates and time)
    UIView *rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
    
    // Create coordinates label
    UILabel *coordsLabel = [[UILabel alloc] init];
    coordsLabel.textColor = [UIColor secondaryLabelColor];
    coordsLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    coordsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    coordsLabel.adjustsFontSizeToFitWidth = YES;
    coordsLabel.minimumScaleFactor = 0.8;
    coordsLabel.textAlignment = NSTextAlignmentRight;
    [rightView addSubview:coordsLabel];
    
    // Create time label
    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.textColor = [UIColor secondaryLabelColor];
    self.timeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.timeLabel.textAlignment = NSTextAlignmentRight;
    self.timeLabel.userInteractionEnabled = YES;
    [rightView addSubview:self.timeLabel];
    
    // Set up constraints for right view
    [NSLayoutConstraint activateConstraints:@[
        // Position coordinates label
        [coordsLabel.topAnchor constraintEqualToAnchor:rightView.topAnchor constant:-2],
        [coordsLabel.trailingAnchor constraintEqualToAnchor:rightView.trailingAnchor],
        [coordsLabel.leadingAnchor constraintEqualToAnchor:rightView.leadingAnchor],
        
        // Position time label
        [self.timeLabel.topAnchor constraintEqualToAnchor:coordsLabel.bottomAnchor constant:2],
        [self.timeLabel.trailingAnchor constraintEqualToAnchor:coordsLabel.trailingAnchor],
        [self.timeLabel.leadingAnchor constraintEqualToAnchor:coordsLabel.leadingAnchor]
    ]];


}




- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPinnedCoordinates];
    
    // Refresh network identifiers from the current profile
    [self refreshNetworkIdentifiers];
    
}

// Add a method to refresh network identifiers from the current profile
- (void)refreshNetworkIdentifiers {
    // Only refresh if network data spoofing is enabled
    if (![self.securitySettings boolForKey:@"networkDataSpoofEnabled"]) {
        return;
    }
    
    // Get the current connection type setting
    NSInteger connectionType = [self.securitySettings integerForKey:@"networkConnectionType"];
    
    // Get NetworkManager class
    Class networkManagerClass = NSClassFromString(@"NetworkManager");
    if (!networkManagerClass) {
        NSLog(@"[WeaponX] Failed to get NetworkManager class for identifier refresh");
        return;
    }
    
    // Disable random force refresh - always use existing values, never auto-generate new ones
    BOOL forceRefresh = NO;
    NSLog(@"[WeaponX] Network identifier refresh - Force refresh: %@", forceRefresh ? @"YES" : @"NO");
    
    // Refresh based on connection type
    if (connectionType == 0 || connectionType == 1) {
        // Auto or WiFi - Update local IP address
        // Use the getSavedLocalIPAddress method to avoid generation
        SEL localIPSel = NSSelectorFromString(@"getSavedLocalIPAddress");
            
        if ([networkManagerClass respondsToSelector:localIPSel]) {
            // Use NSInvocation to safely call the class method
            NSMethodSignature *signature = [networkManagerClass methodSignatureForSelector:localIPSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setTarget:networkManagerClass];
                [invocation setSelector:localIPSel];
                
                [invocation invoke];
                
                // Get the return value
                NSString * __unsafe_unretained localIP;
                [invocation getReturnValue:&localIP];
                
                if (localIP) {
                    NSLog(@"[WeaponX] ✅ Updated UI with saved local IP address: %@", localIP);
                    
                    // Update the displayed local IP address if the UI elements exist
                    if (self.localIPField && connectionType == 1) {
                        self.localIPField.text = localIP;
                    }
                }
            }
        }
    }
    
    if (connectionType == 0 || connectionType == 2) {
        // Auto or Cellular - Update carrier details
        // Use the getSavedCarrierDetails method to avoid generation
        SEL carrierDetailsSel = NSSelectorFromString(@"getSavedCarrierDetails");
            
        if ([networkManagerClass respondsToSelector:carrierDetailsSel]) {
            // Use NSInvocation to safely call the class method
            NSMethodSignature *signature = [networkManagerClass methodSignatureForSelector:carrierDetailsSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setTarget:networkManagerClass];
                [invocation setSelector:carrierDetailsSel];
                
                [invocation invoke];
                
                // Get the return value
                NSDictionary * __unsafe_unretained carrierInfo;
                [invocation getReturnValue:&carrierInfo];
                
                if (carrierInfo) {
                    NSLog(@"[WeaponX] ✅ Updated UI with saved carrier details: %@ (%@-%@)", 
                          carrierInfo[@"name"], carrierInfo[@"mcc"], carrierInfo[@"mnc"]);
                           
                    // Update the UI if we have carrier info labels
                    if (connectionType == 2) {
                        // Update carrier display in the UI if it exists
                        if (self.carrierNameField) {
                            self.carrierNameField.text = carrierInfo[@"name"];
                        }
                        if (self.mccField) {
                            self.mccField.text = carrierInfo[@"mcc"];
                        }
                        if (self.mncField) {
                            self.mncField.text = carrierInfo[@"mnc"];
                        }
                    }
                }
            }
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshPinnedCoordinates];
    self.view.backgroundColor = [UIColor systemBackgroundColor]; // Use system theme color
    
    // Initialize security settings
    self.securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    

    
    // Add tap gesture recognizer to dismiss keyboard when tapping elsewhere
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    // Create scroll view container
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsVerticalScrollIndicator = NO; // Hide the vertical scroll indicator
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];
    
    // Create content view for scroll view
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];
    
    // Setup scroll view constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
    ]];
    
        
    // // Add Network Data Spoof toggle control
    // [self setupNetworkDataSpoofControl:contentView];
    
    // // Add Network Connection Type control (WiFi/Cellular)
    // [self setupNetworkConnectionTypeControl:contentView];
       
    // Add Domain Blocking control
    [self setupDomainBlockingControl:contentView];
    
    
}




#pragma mark - Time Spoofing Control

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
}

// Method to dismiss keyboard when tapping outside text fields
- (void)dismissKeyboard {
    // End editing for carrier fields
    [self.carrierNameField resignFirstResponder];
    [self.mccField resignFirstResponder];
    [self.mncField resignFirstResponder];
    
    // End editing for local IP field
    [self.localIPField resignFirstResponder];
}


#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // We don't use the table view anymore, but need to implement the required method
    return 0;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // We don't use the table view anymore, but need to implement the required method
    return [[UITableViewCell alloc] init];
}



// Helper method to show a toast-like notification at the top
- (void)showToastWithMessage:(NSString *)message {
    CGFloat toastHeight = 60.0;
    CGFloat padding = 16.0;
    UILabel *toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, 44 + padding, self.view.frame.size.width - 2 * padding, toastHeight)];
    toastLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.textAlignment = NSTextAlignmentCenter;
    toastLabel.font = [UIFont boldSystemFontOfSize:16.0];
    toastLabel.text = message;
    toastLabel.numberOfLines = 2;
    toastLabel.layer.cornerRadius = 12;
    toastLabel.layer.masksToBounds = YES;
    toastLabel.alpha = 0.0;
    toastLabel.userInteractionEnabled = NO;
    toastLabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:toastLabel];

    [UIView animateWithDuration:0.3 animations:^{
        toastLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastLabel.alpha = 0.0;
            } completion:^(BOOL finished2) {
                [toastLabel removeFromSuperview];
            }];
        });
    }];
}

- (void)dealloc {
    [self.timeUpdateTimer invalidate];
    self.timeUpdateTimer = nil;
}





#pragma mark - UITextFieldDelegate

// Handle return key press in text fields
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

// Helper method to add a "Done" button to number pad keyboard
- (void)addDoneButtonToNumberPad:(UITextField *)textField {
    // Create a toolbar
    UIToolbar* numberToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    numberToolbar.barStyle = UIBarStyleDefault;
    
    // Create a flexible space and done button
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    
    // Add the buttons to the toolbar
    numberToolbar.items = @[flexibleSpace, doneButton];
    [numberToolbar sizeToFit];
    
    // Set the toolbar as the textfield's input accessory view
    textField.inputAccessoryView = numberToolbar;
}

- (void)setupDomainBlockingControl:(UIView *)contentView {
    // Create a glassmorphic control for Domain Blocking
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Domain Blocking";
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:titleLabel];
    
    // Description label
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"Block tracking domains for scoped apps";
    descriptionLabel.font = [UIFont systemFontOfSize:12];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.numberOfLines = 2;
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:descriptionLabel];
    
    // Info button
    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.tintColor = [UIColor labelColor];
    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [infoButton addTarget:self action:@selector(showDomainBlockingInfo) forControlEvents:UIControlEventTouchUpInside];
    [controlView.contentView addSubview:infoButton];
    
    // Toggle switch
    self.domainBlockingToggleSwitch = [[UISwitch alloc] init];
    self.domainBlockingToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.domainBlockingToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.domainBlockingToggleSwitch addTarget:self action:@selector(domainBlockingToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.domainBlockingToggleSwitch];
    
    // Set initial toggle state
    DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
    [self.domainBlockingToggleSwitch setOn:settings.isEnabled animated:NO];
    
    // Manage domains button
    self.domainManagementButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.domainManagementButton setTitle:@"Manage Domains" forState:UIControlStateNormal];
    self.domainManagementButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.domainManagementButton addTarget:self action:@selector(showDomainManagement) forControlEvents:UIControlEventTouchUpInside];
    [controlView.contentView addSubview:self.domainManagementButton];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Control view
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:320], // Position between App Version Spoofing and Canvas Fingerprinting
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:120],
        
        // Title label
        [titleLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        [titleLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:15],
        
        // Info button
        [infoButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [infoButton.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-15],
        [infoButton.heightAnchor constraintEqualToConstant:24],
        [infoButton.widthAnchor constraintEqualToConstant:24],
        
        // Description label
        [descriptionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:5],
        [descriptionLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [descriptionLabel.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-15],
        
        // Toggle switch
        [self.domainBlockingToggleSwitch.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [self.domainBlockingToggleSwitch.trailingAnchor constraintEqualToAnchor:infoButton.leadingAnchor constant:-10],
        
        // Manage domains button
        [self.domainManagementButton.topAnchor constraintEqualToAnchor:descriptionLabel.bottomAnchor constant:15],
        [self.domainManagementButton.leadingAnchor constraintEqualToAnchor:descriptionLabel.leadingAnchor],
    ]];
    [NSLayoutConstraint activateConstraints:@[
        // ... 你现有的所有约束 ...
        
        // 添加这个关键约束：将 contentView 的底部锚定到 controlView 的底部
        [contentView.bottomAnchor constraintEqualToAnchor:controlView.bottomAnchor constant:50]
    ]];
}


#pragma mark - Domain Blocking Methods

- (void)domainBlockingToggleChanged:(UISwitch *)sender {
    DomainBlockingSettings *settings = [DomainBlockingSettings sharedSettings];
    settings.isEnabled = sender.isOn;
    [settings saveSettings];
    
    // Provide haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    PXLog(@"[WeaponX] Domain Blocking %@", sender.isOn ? @"ENABLED" : @"DISABLED");
}

- (void)showDomainManagement {
    DomainManagementViewController *vc = [[DomainManagementViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDomainBlockingInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Domain Blocking"
                                                                 message:@"Block tracking and verification domains for scoped apps to prevent app attestation and device fingerprinting.\n\nBlocks domains like devicecheck.apple.com, appattest.apple.com, and other tracking services by default.\n\nThis feature only affects apps in your scoped apps list."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}



@end