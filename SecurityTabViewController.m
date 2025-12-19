#import "SecurityTabViewController.h"
#import "ProjectXLogging.h"
#import "NetworkManager.h"
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
    
        
    // Add Network Data Spoof toggle control
    [self setupNetworkDataSpoofControl:contentView];
    
    // Add Network Connection Type control (WiFi/Cellular)
    [self setupNetworkConnectionTypeControl:contentView];
       
    // Add Domain Blocking control
    [self setupDomainBlockingControl:contentView];
    
    
}


- (void)setupNetworkDataSpoofControl:(UIView *)contentView {
    // Create a glassmorphic control for Network Data Spoof toggle
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Network Data Spoof label
    self.networkDataSpoofLabel = [[UILabel alloc] init];
    self.networkDataSpoofLabel.text = @"Network Data Spoof";
    self.networkDataSpoofLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.networkDataSpoofLabel.textColor = [UIColor labelColor];
    self.networkDataSpoofLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.networkDataSpoofLabel];
    
    // Optional label (yellow text)
    UILabel *optionalLabel = [[UILabel alloc] init];

    optionalLabel.text = @"(OPTIONAL)";
    optionalLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    optionalLabel.textColor = [UIColor secondaryLabelColor];
    optionalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:optionalLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.networkDataSpoofInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.networkDataSpoofInfoButton.tintColor = [UIColor systemBlueColor];
    self.networkDataSpoofInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.networkDataSpoofInfoButton addTarget:self action:@selector(showNetworkDataSpoofInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.networkDataSpoofInfoButton];
    
    // Network Data Spoof toggle switch
    self.networkDataSpoofToggleSwitch = [[UISwitch alloc] init];
    self.networkDataSpoofToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.networkDataSpoofToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Check if network data spoof is enabled
    BOOL networkDataSpoofEnabled = [self.securitySettings boolForKey:@"networkDataSpoofEnabled"];
    [self.networkDataSpoofToggleSwitch setOn:networkDataSpoofEnabled animated:NO];
    
    [self.networkDataSpoofToggleSwitch addTarget:self action:@selector(networkDataSpoofToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.networkDataSpoofToggleSwitch];
    
    // Position control under the jailbreak detection control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20], // Position below Jailbreak Detection control
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:60],
        
        [self.networkDataSpoofLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.networkDataSpoofLabel.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        
        // Position optional label to the right of the Network Data Spoof label
        [optionalLabel.leadingAnchor constraintEqualToAnchor:self.networkDataSpoofLabel.trailingAnchor constant:5],
        [optionalLabel.bottomAnchor constraintEqualToAnchor:self.networkDataSpoofLabel.bottomAnchor constant:-2],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:optionalLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.networkDataSpoofInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.networkDataSpoofInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        [self.networkDataSpoofToggleSwitch.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.networkDataSpoofToggleSwitch.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor]
    ]];
}

