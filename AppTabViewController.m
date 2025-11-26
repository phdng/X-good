#import "AppTabViewController.h"
@interface AppTabViewController () 
    @property (nonatomic, strong) UITextField *bundleIDTextField;
    @property (nonatomic, strong) UITableView *appsTableView;
    @property (nonatomic, strong) UIViewController *installedAppsPopupVC;
    @property (nonatomic, strong) UITableView *installedAppsTableView;
    @property (nonatomic, strong) UISearchBar *appSearchBar;
    @property (nonatomic, strong) NSArray *installedApps;
    @property (nonatomic, strong) NSArray *filteredApps;
    @property (nonatomic, strong) NSCache *iconCache;
    @property (nonatomic, strong) NSArray *scopedApps;
    @property (nonatomic, strong) UIStackView *appsStackView;
    @property (nonatomic, strong) NSMutableDictionary *appSwitches;
    @property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

@end
@implementation AppTabViewController
- (instancetype)init {
    self = [super init];
    if (self) {
        self.iconCache = [[NSCache alloc] init];
        self.iconCache.countLimit = 50; // Cache up to 50 icons
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.appSwitches = [NSMutableDictionary dictionary];
    [self setupUI];
}

- (void)setupUI {
    // Create apps stack view
    self.appsStackView = [[UIStackView alloc] init];
    self.appsStackView.axis = UILayoutConstraintAxisVertical;
    self.appsStackView.spacing = 12;
    self.appsStackView.alignment = UIStackViewAlignmentFill;
    self.appsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.appsStackView];
    
    // Add bundle ID input field and buttons container
    UIStackView *inputStack = [[UIStackView alloc] init];
    inputStack.axis = UILayoutConstraintAxisHorizontal;
    inputStack.spacing = 8;
    inputStack.alignment = UIStackViewAlignmentCenter;
    inputStack.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);
    inputStack.layoutMarginsRelativeArrangement = YES;
    
    // Create container view for text field to control its size
    UIView *textFieldContainer = [[UIView alloc] init];
    textFieldContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.bundleIDTextField = [[UITextField alloc] init];
    self.bundleIDTextField.placeholder = @"Enter Bundle ID";
    self.bundleIDTextField.font = [UIFont systemFontOfSize:16];
    self.bundleIDTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.bundleIDTextField.delegate = self;
    self.bundleIDTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [textFieldContainer addSubview:self.bundleIDTextField];
    
    // Set fixed height and width for text field container
    [NSLayoutConstraint activateConstraints:@[
        [textFieldContainer.heightAnchor constraintEqualToConstant:36],
        [textFieldContainer.widthAnchor constraintEqualToConstant:200],  // Fixed width
        [self.bundleIDTextField.topAnchor constraintEqualToAnchor:textFieldContainer.topAnchor],
        [self.bundleIDTextField.bottomAnchor constraintEqualToAnchor:textFieldContainer.bottomAnchor],
        [self.bundleIDTextField.leadingAnchor constraintEqualToAnchor:textFieldContainer.leadingAnchor],
        [self.bundleIDTextField.trailingAnchor constraintEqualToAnchor:textFieldContainer.trailingAnchor]
    ]];
    
    [inputStack addArrangedSubview:textFieldContainer];
    
    // Create buttons stack
    UIStackView *buttonsStack = [[UIStackView alloc] init];
    buttonsStack.axis = UILayoutConstraintAxisHorizontal;
    buttonsStack.spacing = 12;  // Increased spacing between buttons
    buttonsStack.alignment = UIStackViewAlignmentCenter;
    
    // Add installed apps button (plus button)
    UIButton *installedAppsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [installedAppsButton setImage:[UIImage systemImageNamed:@"plus.diamond.fill"] forState:UIControlStateNormal];
    [installedAppsButton addTarget:self action:@selector(addAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [installedAppsButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack addArrangedSubview:installedAppsButton];
    
    // Add App button
    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *addButtonConfig = [UIButtonConfiguration plainButtonConfiguration];
    addButtonConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 6, 4, 6);
    addButtonConfig.title = @"Add App";
    addButtonConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    addButtonConfig.background.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
    addButtonConfig.baseForegroundColor = [UIColor systemGreenColor];
    addButton.configuration = addButtonConfig;
    addButton.layer.cornerRadius = 10;
    addButton.clipsToBounds = YES;
    addButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [addButton addTarget:self action:@selector(showInstalledAppsPopup:) forControlEvents:UIControlEventTouchUpInside];
    [addButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack addArrangedSubview:addButton];
    
    [inputStack addArrangedSubview:buttonsStack];
    
    // Set content hugging and compression resistance for the container
    [textFieldContainer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [textFieldContainer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    
    // Set content hugging and compression resistance for buttons stack
    [buttonsStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    
    // Add input stack to apps stack view
    [self.appsStackView addArrangedSubview:inputStack];
    
    // Add constraints for appsStackView
    [NSLayoutConstraint activateConstraints:@[
        [self.appsStackView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.appsStackView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.appsStackView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.appsStackView.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]
    ]];
}



@end 