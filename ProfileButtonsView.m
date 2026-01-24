#import "ProfileButtonsView.h"
#import "common/UIButton+SafeConfiguration.h"

@interface ProfileButtonsView ()

@property (nonatomic, strong) UIButton *addProfileButton;
@property (nonatomic, strong) UIButton *manageProfilesButton;
@property (nonatomic, strong) UIStackView *buttonStack;

@end

@implementation ProfileButtonsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupButtons];
    }
    return self;
}

- (void)setupButtons {
    // Create container view
    self.backgroundColor = [UIColor clearColor];
    
    // Create stack view for buttons
    self.buttonStack = [[UIStackView alloc] init];
    self.buttonStack.axis = UILayoutConstraintAxisVertical;
    self.buttonStack.spacing = 10;
    self.buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.buttonStack];
    
    // Create buttons
    self.addProfileButton = [self createButtonWithIcon:@"plus.circle.fill" title:@"New"];
    self.manageProfilesButton = [self createButtonWithIcon:@"folder.fill" title:@"Profiles"];
    
    // Add buttons to stack
    [self.buttonStack addArrangedSubview:self.addProfileButton];
    [self.buttonStack addArrangedSubview:self.manageProfilesButton];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.buttonStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.buttonStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.buttonStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (UIButton *)createButtonWithIcon:(NSString *)iconName title:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if ([UIButton buttonConfigurationClassExists]) {
        if ([button supportsConfiguration]) {
            // iOS 15+ - Use modern UIButtonConfiguration
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            
            // Configure background
            config.background.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.5];
            config.background.cornerRadius = 22;
            
            // Configure image and text
            UIImage *icon = [UIImage systemImageNamed:iconName];
            config.image = icon;
            config.title = title;
            config.imagePlacement = NSDirectionalRectEdgeTop;
            config.imagePadding = 8;
            
            // Configure text attributes
            UIFont *font = [UIFont systemFontOfSize:8 weight:UIFontWeightMedium];
            NSDictionary *attributeDict = @{NSFontAttributeName: font};
            NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:attributeDict];
            config.attributedTitle = attributedTitle;
            
            // Set colors
            config.baseForegroundColor = [UIColor systemBlueColor];
            
            // Apply configuration safely
            [button safeSetConfiguration:config];
        } else {
            // iOS 15 but configuration not available - use fallback
            [self applyFallbackStyleToButton:button iconName:iconName title:title];
        }
    } else {
        // iOS 12-14 fallback - apply style to existing button
        [self applyFallbackStyleToButton:button iconName:iconName title:title];
    }
    
    button.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add targets
    if ([title isEqualToString:@"New"]) {
        [button addTarget:self action:@selector(newProfileTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        [button addTarget:self action:@selector(manageProfilesTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    
    // Set size constraints
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:45],
        [button.heightAnchor constraintEqualToConstant:45]
    ]];
    
    return button;
}

#pragma mark - Helper Methods

- (void)applyFallbackStyleToButton:(UIButton *)button iconName:(NSString *)iconName title:(NSString *)title {
    [button setTitle:title forState:UIControlStateNormal];
    [button setTintColor:[UIColor systemBlueColor]];
    button.titleLabel.font = [UIFont systemFontOfSize:8 weight:UIFontWeightMedium];
    
    // Set image for iOS 13+
    if (@available(iOS 13.0, *)) {
        UIImage *icon = [UIImage systemImageNamed:iconName];
        [button setImage:icon forState:UIControlStateNormal];
    }
    
    // Style the button
    button.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.5];
    button.layer.cornerRadius = 22;
    button.clipsToBounds = YES;
}

#pragma mark - Button Actions

- (void)newProfileTapped {
    if (self.onNewProfileTapped) {
        self.onNewProfileTapped();
    }
}

- (void)manageProfilesTapped {
    if (self.onManageProfilesTapped) {
        self.onManageProfilesTapped();
    }
}

@end 