- (void)setupNetworkConnectionTypeControl:(UIView *)contentView {
    // Only show this control if network data spoofing is enabled
    BOOL networkDataSpoofEnabled = [self.securitySettings boolForKey:@"networkDataSpoofEnabled"];
    
    // Create a glassmorphic control for Network Connection Type selection
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = networkDataSpoofEnabled ? 0.8 : 0.4; // Dim if network spoofing is disabled
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    controlView.tag = 1001; // Tag for easy reference
    [contentView addSubview:controlView];
    
    // Network Connection Type label
    self.networkConnectionTypeLabel = [[UILabel alloc] init];
    self.networkConnectionTypeLabel.text = @"Network Connection Type";
    self.networkConnectionTypeLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.networkConnectionTypeLabel.textColor = [UIColor labelColor];
    self.networkConnectionTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.networkConnectionTypeLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.networkConnectionTypeInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.networkConnectionTypeInfoButton.tintColor = [UIColor systemBlueColor];
    self.networkConnectionTypeInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.networkConnectionTypeInfoButton addTarget:self action:@selector(showNetworkConnectionTypeInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.networkConnectionTypeInfoButton];
    
    // Network Connection Type segmented control
    NSArray *segments = @[@"Auto", @"WiFi", @"Cellular", @"None"];
    self.networkConnectionTypeSegment = [[UISegmentedControl alloc] initWithItems:segments];
    self.networkConnectionTypeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Load saved setting or default to Auto (0)
    NSInteger savedConnectionType = [self.securitySettings integerForKey:@"networkConnectionType"];
    if (savedConnectionType < 0 || savedConnectionType > 3) {
        savedConnectionType = 0; // Default to Auto
    }
    [self.networkConnectionTypeSegment setSelectedSegmentIndex:savedConnectionType];
    
    // Enable/disable based on network data spoofing toggle
    self.networkConnectionTypeSegment.enabled = networkDataSpoofEnabled;
    
    [self.networkConnectionTypeSegment addTarget:self action:@selector(networkConnectionTypeChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.networkConnectionTypeSegment];

    // --- ISO Country Code segmented control (only for Cellular) ---
    NSArray *isoSegments = @[@"US", @"IN", @"CA"];
    self.networkISOCountrySegment = [[UISegmentedControl alloc] initWithItems:isoSegments];
    self.networkISOCountrySegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.networkISOCountrySegment.tag = 2001;
    
    // Load saved ISO code or default to US
    NSString *savedISO = [self.securitySettings stringForKey:@"networkISOCountryCode"] ?: @"us";
    NSInteger defaultISOIndex = 0;
    if ([savedISO isEqualToString:@"in"]) defaultISOIndex = 1;
    else if ([savedISO isEqualToString:@"ca"]) defaultISOIndex = 2;
    else if (![savedISO isEqualToString:@"us"] && ![savedISO isEqualToString:@"in"] && ![savedISO isEqualToString:@"ca"]) {
        // This is a custom ISO code
        defaultISOIndex = -1; // Don't select any segment
    }
    [self.networkISOCountrySegment setSelectedSegmentIndex:defaultISOIndex];
    
    // Enable/disable based on network data spoofing and connection type
    self.networkISOCountrySegment.enabled = (networkDataSpoofEnabled && savedConnectionType == 2);
    [self.networkISOCountrySegment addTarget:self action:@selector(networkISOCountryChanged:) forControlEvents:UIControlEventValueChanged];
    
    // Add custom ISO button
    self.customISOButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.customISOButton setTitle:@"Custom" forState:UIControlStateNormal];
    
    // Style to match segmented control appearance
    self.customISOButton.backgroundColor = [UIColor systemBackgroundColor];
    if (@available(iOS 13.0, *)) {
        self.customISOButton.backgroundColor = [UIColor systemGray5Color];
    }
    self.customISOButton.layer.cornerRadius = 4;
    self.customISOButton.titleLabel.font = [UIFont systemFontOfSize:13];
    self.customISOButton.tintColor = [UIColor labelColor];
    
    // Highlight the button if a custom ISO is selected
    if (defaultISOIndex == -1) {
        if (@available(iOS 13.0, *)) {
            self.customISOButton.backgroundColor = [UIColor systemBlueColor];
            [self.customISOButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
                            self.customISOButton.backgroundColor = [UIColor systemBlueColor];
            [self.customISOButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        }
        [self.customISOButton setTitle:[NSString stringWithFormat:@"Custom: %@", [savedISO uppercaseString]] forState:UIControlStateNormal];
    }
    
    self.customISOButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.customISOButton.enabled = (networkDataSpoofEnabled && savedConnectionType == 2);
    [self.customISOButton addTarget:self action:@selector(showCustomISOPrompt) forControlEvents:UIControlEventTouchUpInside];
    
    // Add quick generate button with refresh icon
    self.quickGenerateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.quickGenerateButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        self.quickGenerateButton.backgroundColor = [UIColor systemGray5Color];
    } else {
        [self.quickGenerateButton setTitle:@"↻" forState:UIControlStateNormal]; // Fallback for older iOS
        self.quickGenerateButton.backgroundColor = [UIColor systemBackgroundColor];
    }
    self.quickGenerateButton.layer.cornerRadius = 4;
    self.quickGenerateButton.tintColor = [UIColor labelColor];
    self.quickGenerateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.quickGenerateButton.enabled = (networkDataSpoofEnabled && savedConnectionType == 2);
    [self.quickGenerateButton addTarget:self action:@selector(quickGenerateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Create a container for ISO options to center them together
    UIView *isoContainer = [[UIView alloc] init];
    isoContainer.translatesAutoresizingMaskIntoConstraints = NO;
    isoContainer.backgroundColor = [UIColor clearColor];
    [controlView.contentView addSubview:isoContainer];
    
    // Add the segmented control, custom button and generate button to the container
    [isoContainer addSubview:self.networkISOCountrySegment];
    [isoContainer addSubview:self.customISOButton];
    [isoContainer addSubview:self.quickGenerateButton];
    
    // Create local IP container for WiFi connection type
    self.localIPContainer = [[UIView alloc] init];
    self.localIPContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.localIPContainer.backgroundColor = [UIColor clearColor];
    [controlView.contentView addSubview:self.localIPContainer];
    
    // Create stack view for centered alignment
    UIView *localIPStack = [[UIView alloc] init];
    localIPStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.localIPContainer addSubview:localIPStack];
    
    // Create a vertical stack view for IP address fields
         UIStackView *ipVerticalStack = [[UIStackView alloc] init];
     ipVerticalStack.axis = UILayoutConstraintAxisVertical;
     ipVerticalStack.spacing = 15; // Increased spacing between IP rows
     ipVerticalStack.alignment = UIStackViewAlignmentLeading;
     ipVerticalStack.distribution = UIStackViewDistributionFill;
    ipVerticalStack.translatesAutoresizingMaskIntoConstraints = NO;
    [localIPStack addSubview:ipVerticalStack];
    
    // --- IPv6 ROW (FIRST) ---
    UIView *ipv6Row = [[UIView alloc] init];
    ipv6Row.translatesAutoresizingMaskIntoConstraints = NO;
    [ipVerticalStack addArrangedSubview:ipv6Row];
    
    // Create local IPv6 label
    UILabel *localIPv6Label = [[UILabel alloc] init];
    localIPv6Label.text = @"Local IP v6:";
    localIPv6Label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    localIPv6Label.translatesAutoresizingMaskIntoConstraints = NO;
    [ipv6Row addSubview:localIPv6Label];
    
    // Create local IPv6 field
    self.localIPv6Field = [[UITextField alloc] init];
    self.localIPv6Field.borderStyle = UITextBorderStyleRoundedRect;
    self.localIPv6Field.font = [UIFont systemFontOfSize:12];
    self.localIPv6Field.translatesAutoresizingMaskIntoConstraints = NO;
    self.localIPv6Field.placeholder = @"fe80::xxxx:xxxx:xxxx:xxxx";
    self.localIPv6Field.keyboardType = UIKeyboardTypeASCIICapable;
    self.localIPv6Field.returnKeyType = UIReturnKeyDone;
    self.localIPv6Field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.localIPv6Field.delegate = self;
    [self.localIPv6Field addTarget:self action:@selector(localIPv6FieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [ipv6Row addSubview:self.localIPv6Field];
    
    // Create generate button for local IPv6
    self.localIPv6GenerateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.localIPv6GenerateButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        self.localIPv6GenerateButton.backgroundColor = [UIColor systemGray5Color];
    } else {
        [self.localIPv6GenerateButton setTitle:@"↻" forState:UIControlStateNormal];
        self.localIPv6GenerateButton.backgroundColor = [UIColor systemBackgroundColor];
    }
    self.localIPv6GenerateButton.layer.cornerRadius = 4;
    self.localIPv6GenerateButton.tintColor = [UIColor labelColor];
    self.localIPv6GenerateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.localIPv6GenerateButton addTarget:self action:@selector(localIPv6GenerateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [ipv6Row addSubview:self.localIPv6GenerateButton];
    
    // --- IPv4 ROW (SECOND) ---
    UIView *ipv4Row = [[UIView alloc] init];
    ipv4Row.translatesAutoresizingMaskIntoConstraints = NO;
    [ipVerticalStack addArrangedSubview:ipv4Row];
    
    // Create local IP v4 label
    UILabel *localIPLabel = [[UILabel alloc] init];
    localIPLabel.text = @"Local IP v4:";
    localIPLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    localIPLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [ipv4Row addSubview:localIPLabel];
    
    // Create local IP field
    self.localIPField = [[UITextField alloc] init];
    self.localIPField.borderStyle = UITextBorderStyleRoundedRect;
    self.localIPField.font = [UIFont systemFontOfSize:12];
    self.localIPField.translatesAutoresizingMaskIntoConstraints = NO;
    self.localIPField.placeholder = @"192.168.x.y";
    self.localIPField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.localIPField.returnKeyType = UIReturnKeyDone;
    self.localIPField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.localIPField.delegate = self; // Set delegate to handle return key
    [self.localIPField addTarget:self action:@selector(localIPFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [ipv4Row addSubview:self.localIPField];
    
    // Create generate button for local IP
    self.localIPGenerateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.localIPGenerateButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        self.localIPGenerateButton.backgroundColor = [UIColor systemGray5Color];
    } else {
        [self.localIPGenerateButton setTitle:@"↻" forState:UIControlStateNormal]; // Fallback for older iOS
        self.localIPGenerateButton.backgroundColor = [UIColor systemBackgroundColor];
    }
    self.localIPGenerateButton.layer.cornerRadius = 4;
    self.localIPGenerateButton.tintColor = [UIColor labelColor];
    self.localIPGenerateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.localIPGenerateButton addTarget:self action:@selector(localIPGenerateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [ipv4Row addSubview:self.localIPGenerateButton];
    
    // Create carrier details container
    self.carrierDetailsContainer = [[UIView alloc] init];
    self.carrierDetailsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.carrierDetailsContainer.backgroundColor = [UIColor clearColor];
    [controlView.contentView addSubview:self.carrierDetailsContainer];
    
    // Create carrier name field with label
    UILabel *carrierNameLabel = [[UILabel alloc] init];
    carrierNameLabel.text = @"Carrier:";
    carrierNameLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    carrierNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.carrierDetailsContainer addSubview:carrierNameLabel];
    
    self.carrierNameField = [[UITextField alloc] init];
    self.carrierNameField.borderStyle = UITextBorderStyleRoundedRect;
    self.carrierNameField.font = [UIFont systemFontOfSize:12];
    self.carrierNameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.carrierNameField.placeholder = @"Carrier name";
    self.carrierNameField.returnKeyType = UIReturnKeyDone;
    self.carrierNameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.carrierNameField.delegate = self; // Set delegate to handle return key
    [self.carrierNameField addTarget:self action:@selector(carrierFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.carrierDetailsContainer addSubview:self.carrierNameField];
    
    // Create MCC field with label
    UILabel *mccLabel = [[UILabel alloc] init];
    mccLabel.text = @"MCC:";
    mccLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    mccLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.carrierDetailsContainer addSubview:mccLabel];
    
    self.mccField = [[UITextField alloc] init];
    self.mccField.borderStyle = UITextBorderStyleRoundedRect;
    self.mccField.font = [UIFont systemFontOfSize:12];
    self.mccField.translatesAutoresizingMaskIntoConstraints = NO;
    self.mccField.placeholder = @"MCC";
    self.mccField.keyboardType = UIKeyboardTypeNumberPad;
    self.mccField.returnKeyType = UIReturnKeyDone;
    self.mccField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.mccField.delegate = self; // Set delegate to handle return key
    [self.mccField addTarget:self action:@selector(carrierFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    // Add toolbar for number pad to dismiss keyboard
    [self addDoneButtonToNumberPad:self.mccField];
    [self.carrierDetailsContainer addSubview:self.mccField];
    
    // Create MNC field with label
    UILabel *mncLabel = [[UILabel alloc] init];
    mncLabel.text = @"MNC:";
    mncLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    mncLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.carrierDetailsContainer addSubview:mncLabel];
    
    self.mncField = [[UITextField alloc] init];
    self.mncField.borderStyle = UITextBorderStyleRoundedRect;
    self.mncField.font = [UIFont systemFontOfSize:12];
    self.mncField.translatesAutoresizingMaskIntoConstraints = NO;
    self.mncField.placeholder = @"MNC";
    self.mncField.keyboardType = UIKeyboardTypeNumberPad;
    self.mncField.returnKeyType = UIReturnKeyDone;
    self.mncField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.mncField.delegate = self; // Set delegate to handle return key
    [self.mncField addTarget:self action:@selector(carrierFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    // Add toolbar for number pad to dismiss keyboard
    [self addDoneButtonToNumberPad:self.mncField];
    [self.carrierDetailsContainer addSubview:self.mncField];
    
    // We're using the quick generate button instead of a separate one in the carrier details row
    
    // Position control under the network data spoof control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:100], // Position below Network Data Spoof control
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:200], // Increased height to accommodate carrier details and local IP
        
        // Position label at the top with info button beside it
        [self.networkConnectionTypeLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.networkConnectionTypeLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.networkConnectionTypeLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.networkConnectionTypeLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.networkConnectionTypeInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.networkConnectionTypeInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        // Position segmented control below the label, centered horizontally
        [self.networkConnectionTypeSegment.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [self.networkConnectionTypeSegment.topAnchor constraintEqualToAnchor:self.networkConnectionTypeLabel.bottomAnchor constant:15],
        [self.networkConnectionTypeSegment.widthAnchor constraintEqualToConstant:250], // Wider segmented control
        
        // Position ISO container below network connection type
        [isoContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [isoContainer.topAnchor constraintEqualToAnchor:self.networkConnectionTypeSegment.bottomAnchor constant:15],
        [isoContainer.heightAnchor constraintEqualToConstant:30],
        
        // Position elements inside container
        [self.networkISOCountrySegment.leadingAnchor constraintEqualToAnchor:isoContainer.leadingAnchor],
        [self.networkISOCountrySegment.centerYAnchor constraintEqualToAnchor:isoContainer.centerYAnchor],
        [self.networkISOCountrySegment.widthAnchor constraintEqualToConstant:120],
        
        [self.customISOButton.leadingAnchor constraintEqualToAnchor:self.networkISOCountrySegment.trailingAnchor constant:8],
        [self.customISOButton.centerYAnchor constraintEqualToAnchor:isoContainer.centerYAnchor],
        [self.customISOButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],
        [self.customISOButton.heightAnchor constraintEqualToConstant:30],
        
        // Position generate icon button next to custom button
        [self.quickGenerateButton.leadingAnchor constraintEqualToAnchor:self.customISOButton.trailingAnchor constant:8],
        [self.quickGenerateButton.centerYAnchor constraintEqualToAnchor:isoContainer.centerYAnchor],
        [self.quickGenerateButton.trailingAnchor constraintEqualToAnchor:isoContainer.trailingAnchor],
        [self.quickGenerateButton.widthAnchor constraintEqualToConstant:36],
        [self.quickGenerateButton.heightAnchor constraintEqualToConstant:30],
        
        // Position carrier details container below ISO container
        [self.carrierDetailsContainer.topAnchor constraintEqualToAnchor:isoContainer.bottomAnchor constant:10],
        [self.carrierDetailsContainer.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.carrierDetailsContainer.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.carrierDetailsContainer.heightAnchor constraintEqualToConstant:30],
        
        // Position local IP container just below the WiFi segmented control
        [self.localIPContainer.topAnchor constraintEqualToAnchor:self.networkConnectionTypeSegment.bottomAnchor constant:22],
        [self.localIPContainer.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.localIPContainer.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.localIPContainer.heightAnchor constraintEqualToConstant:85], // Increased height for two rows with spacing
        
        // Position carrier name label and field
        [carrierNameLabel.leadingAnchor constraintEqualToAnchor:self.carrierDetailsContainer.leadingAnchor],
        [carrierNameLabel.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [carrierNameLabel.widthAnchor constraintEqualToConstant:45],
        
        [self.carrierNameField.leadingAnchor constraintEqualToAnchor:carrierNameLabel.trailingAnchor constant:5],
        [self.carrierNameField.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [self.carrierNameField.widthAnchor constraintEqualToConstant:80],
        [self.carrierNameField.heightAnchor constraintEqualToConstant:25],
        
        // Position MCC label and field
        [mccLabel.leadingAnchor constraintEqualToAnchor:self.carrierNameField.trailingAnchor constant:8],
        [mccLabel.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [mccLabel.widthAnchor constraintEqualToConstant:35],
        
        [self.mccField.leadingAnchor constraintEqualToAnchor:mccLabel.trailingAnchor constant:2],
        [self.mccField.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [self.mccField.widthAnchor constraintEqualToConstant:40],
        [self.mccField.heightAnchor constraintEqualToConstant:25],
        
        // Position MNC label and field
        [mncLabel.leadingAnchor constraintEqualToAnchor:self.mccField.trailingAnchor constant:8],
        [mncLabel.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [mncLabel.widthAnchor constraintEqualToConstant:35],
        
        [self.mncField.leadingAnchor constraintEqualToAnchor:mncLabel.trailingAnchor constant:2],
        [self.mncField.centerYAnchor constraintEqualToAnchor:self.carrierDetailsContainer.centerYAnchor],
        [self.mncField.trailingAnchor constraintLessThanOrEqualToAnchor:self.carrierDetailsContainer.trailingAnchor constant:-10],
        [self.mncField.widthAnchor constraintEqualToConstant:40],
        [self.mncField.heightAnchor constraintEqualToConstant:25],
        
        // Position the vertical stack for local IP elements
        [localIPStack.leadingAnchor constraintEqualToAnchor:self.localIPContainer.leadingAnchor],
        [localIPStack.topAnchor constraintEqualToAnchor:self.localIPContainer.topAnchor constant:5], // Add slight top margin
        [localIPStack.trailingAnchor constraintEqualToAnchor:self.localIPContainer.trailingAnchor],
        [localIPStack.bottomAnchor constraintEqualToAnchor:self.localIPContainer.bottomAnchor],
        
        // Position the IP vertical stack inside the localIPStack
        [ipVerticalStack.leadingAnchor constraintEqualToAnchor:localIPStack.leadingAnchor],
        [ipVerticalStack.topAnchor constraintEqualToAnchor:localIPStack.topAnchor],
        [ipVerticalStack.trailingAnchor constraintEqualToAnchor:localIPStack.trailingAnchor],
        [ipVerticalStack.bottomAnchor constraintEqualToAnchor:localIPStack.bottomAnchor],
        
        // IPv6 row constraints
        [ipv6Row.heightAnchor constraintEqualToConstant:30],
        [ipv6Row.leadingAnchor constraintEqualToAnchor:ipVerticalStack.leadingAnchor],
        [ipv6Row.trailingAnchor constraintEqualToAnchor:ipVerticalStack.trailingAnchor],
        
        // IPv4 row constraints
        [ipv4Row.heightAnchor constraintEqualToConstant:30],
        [ipv4Row.leadingAnchor constraintEqualToAnchor:ipVerticalStack.leadingAnchor],
        [ipv4Row.trailingAnchor constraintEqualToAnchor:ipVerticalStack.trailingAnchor],
        
        // IPv6 elements
        [localIPv6Label.leadingAnchor constraintEqualToAnchor:ipv6Row.leadingAnchor],
        [localIPv6Label.centerYAnchor constraintEqualToAnchor:ipv6Row.centerYAnchor],
        [localIPv6Label.widthAnchor constraintEqualToConstant:80],
        
        [self.localIPv6Field.leadingAnchor constraintEqualToAnchor:localIPv6Label.trailingAnchor constant:5],
        [self.localIPv6Field.centerYAnchor constraintEqualToAnchor:ipv6Row.centerYAnchor],
        [self.localIPv6Field.widthAnchor constraintEqualToConstant:160],
        [self.localIPv6Field.heightAnchor constraintEqualToConstant:25],
        
        [self.localIPv6GenerateButton.leadingAnchor constraintEqualToAnchor:self.localIPv6Field.trailingAnchor constant:10],
        [self.localIPv6GenerateButton.centerYAnchor constraintEqualToAnchor:ipv6Row.centerYAnchor],
        [self.localIPv6GenerateButton.widthAnchor constraintEqualToConstant:36],
        [self.localIPv6GenerateButton.heightAnchor constraintEqualToConstant:30],
        
        // IPv4 elements
        [localIPLabel.leadingAnchor constraintEqualToAnchor:ipv4Row.leadingAnchor],
        [localIPLabel.centerYAnchor constraintEqualToAnchor:ipv4Row.centerYAnchor],
        [localIPLabel.widthAnchor constraintEqualToConstant:80],
        
        [self.localIPField.leadingAnchor constraintEqualToAnchor:localIPLabel.trailingAnchor constant:5],
        [self.localIPField.centerYAnchor constraintEqualToAnchor:ipv4Row.centerYAnchor],
        [self.localIPField.widthAnchor constraintEqualToConstant:160],
        [self.localIPField.heightAnchor constraintEqualToConstant:25],
        
        [self.localIPGenerateButton.leadingAnchor constraintEqualToAnchor:self.localIPField.trailingAnchor constant:10],
        [self.localIPGenerateButton.centerYAnchor constraintEqualToAnchor:ipv4Row.centerYAnchor],
        [self.localIPGenerateButton.widthAnchor constraintEqualToConstant:36],
        [self.localIPGenerateButton.heightAnchor constraintEqualToConstant:30]
    ]];

    // Show/hide ISO segment based on selection
    if (!self.networkISOCountrySegment) return;
    BOOL showISO = (savedConnectionType == 2);
    BOOL showLocalIP = (savedConnectionType == 1);
    
    self.networkISOCountrySegment.hidden = !showISO;
    self.networkISOCountrySegment.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    
    // Also show/hide the custom ISO button
    if (self.customISOButton) {
        self.customISOButton.hidden = !showISO;
        self.customISOButton.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    }
    
    // Show/hide the quick generate button
    if (self.quickGenerateButton) {
        self.quickGenerateButton.hidden = !showISO;
        self.quickGenerateButton.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    }
    
    // Show/hide the container
    isoContainer.hidden = !showISO;
    
    // Show/hide carrier details container
    self.carrierDetailsContainer.hidden = !showISO;
    
    // Show/hide local IP container based on WiFi selection
    self.localIPContainer.hidden = !showLocalIP;
    
    // Load saved carrier values or generate new ones
    if (showISO) {
        // Get saved carrier details from profile-based storage
        NSDictionary *carrierDetails = [NetworkManager getSavedCarrierDetails];
        
        if (carrierDetails) {
            self.carrierNameField.text = carrierDetails[@"name"];
            self.mccField.text = carrierDetails[@"mcc"];
            self.mncField.text = carrierDetails[@"mnc"];
        } else {
            // If for some reason we couldn't get carrier details, generate new ones
            [self updateCarrierDetailsForCountry:savedISO];
        }
        
        // Enable fields only for custom country
        BOOL isCustomCountry = ![savedISO isEqualToString:@"us"] && 
                               ![savedISO isEqualToString:@"in"] && 
                               ![savedISO isEqualToString:@"ca"];
        
        self.carrierNameField.enabled = isCustomCountry;
        self.mccField.enabled = isCustomCountry;
        self.mncField.enabled = isCustomCountry;
    }
    
    // Load saved local IP or generate one if WiFi is selected
    if (showLocalIP) {
        NSString *savedLocalIPv6 = [NetworkManager getSavedLocalIPv6Address];
        self.localIPv6Field.text = savedLocalIPv6;
        
        NSString *savedLocalIP = [NetworkManager getSavedLocalIPAddress];
        self.localIPField.text = savedLocalIP;
    }

    // No longer needed - moved to the vertical stack layout above

    // Methods for field change and generate button have been moved to top-level
    // No nested methods here
}



- (void)networkDataSpoofToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // 1. Update plist file - THE SOURCE OF TRUTH
    NSString *securitySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
    NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
    settingsDict[@"networkDataSpoofEnabled"] = @(enabled);
    
    // Ensure the plist is written atomically and with proper permissions
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:settingsDict
                                                                  format:NSPropertyListXMLFormat_v1_0
                                                                 options:0
                                                                   error:nil];
    if (plistData) {
        [plistData writeToFile:securitySettingsPath atomically:YES];
    }
    
    // 2. Update NSUserDefaults in all suites to ensure consistency
    NSArray *suiteNames = @[
        @"com.weaponx.securitySettings",
        @"com.hydra.projectx.SecuritySettings",
        @"com.hydra.projectx"
    ];
    
    for (NSString *suiteName in suiteNames) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults setBool:enabled forKey:@"networkDataSpoofEnabled"];
        [defaults synchronize];
    }
    
    // 3. Update UI
    UIView *connectionTypeView = [self.view viewWithTag:1001];
    if (connectionTypeView) {
        connectionTypeView.alpha = enabled ? 0.8 : 0.4;
        self.networkConnectionTypeSegment.enabled = enabled;
    }
    
    // 4. Send notifications with enhanced information
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(enabled) forKey:@"enabled"];
    [userInfo setObject:@"SecurityTabView" forKey:@"sender"];
    [userInfo setObject:[NSDate date] forKey:@"timestamp"];
    [userInfo setObject:@YES forKey:@"forceReload"];
    [userInfo setObject:securitySettingsPath forKey:@"settingsPath"];
    
    // Post notification immediately on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.toggleNetworkDataSpoof" 
                                                            object:nil 
                                                          userInfo:userInfo];
    });
    
    // Send Darwin notification with enhanced information
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    NSString *notificationName = enabled ? @"com.hydra.projectx.enableNetworkDataSpoof" : @"com.hydra.projectx.disableNetworkDataSpoof";
    CFNotificationCenterPostNotification(darwinCenter, (__bridge CFStringRef)notificationName, NULL, NULL, YES);
    
    // Also send a generic change notification
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkDataSpoofChanged"), NULL, NULL, YES);
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    // Log the change
    PXLog(@"[SecurityTab] 🔄 Network data spoof %@: Settings updated in plist and all NSUserDefaults suites", 
          enabled ? @"ENABLED" : @"DISABLED");
}


- (void)showNetworkDataSpoofInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Network Data Spoof"
                               message:@"Spoofs network data statistics including total data received and sent for both WiFi and cellular connections. This helps maintain privacy by preventing apps from tracking your actual network usage."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showNetworkConnectionTypeInfo {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Network Connection Type"
                                                                             message:@"Select how apps should see your network connection:\n\n• Auto - Randomly switches between WiFi and Cellular based on profile settings\n• WiFi - Always shows as connected via WiFi\n• Cellular - Always shows as connected via Cellular data\n• None - Never shows any network connection\n\nThis setting only works when Network Data Spoof is enabled."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:okAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)networkISOCountryChanged:(UISegmentedControl *)sender {
    // Save ISO code to user defaults (keeping this in user defaults as it's a UI preference, not device identity)
    NSString *selectedISO = @"us";
    switch (sender.selectedSegmentIndex) {
        case 0: selectedISO = @"us"; break;
        case 1: selectedISO = @"in"; break;
        case 2: selectedISO = @"ca"; break;
        default: {
            // If no segment is selected, keep the existing custom code
            selectedISO = [self.securitySettings stringForKey:@"networkISOCountryCode"] ?: @"us";
            // But don't allow going back to "no selection" without a valid code
            if ([selectedISO isEqualToString:@"us"] || [selectedISO isEqualToString:@"in"] || [selectedISO isEqualToString:@"ca"]) {
                selectedISO = @"us"; // Default to US
                sender.selectedSegmentIndex = 0;
            }
            break;
        }
    }
    
    [self.securitySettings setObject:selectedISO forKey:@"networkISOCountryCode"];
    [self.securitySettings synchronize];
    
    // Reset the custom button style if a standard option is selected
    if (sender.selectedSegmentIndex >= 0) {
        [self.customISOButton setTitle:@"Custom" forState:UIControlStateNormal];
        [self.customISOButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        
        if (@available(iOS 13.0, *)) {
            self.customISOButton.backgroundColor = [UIColor systemGray5Color];
        } else {
            self.customISOButton.backgroundColor = [UIColor systemBackgroundColor];
        }
    }
    
    // Update carrier details for the selected country
    [self updateCarrierDetailsForCountry:selectedISO];
    
    // Log the change
    PXLog(@"[SecurityTab] ISO Country Code changed to: %@ (index: %ld)", selectedISO, (long)sender.selectedSegmentIndex);
    
    // Send notification for updates
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkISOCountryCodeChanged"), NULL, NULL, YES);
    
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)networkConnectionTypeChanged:(UISegmentedControl *)sender {
    NSInteger selectedType = sender.selectedSegmentIndex;
    
    // Save setting immediately and synchronize
    [self.securitySettings setInteger:selectedType forKey:@"networkConnectionType"];
    [self.securitySettings synchronize];
    
    // Get type name for logging
    NSArray *typeNames = @[@"Auto", @"WiFi", @"Cellular", @"None"];
    NSString *typeName = typeNames[selectedType];
    
    PXLog(@"[SecurityTab] Network connection type changed to: %@ (index: %ld)", typeName, (long)selectedType);
    
    // Post Darwin notification to update all processes
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkConnectionTypeChanged"), NULL, NULL, YES);
    
    // Add message explaining the change
    NSString *message = @"";
    switch (selectedType) {
        case 0: // Auto
            message = @"Apps will see WiFi or Cellular randomly based on profile settings";
            break;
        case 1: // WiFi
            message = @"Apps will always see WiFi connection";
            break;
        case 2: // Cellular
            message = @"Apps will always see Cellular connection";
            break;
        case 3: // None
            message = @"Apps will see no network connection";
            break;
    }
    
    // Show/hide ISO country code segment based on selection
    if (!self.networkISOCountrySegment) return;
    BOOL showISO = (selectedType == 2);
    self.networkISOCountrySegment.hidden = !showISO;
    self.networkISOCountrySegment.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    
    // Also show/hide the custom ISO button
    if (self.customISOButton) {
        self.customISOButton.hidden = !showISO;
        self.customISOButton.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    }
    
    // Also show/hide the quick generate button
    if (self.quickGenerateButton) {
        self.quickGenerateButton.hidden = !showISO;
        self.quickGenerateButton.enabled = (self.networkConnectionTypeSegment.enabled && showISO);
    }
    
    // Also show/hide the ISO container
    UIView *isoContainer = self.networkISOCountrySegment.superview;
    if (isoContainer != self.networkConnectionTypeSegment.superview) {
        isoContainer.hidden = !showISO;
    }
    
    // Show/hide the carrier details container
    if (self.carrierDetailsContainer) {
        self.carrierDetailsContainer.hidden = !showISO;
    }
    
    // Show/hide the local IP container for WiFi connection type
    if (self.localIPContainer) {
        BOOL showLocalIP = (selectedType == 1); // Show for WiFi (index 1)
        self.localIPContainer.hidden = !showLocalIP;
        
        // If WiFi is selected, initialize the local IP field with real IP or saved value
        if (showLocalIP) {
            // Get the saved local IP from the profile-based storage
            NSString *savedLocalIP = [NetworkManager getSavedLocalIPAddress];
            self.localIPField.text = savedLocalIP;
        }
    }

    // Show feedback toast
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        // Cast to the right type to avoid incompatible pointer types warning
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
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
    } else {
        // Suppress deprecation warning for iOS 12 and below
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    
    if (keyWindow) {
        UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil
                                                                       message:[NSString stringWithFormat:@"Network Connection Type: %@\n%@", typeName, message]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [self presentViewController:toast animated:YES completion:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [toast dismissViewControllerAnimated:YES completion:nil];
        });
    }
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
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


// Add new method to handle custom ISO code input
- (void)showCustomISOPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom ISO Country Code"
                                                                   message:@"Enter a two-letter ISO country code (e.g., GB, DE, JP)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"ISO Code (2 letters)";
        textField.text = [self.securitySettings stringForKey:@"networkISOCountryCode"] ?: @"";
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.returnKeyType = UIReturnKeyDone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *isoCode = [textField.text stringByReplacingOccurrencesOfString:@" " withString:@""];
        isoCode = [isoCode lowercaseString];
        
        // Validate ISO code format (2 letters)
        if (isoCode.length == 2 && [self isValidISOCountryCode:isoCode]) {
            // Deselect any selected segment
            [self.networkISOCountrySegment setSelectedSegmentIndex:UISegmentedControlNoSegment];
            
            // Save to user defaults
            [self.securitySettings setObject:isoCode forKey:@"networkISOCountryCode"];
            [self.securitySettings synchronize];
            
            // Update custom button title
            [self.customISOButton setTitle:[NSString stringWithFormat:@"Custom: %@", [isoCode uppercaseString]] forState:UIControlStateNormal];
            
            // Highlight the custom button like selected segment
            if (@available(iOS 13.0, *)) {
                self.customISOButton.backgroundColor = [UIColor systemBlueColor];
                [self.customISOButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            } else {
                self.customISOButton.backgroundColor = [UIColor systemBlueColor];
                [self.customISOButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            }
            
            // Update carrier details for custom country
            [self updateCarrierDetailsForCountry:isoCode];
            
            // Log the change
            PXLog(@"[SecurityTab] ISO Country Code changed to custom value: %@", isoCode);
            
            // Send notification for updates
            CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkISOCountryCodeChanged"), NULL, NULL, YES);
            
            // Add haptic feedback
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
        } else {
            // Show error for invalid ISO code
            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Invalid ISO Code"
                                                                               message:@"Please enter a valid two-letter ISO country code (e.g., GB, DE, JP)"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // Re-show the input prompt after dismissing the error
                [self showCustomISOPrompt];
            }]];
            
            [self presentViewController:errorAlert animated:YES completion:nil];
        }
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:saveAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Helper method to validate ISO country code
- (BOOL)isValidISOCountryCode:(NSString *)code {
    // Simple validation - must be 2 letters
    if (code.length != 2) return NO;
    
    // Check if all characters are letters
    NSCharacterSet *nonLetterSet = [[NSCharacterSet letterCharacterSet] invertedSet];
    return ([code rangeOfCharacterFromSet:nonLetterSet].location == NSNotFound);
}

// Add method to generate carrier info based on country code
- (NSDictionary *)generateCarrierInfoForCountry:(NSString *)countryCode {
    // Use the NetworkManager class to get a random carrier for the country
    return [NetworkManager getRandomCarrierForCountry:countryCode];
}

// Method to update the carrier details UI fields
- (void)updateCarrierDetailsForCountry:(NSString *)countryCode {
    if (!self.carrierNameField || !self.mccField || !self.mncField) {
        return;
    }
    
    // Generate information for the country
    NSDictionary *carrierInfo = [self generateCarrierInfoForCountry:countryCode];
    
    // Update UI
    self.carrierNameField.text = carrierInfo[@"name"];
    self.mccField.text = carrierInfo[@"mcc"];
    self.mncField.text = carrierInfo[@"mnc"];
    
    // Save values to profile-based storage
    [NetworkManager saveCarrierDetails:carrierInfo[@"name"] 
                                   mcc:carrierInfo[@"mcc"] 
                                   mnc:carrierInfo[@"mnc"]];
    
    // Enable editing only for custom country codes
    BOOL isCustomCountry = ![countryCode isEqualToString:@"us"] && 
                           ![countryCode isEqualToString:@"in"] && 
                           ![countryCode isEqualToString:@"ca"];
    
    self.carrierNameField.enabled = isCustomCountry;
    self.mccField.enabled = isCustomCountry;
    self.mncField.enabled = isCustomCountry;
}

// Add methods to handle carrier field changes
- (void)carrierFieldChanged:(UITextField *)textField {
    // Get current values from fields
    NSString *carrierName = self.carrierNameField.text;
    NSString *mcc = self.mccField.text;
    NSString *mnc = self.mncField.text;
    
    // Save changes to profile-based storage
    [NetworkManager saveCarrierDetails:carrierName mcc:mcc mnc:mnc];
    
    // Send notification that carrier details changed
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.carrierDetailsChanged"), NULL, NULL, YES);
}

// Add method to handle generate button tap
- (void)generateCarrierButtonTapped:(UIButton *)sender {
    // Get the current country code
    NSString *countryCode = [self.securitySettings stringForKey:@"networkISOCountryCode"] ?: @"us";
    
    // Generate new carrier details
    [self updateCarrierDetailsForCountry:countryCode];
    
    // Show feedback toast
    [self showToastWithMessage:[NSString stringWithFormat:@"Generated carrier details for %@", [countryCode uppercaseString]]];
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

// Add method for quick generate button tap
- (void)quickGenerateButtonTapped:(UIButton *)sender {
    // Get the current country code
    NSString *countryCode = [self.securitySettings stringForKey:@"networkISOCountryCode"] ?: @"us";
    
    // Generate new carrier details
    [self updateCarrierDetailsForCountry:countryCode];
    
         // Add visual feedback - briefly highlight the button
     UIColor *originalColor = sender.backgroundColor;
     [UIView animateWithDuration:0.1 animations:^{
         sender.backgroundColor = [UIColor systemBlueColor];
         sender.tintColor = [UIColor whiteColor];
     } completion:^(BOOL finished) {
         [UIView animateWithDuration:0.2 animations:^{
             sender.backgroundColor = originalColor;
             sender.tintColor = [UIColor labelColor];
         }];
     }];
    
    // Show toast with generated carrier info
    NSString *carrierInfo = [NSString stringWithFormat:@"Generated: %@ (%@-%@)", 
                             self.carrierNameField.text,
                             self.mccField.text,
                             self.mncField.text];
    [self showToastWithMessage:carrierInfo];
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

// Method to generate a random local IP address
- (NSString *)generateRandomLocalIP {
    return [NetworkManager generateSpoofedLocalIPAddressFromCurrent];
}

// Method to get the device's current local IP address
- (NSString *)getCurrentLocalIP {
    return [NetworkManager getCurrentLocalIPAddress];
}

// Method to handle local IP generation button tap
- (void)localIPGenerateButtonTapped:(UIButton *)sender {
    // Generate a new random local IP
    NSString *newIP = [self generateRandomLocalIP];
    self.localIPField.text = newIP;
    
    // Save to profile-based storage
    [NetworkManager saveLocalIPAddress:newIP];
    
    // Add visual feedback - briefly highlight the button
    UIColor *originalColor = sender.backgroundColor;
    [UIView animateWithDuration:0.1 animations:^{
        sender.backgroundColor = [UIColor systemBlueColor];
        sender.tintColor = [UIColor whiteColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = originalColor;
            sender.tintColor = [UIColor labelColor];
        }];
    }];
    
    // Show toast with generated IP
    [self showToastWithMessage:[NSString stringWithFormat:@"Generated local IP: %@", newIP]];
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

// Method to handle local IP field changes
- (void)localIPFieldChanged:(UITextField *)textField {
    // Save changes to profile-based storage
    [NetworkManager saveLocalIPAddress:textField.text];
    
    // Send notification that local IP has changed
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.localIPChanged"), NULL, NULL, YES);
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

- (void)localIPv6FieldChanged:(UITextField *)textField {
    // Save changes to profile-based storage
    NSString *ipv4 = self.localIPField.text;
    [NetworkManager saveLocalIPAddress:ipv4]; // This will also update IPv6
    // Send notification that local IP has changed
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.localIPChanged"), NULL, NULL, YES);
}

- (void)localIPv6GenerateButtonTapped:(UIButton *)sender {
    // Generate a new spoofed IPv6
    NSString *newIPv6 = [NetworkManager generateSpoofedLocalIPv6AddressFromCurrent];
    self.localIPv6Field.text = newIPv6;
    // Save to profile-based storage (by saving IPv4, which triggers IPv6 save)
    NSString *ipv4 = self.localIPField.text;
    [NetworkManager saveLocalIPAddress:ipv4];
    // Add visual feedback
    UIColor *originalColor = sender.backgroundColor;
    [UIView animateWithDuration:0.1 animations:^{
        sender.backgroundColor = [UIColor systemBlueColor];
        sender.tintColor = [UIColor whiteColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = originalColor;
            sender.tintColor = [UIColor labelColor];
        }];
    }];
    // Show toast
    [self showToastWithMessage:[NSString stringWithFormat:@"Generated local IPv6: %@", newIPv6]];
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

@end