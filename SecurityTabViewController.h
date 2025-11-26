#import "UIKit/UIKit.h"


@interface SecurityCardView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, copy) NSString *featureKey;
@property (nonatomic, copy) NSString *featureDescription;
@end

@interface SecurityTabViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>


- (void)presentIPStatusPage;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *securityCards;
@property (nonatomic, strong) NSUserDefaults *securitySettings;



// Network data spoof control
@property (nonatomic, strong) UILabel *networkDataSpoofLabel;
@property (nonatomic, strong) UISwitch *networkDataSpoofToggleSwitch;
@property (nonatomic, strong) UIButton *networkDataSpoofInfoButton;

// Network connection type control
@property (nonatomic, strong) UILabel *networkConnectionTypeLabel;
@property (nonatomic, strong) UISegmentedControl *networkConnectionTypeSegment;
@property (nonatomic, strong) UISegmentedControl *networkISOCountrySegment;
@property (nonatomic, strong) UIButton *networkConnectionTypeInfoButton;
@property (nonatomic, strong) UIButton *customISOButton;
@property (nonatomic, strong) UIButton *quickGenerateButton;

// Canvas fingerprinting protection control
@property (nonatomic, strong) UILabel *canvasFingerprintingLabel;
@property (nonatomic, strong) UISwitch *canvasFingerprintingToggleSwitch;
@property (nonatomic, strong) UIButton *canvasFingerprintingInfoButton;
@property (nonatomic, strong) UIButton *canvasFingerprintingResetButton;


// Carrier details properties
@property (nonatomic, strong) UITextField *carrierNameField;
@property (nonatomic, strong) UITextField *mccField;
@property (nonatomic, strong) UITextField *mncField;
@property (nonatomic, strong) UIView *carrierDetailsContainer;

// WiFi local IP address
@property (nonatomic, strong) UIView *localIPContainer;
@property (nonatomic, strong) UITextField *localIPField;
@property (nonatomic, strong) UIButton *localIPGenerateButton;

// Private methods

- (void)setupNetworkDataSpoofControl:(UIView *)contentView;
- (void)setupNetworkConnectionTypeControl:(UIView *)contentView;
- (void)setupCanvasFingerprintingControl:(UIView *)contentView;
- (void)setupAlertChecksSection:(UIView *)contentView;

@end