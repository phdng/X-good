#import "SecurityTabViewController.h"
#import "FixVersionAppsViewController.h"
#import "ProjectXLogging.h"
#import "IdentifierManager.h"
#import "AppVersionSpoofingViewController.h"
#import "DeviceSpecificSpoofingViewController.h"
#import "IPStatusViewController.h"
#import "IPMonitorService.h"
#import "LocationSpoofingManager.h"
#import "NetworkManager.h"
#import "IPStatusCacheManager.h" // Import for IP and location data saving
#import "DomainBlockingSettings.h"
#import "DomainManagementViewController.h"
#import <notify.h>  // Add this import for Darwin notification functions
#import "common/UIButton+SafeConfiguration.h"
#import "common/VersionCompare.h"
#import "common/IPStatusCacheManager.h"
#import <CoreLocation/CoreLocation.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <MapKit/MapKit.h>

#pragma mark - MatrixRainView Implementation

@interface MatrixRainCharacter : NSObject
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, copy) NSString *character;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat speed;
@property (nonatomic, assign) CGFloat opacity;


@end

@implementation MatrixRainCharacter

- (instancetype)init {
    if (self = [super init]) {
        // Set default properties
        _character = [self randomCharacter];
        _speed = (arc4random_uniform(10) + 1) / 10.0; // 0.1 to 1.0
        _opacity = 1.0;
    }
    return self;
}

- (NSString *)randomCharacter {
    // Include Japanese katakana, hiragana, and other symbols for more futuristic look
    NSArray *characterSets = @[
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$#@&%!?;:=+*-/\\",
        @"ｦｧｨｩｪｫｬｭｮｯｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ",
        @"αβγδεζηθικλμνξοπρστυφχψω",
        @"∂∆∏∑−±∞≠≈∫√∞²³°≤≥→×÷⌂⌐¬"
    ];
    
    // Select a random character set with higher probability for Japanese characters
    int setIndex = arc4random_uniform(100) < 75 ? arc4random_uniform(3) + 1 : 0;
    NSString *selectedSet = characterSets[setIndex];
    
    int randomIndex = arc4random_uniform((u_int32_t)[selectedSet length]);
    return [selectedSet substringWithRange:NSMakeRange(randomIndex, 1)];
}



@end

@interface MatrixRainView ()
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) UIColor *matrixColor;
@property (nonatomic, strong) NSArray *depthColors;


@end

@implementation MatrixRainView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    return self;
}

- (void)setup {
    self.backgroundColor = [UIColor clearColor];
    self.matrixColor = [UIColor systemGreenColor];
    
    // Define colors for depth effect - only green shades, no white
    self.depthColors = @[
        [UIColor colorWithRed:0.1 green:1.0 blue:0.1 alpha:1.0],     // Bright green
        [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0],     // Medium green
        [UIColor systemGreenColor],                                   // Standard green
        [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]      // Dark green
    ];
    
    self.columns = [NSMutableArray array];
    
    // Set up columns of characters - wider columns for less density
    CGFloat columnWidth = 25.0; // Increased from 15.0 to reduce density
    NSInteger numColumns = self.bounds.size.width / columnWidth;
    
    for (int i = 0; i < numColumns; i++) {
        // Randomly skip some columns (30% chance)
        if (arc4random_uniform(100) < 30) {
            [self.columns addObject:[NSMutableArray array]]; // Empty column
            continue;
        }
        
        NSMutableArray *column = [NSMutableArray array];
        
        // Random starting position with more spacing
        CGFloat startY = - (CGFloat)(arc4random_uniform(1000));
        
        // Fewer characters per column (3-12 instead of 5-20)
        int numChars = arc4random_uniform(10) + 3;
        
        for (int j = 0; j < numChars; j++) {
            MatrixRainCharacter *character = [[MatrixRainCharacter alloc] init];
            // More vertical spacing between characters
            character.position = CGPointMake(i * columnWidth, startY - (j * 25));
            
            // Assign depth-based color
            int depthIndex = arc4random_uniform(4);
            character.color = self.depthColors[depthIndex];
            
            // Vary speed based on depth
            character.speed = (0.3 + (arc4random_uniform(12) / 10.0)) * (1.0 - (depthIndex * 0.15));
            
            [column addObject:character];
        }
        
        [self.columns addObject:column];
    }
}

- (void)startAnimation {
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMatrix)];
        // Use an even lower frame rate (20 fps) to reduce CPU usage further
        self.displayLink.preferredFramesPerSecond = 20;
        [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)stopAnimation {
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self setNeedsDisplay];
}

- (void)updateWithColor:(UIColor *)color {
    self.matrixColor = color;
    for (NSMutableArray *column in self.columns) {
        for (MatrixRainCharacter *character in column) {
            character.color = color;
        }
    }
    [self setNeedsDisplay];
}

- (void)updateMatrix {
    static int frameCount = 0;
    frameCount++;
    
    for (NSMutableArray *column in self.columns) {
        // Skip empty columns
        if (column.count == 0) {
            continue;
        }
        
        // Track the first visible character to make it brighter
        MatrixRainCharacter *leadCharacter = nil;
        CGFloat minY = CGFLOAT_MAX;
        
        for (MatrixRainCharacter *character in column) {
            // Move character down with its own speed
            CGPoint position = character.position;
            position.y += character.speed * 6; // Reduced speed multiplier from 8 to 6
            character.position = position;
            
            // Track lead character (first visible in column)
            if (position.y > 0 && position.y < minY) {
                minY = position.y;
                leadCharacter = character;
            }
            
            // Random character change (reduced from 10% to 5% chance)
            if (arc4random_uniform(100) < 5) {
                character.character = [character randomCharacter];
            }
            
            // If character moves off-screen, reset to top
            if (position.y > self.bounds.size.height) {
                position.y = -15;
                character.position = position;
                character.opacity = 1.0;
                character.character = [character randomCharacter];
                
                // Occasionally change depth/color when recycling (reduced from 30% to 20%)
                if (arc4random_uniform(100) < 20) {
                    int depthIndex = arc4random_uniform(4);
                    character.color = self.depthColors[depthIndex];
                    character.speed = (0.3 + (arc4random_uniform(12) / 10.0)) * (1.0 - (depthIndex * 0.15));
                }
            }
            
            // Fade out as it falls
            if (position.y > self.bounds.size.height - 150) {
                character.opacity = (self.bounds.size.height - position.y) / 150.0;
            }
        }
        
        // Highlight lead character with a brighter green (not white) and full opacity
        if (leadCharacter && arc4random_uniform(100) < 30) {
            leadCharacter.color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0]; // Pure green, not white-ish
            leadCharacter.opacity = 1.0;
        }
    }
    
    // Change random characters less frequently (every 45 frames instead of 30)
    if (frameCount % 45 == 0) {
        int numChanges = 5 + arc4random_uniform(10); // Reduced from 10-30 to 5-15
        for (int i = 0; i < numChanges; i++) {
            int colIndex = arc4random_uniform((uint32_t)self.columns.count);
            NSMutableArray *column = self.columns[colIndex];
            
            if (column.count > 0) {
                int charIndex = arc4random_uniform((uint32_t)column.count);
                MatrixRainCharacter *character = column[charIndex];
                character.character = [character randomCharacter];
            }
        }
    }
    
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextClearRect(context, rect);
    
    for (NSMutableArray *column in self.columns) {
        for (MatrixRainCharacter *character in column) {
            // Skip if outside the visible area
            if (character.position.y < -20 || character.position.y > self.bounds.size.height + 20) {
                continue;
            }
            
            // Set the alpha for the character
            CGContextSetAlpha(context, character.opacity);
            
            // Set the color
            UIColor *drawColor = character.color;
            CGContextSetFillColorWithColor(context, drawColor.CGColor);
            
            // Draw the character
            [character.character drawAtPoint:character.position 
                            withAttributes:@{
                                NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                                NSForegroundColorAttributeName: drawColor
                            }];
            
            // Enhanced green glow effect for ALL characters (not just some)
            if (arc4random_uniform(100) < 40) { // Increased chance of glow from 8% to 40%
                CGContextSaveGState(context);
                
                // Create a stronger green glow effect
                CGFloat glowIntensity = (arc4random_uniform(40) / 100.0) + 0.2; // 0.2-0.6 intensity
                UIColor *glowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:glowIntensity];
                
                // Draw multiple glow layers
                for (int i = 1; i <= 3; i++) {
                    CGFloat offset = i * 0.5;
                    CGFloat alpha = character.opacity * (0.5 / i);
                    
                    CGContextSetAlpha(context, alpha);
                    [character.character drawAtPoint:CGPointMake(character.position.x + offset, character.position.y)
                                     withAttributes:@{
                                         NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                                         NSForegroundColorAttributeName: glowColor
                                     }];
                    
                    [character.character drawAtPoint:CGPointMake(character.position.x - offset, character.position.y)
                                     withAttributes:@{
                                         NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                                         NSForegroundColorAttributeName: glowColor
                                     }];
                    
                    [character.character drawAtPoint:CGPointMake(character.position.x, character.position.y + offset)
                                     withAttributes:@{
                                         NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                                         NSForegroundColorAttributeName: glowColor
                                     }];
                    
                    [character.character drawAtPoint:CGPointMake(character.position.x, character.position.y - offset)
                                     withAttributes:@{
                                         NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                                         NSForegroundColorAttributeName: glowColor
                                     }];
                }
                
                CGContextRestoreGState(context);
            }
        }
    }
}



@end


@interface SecurityTabViewController () <UITextFieldDelegate>

// Domain Blocking Properties
@property (nonatomic, strong) UISwitch *domainBlockingToggleSwitch;
@property (nonatomic, strong) UIButton *domainManagementButton;

// Matrix Rain View (properties declared in header)

@property (nonatomic, strong) UIButton *ipMonitorCheckButton;
@property (nonatomic, strong) UISwitch *ipMonitorToggleSwitch;
@property (nonatomic, strong) UISwitch *targetRegionFollowsIPToggleSwitch;
@property (nonatomic, strong) UIButton *targetRegionSyncButton;

@property (nonatomic, strong) UILabel *safariStackSpoofingLabel;
@property (nonatomic, strong) UISwitch *safariStackSpoofingToggleSwitch;

@property (nonatomic, strong) UILabel *webCompatIOSRangeLabel;
@property (nonatomic, strong) UISwitch *webCompatIOSRangeToggleSwitch;
@property (nonatomic, strong) UILabel *webCompatIOSRangeWarningLabel;

@property (nonatomic, strong) UILabel *fullSpoofTestModeLabel;
@property (nonatomic, strong) UISwitch *fullSpoofTestModeToggleSwitch;

@property (nonatomic, strong) UILabel *displayUIScaleSpoofLabel;
@property (nonatomic, strong) UISwitch *displayUIScaleSpoofToggleSwitch;

@property (nonatomic, strong) NSLayoutConstraint *webCompatIOSRangeWarningHeightConstraint;
- (void)setupIPMonitorControl:(UIView *)contentView;
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

- (NSString *)flagEmojiForCountryCode:(NSString *)countryCode {
    if (!countryCode || countryCode.length != 2) {
        PXLog(@"[WeaponX] Invalid country code for flag emoji: %@", countryCode);
        return nil;
    }
    
    // Convert country code to uppercase
    countryCode = [countryCode uppercaseString];
    
    // Create array of country codes and corresponding emojis
    NSDictionary *flagEmojis = @{
        @"US": @"🇺🇸",
        @"GB": @"🇬🇧",
        @"CA": @"🇨🇦",
        @"AU": @"🇦🇺",
        @"IN": @"🇮🇳",
        @"JP": @"🇯🇵",
        @"DE": @"🇩🇪",
        @"FR": @"🇫🇷",
        @"IT": @"🇮🇹",
        @"ES": @"🇪🇸",
        @"BR": @"🇧🇷",
        @"RU": @"🇷🇺",
        @"CN": @"🇨🇳",
        @"KR": @"🇰🇷",
        @"ID": @"🇮🇩",
        @"MX": @"🇲🇽",
        @"NL": @"🇳🇱",
        @"TR": @"🇹🇷",
        @"SA": @"🇸🇦",
        @"CH": @"🇨🇭",
        @"SE": @"🇸🇪",
        @"PL": @"🇵🇱",
        @"BE": @"🇧🇪",
        @"IR": @"🇮🇷",
        @"NO": @"🇳🇴",
        @"AT": @"🇦🇹",
        @"IL": @"🇮🇱",
        @"DK": @"🇩🇰",
        @"SG": @"🇸🇬",
        @"FI": @"🇫🇮",
        @"NZ": @"🇳🇿",
        @"MY": @"🇲🇾",
        @"TH": @"🇹🇭",
        @"AE": @"🇦🇪",
        @"PH": @"🇵🇭",
        @"IE": @"🇮🇪",
        @"PT": @"🇵🇹",
        @"GR": @"🇬🇷",
        @"CZ": @"🇨🇿",
        @"VN": @"🇻🇳",
        @"RO": @"🇷🇴",
        @"ZA": @"🇿🇦",
        @"UA": @"🇺🇦",
        @"HK": @"🇭🇰",
        @"HU": @"🇭🇺",
        @"BG": @"🇧🇬",
        @"HR": @"🇭🇷",
        @"LT": @"🇱🇹",
        @"EE": @"🇪🇪",
        @"SK": @"🇸🇰"
    };
    
    NSString *flag = flagEmojis[countryCode];
    if (!flag) {
        PXLog(@"[WeaponX] No predefined flag emoji for country code: %@", countryCode);
        // Fallback to dynamic generation for unsupported country codes
        flag = [[NSString alloc] initWithFormat:@"%C%C",
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:0] - 'A'),
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:1] - 'A')];
    }
    
    PXLog(@"[WeaponX] Generated flag emoji for %@: %@", countryCode, flag);
    return flag;
}

- (void)fetchCountryForCoordinates:(double)lat longitude:(double)lon completion:(void (^)(NSString *countryCode, NSString *flag))completion {
    // Create cache key
    NSString *cacheKey = [NSString stringWithFormat:@"%.4f,%.4f", lat, lon];
    
    // Check cache first
    NSDictionary *cachedInfo = [self.countryCache objectForKey:cacheKey];
    if (cachedInfo) {
        completion(cachedInfo[@"countryCode"], cachedInfo[@"flag"]);
        return;
    }
    
    // Create URL for OpenStreetMap Nominatim reverse geocoding
    NSString *urlString = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/reverse?format=json&lat=%.6f&lon=%.6f&zoom=18&addressdetails=1", lat, lon];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"WeaponX iOS App" forHTTPHeaderField:@"User-Agent"]; // Required by Nominatim
    [request setTimeoutInterval:10.0]; // Add timeout
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || !json || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        NSDictionary *address = json[@"address"];
        NSString *countryCode = address[@"country_code"];
        
        if (!countryCode) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        // Convert country code to uppercase for flag emoji
        countryCode = [countryCode uppercaseString];
        
        // Convert country code to flag emoji
        NSString *flag = [self flagEmojiForCountryCode:countryCode];
        
        // Verify flag emoji was created successfully
        if (flag && flag.length > 0) {
            // Cache the result
            [self.countryCache setObject:@{
                @"countryCode": countryCode,
                @"flag": flag
            } forKey:cacheKey];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(countryCode, flag);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(countryCode, nil);
            });
        }
    }];
    
    [task resume];
}

- (void)ipMonitorCheckTapped:(id)sender {
    [self presentIPStatusPage];
}

- (void)presentIPStatusPage {
    IPStatusViewController *vc = [[IPStatusViewController alloc] init];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // Add a back button to dismiss if presented modally
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(dismissIPStatusPage)];
        vc.navigationItem.leftBarButtonItem = backButton;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)dismissIPStatusPage {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - IP Monitor Toggle Handler
- (void)ipMonitorToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"ipMonitorEnabled"];
    [self.securitySettings synchronize];

    // Start or stop IP monitoring based on toggle state
    if (enabled) {
        [[IPMonitorService sharedInstance] startMonitoring];
    } else {
        [[IPMonitorService sharedInstance] stopMonitoring];
    }

    NSString *msg = enabled ? @"IP Monitoring Enabled" : @"IP Monitoring Disabled";
    [self showToastWithMessage:msg];
}

- (void)setupIPMonitorControl:(UIView *)contentView {
    // Create a glassmorphic control for IP Monitor
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];

    // Title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Check & Monitor IP Status";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:titleLabel];

    // Info button
    UIButton *ipInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    if (@available(iOS 13.0, *)) {
        UIImage *infoImage = [UIImage systemImageNamed:@"info.circle"];
        [ipInfoButton setImage:infoImage forState:UIControlStateNormal];
        ipInfoButton.tintColor = [UIColor systemGrayColor];
    } else {
        [ipInfoButton setTitle:@"i" forState:UIControlStateNormal];
        ipInfoButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    }
    ipInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [ipInfoButton addTarget:self action:@selector(showIPMonitorInfo) forControlEvents:UIControlEventTouchUpInside];
    [controlView.contentView addSubview:ipInfoButton];

    // Centered horizontal container for icon, button, and toggle
    UIView *centerContainer = [[UIView alloc] init];
    centerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:centerContainer];

    // Icon image view (SF Symbol)
    UIImageView *ipIconView = [[UIImageView alloc] init];
    UIImage *iconImg = nil;
    if (@available(iOS 13.0, *)) {
        iconImg = [UIImage systemImageNamed:@"network"];
    }
    // Fallback to a default image if SF Symbol fails
    if (!iconImg) {
        iconImg = [UIImage imageNamed:@"ip_icon"];
    }
    if (!iconImg) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(28, 28), NO, 0.0);
        [[UIColor systemGrayColor] setFill];
        UIRectFill(CGRectMake(0, 0, 28, 28));
        iconImg = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    ipIconView.image = [iconImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ipIconView.tintColor = [UIColor systemBlueColor];
    ipIconView.contentMode = UIViewContentModeScaleAspectFit;
    ipIconView.translatesAutoresizingMaskIntoConstraints = NO;
    // Remove debug border/background
    ipIconView.layer.borderWidth = 0;
    ipIconView.backgroundColor = [UIColor clearColor];
    [centerContainer addSubview:ipIconView];

    // Check IP button
    self.ipMonitorCheckButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = @"Check IP";
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] forKey:NSFontAttributeName];
            return newAttributes;
        };
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 12, 4, 12);
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseForegroundColor = [UIColor whiteColor];
        [self.ipMonitorCheckButton safeSetConfiguration:config];
    } else {
        [self.ipMonitorCheckButton setTitle:@"Check IP" forState:UIControlStateNormal];
        self.ipMonitorCheckButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.ipMonitorCheckButton.backgroundColor = [UIColor systemBlueColor];
        self.ipMonitorCheckButton.layer.cornerRadius = 15;
        self.ipMonitorCheckButton.tintColor = [UIColor whiteColor];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.ipMonitorCheckButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        #pragma clang diagnostic pop
    }
    self.ipMonitorCheckButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.ipMonitorCheckButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.ipMonitorCheckButton.layer.shadowOpacity = 0.2;
    self.ipMonitorCheckButton.layer.shadowRadius = 2;
    self.ipMonitorCheckButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.ipMonitorCheckButton addTarget:self action:@selector(ipMonitorCheckTapped:) forControlEvents:UIControlEventTouchUpInside];
    [centerContainer addSubview:self.ipMonitorCheckButton];

    // Monitor toggle
    self.ipMonitorToggleSwitch = [[UISwitch alloc] init];
    self.ipMonitorToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.ipMonitorToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL monitorEnabled = [self.securitySettings boolForKey:@"ipMonitorEnabled"];
    [self.ipMonitorToggleSwitch setOn:monitorEnabled animated:NO];
    [self.ipMonitorToggleSwitch addTarget:self action:@selector(ipMonitorToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [centerContainer addSubview:self.ipMonitorToggleSwitch];

    // Layout for icon, button, and toggle inside centerContainer
    [NSLayoutConstraint activateConstraints:@[
        [ipIconView.centerYAnchor constraintEqualToAnchor:self.ipMonitorCheckButton.centerYAnchor],
        [ipIconView.leadingAnchor constraintEqualToAnchor:centerContainer.leadingAnchor],
        [ipIconView.widthAnchor constraintEqualToConstant:28],
        [ipIconView.heightAnchor constraintEqualToConstant:28],

        [self.ipMonitorCheckButton.leadingAnchor constraintEqualToAnchor:ipIconView.trailingAnchor constant:12],
        [self.ipMonitorCheckButton.centerYAnchor constraintEqualToAnchor:centerContainer.centerYAnchor],

        [self.ipMonitorToggleSwitch.leadingAnchor constraintEqualToAnchor:self.ipMonitorCheckButton.trailingAnchor constant:16],
        [self.ipMonitorToggleSwitch.centerYAnchor constraintEqualToAnchor:centerContainer.centerYAnchor],
        [self.ipMonitorToggleSwitch.trailingAnchor constraintEqualToAnchor:centerContainer.trailingAnchor],
    ]];

    // Add subtle info label below the container
    UILabel *ipMonitorInfoLabel = [[UILabel alloc] init];
    ipMonitorInfoLabel.text = @"Turn on toggle for IP monitoring. It notifies when IP changes.";
    ipMonitorInfoLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightRegular];
    ipMonitorInfoLabel.textColor = [UIColor secondaryLabelColor];
    ipMonitorInfoLabel.textAlignment = NSTextAlignmentCenter;
    ipMonitorInfoLabel.numberOfLines = 1;
    ipMonitorInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:ipMonitorInfoLabel];

    // TargetRegion follows IP (pinned) row
    UIView *targetRegionRow = [[UIView alloc] init];
    targetRegionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:targetRegionRow];

    UILabel *targetRegionLabel = [[UILabel alloc] init];
    targetRegionLabel.text = @"TargetRegion follows IP";
    targetRegionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    targetRegionLabel.textColor = [UIColor secondaryLabelColor];
    targetRegionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [targetRegionRow addSubview:targetRegionLabel];

    self.targetRegionFollowsIPToggleSwitch = [[UISwitch alloc] init];
    self.targetRegionFollowsIPToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.targetRegionFollowsIPToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL followsEnabled = [self.securitySettings boolForKey:@"targetRegionFollowsIPEnabled"];
    [self.targetRegionFollowsIPToggleSwitch setOn:followsEnabled animated:NO];
    [self.targetRegionFollowsIPToggleSwitch addTarget:self action:@selector(targetRegionFollowsIPToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [targetRegionRow addSubview:self.targetRegionFollowsIPToggleSwitch];

    self.targetRegionSyncButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
        cfg.title = @"Sync from IP now";
        cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            newAttributes[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            return newAttributes;
        };
        cfg.baseForegroundColor = [UIColor systemBlueColor];
        cfg.background.cornerRadius = 12;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
        [self.targetRegionSyncButton safeSetConfiguration:cfg];
    } else {
        [self.targetRegionSyncButton setTitle:@"Sync from IP now" forState:UIControlStateNormal];
        self.targetRegionSyncButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    }
    self.targetRegionSyncButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.targetRegionSyncButton addTarget:self action:@selector(syncTargetRegionFromIPTapped:) forControlEvents:UIControlEventTouchUpInside];
    [controlView.contentView addSubview:self.targetRegionSyncButton];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1260],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:200],

        [titleLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [ipInfoButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [ipInfoButton.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:8],
        [ipInfoButton.widthAnchor constraintEqualToConstant:24],
        [ipInfoButton.heightAnchor constraintEqualToConstant:24],
        [ipInfoButton.trailingAnchor constraintLessThanOrEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],

        // Keep the container near the top so extra rows fit.
        [centerContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [centerContainer.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [centerContainer.heightAnchor constraintEqualToConstant:44],
        [centerContainer.widthAnchor constraintLessThanOrEqualToAnchor:controlView.contentView.widthAnchor constant:-40],

        // Icon, button, and toggle inside container
        [ipIconView.leadingAnchor constraintEqualToAnchor:centerContainer.leadingAnchor],
        [ipIconView.centerYAnchor constraintEqualToAnchor:centerContainer.centerYAnchor],
        [ipIconView.widthAnchor constraintEqualToConstant:28],
        [ipIconView.heightAnchor constraintEqualToConstant:28],

        [self.ipMonitorCheckButton.leadingAnchor constraintEqualToAnchor:ipIconView.trailingAnchor constant:8],
        [self.ipMonitorCheckButton.centerYAnchor constraintEqualToAnchor:centerContainer.centerYAnchor],

        [self.ipMonitorToggleSwitch.leadingAnchor constraintEqualToAnchor:self.ipMonitorCheckButton.trailingAnchor constant:24],
        [self.ipMonitorToggleSwitch.centerYAnchor constraintEqualToAnchor:centerContainer.centerYAnchor],
        [self.ipMonitorToggleSwitch.trailingAnchor constraintEqualToAnchor:centerContainer.trailingAnchor],

        // Info label below the container
        [ipMonitorInfoLabel.topAnchor constraintEqualToAnchor:centerContainer.bottomAnchor constant:6],
        [ipMonitorInfoLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [ipMonitorInfoLabel.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],

        // TargetRegion row below info label
        [targetRegionRow.topAnchor constraintEqualToAnchor:ipMonitorInfoLabel.bottomAnchor constant:10],
        [targetRegionRow.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [targetRegionRow.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [targetRegionRow.heightAnchor constraintEqualToConstant:28],

        [targetRegionLabel.leadingAnchor constraintEqualToAnchor:targetRegionRow.leadingAnchor],
        [targetRegionLabel.centerYAnchor constraintEqualToAnchor:targetRegionRow.centerYAnchor],

        [self.targetRegionFollowsIPToggleSwitch.trailingAnchor constraintEqualToAnchor:targetRegionRow.trailingAnchor],
        [self.targetRegionFollowsIPToggleSwitch.centerYAnchor constraintEqualToAnchor:targetRegionRow.centerYAnchor],

        // Sync button at bottom
        [self.targetRegionSyncButton.topAnchor constraintEqualToAnchor:targetRegionRow.bottomAnchor constant:8],
        [self.targetRegionSyncButton.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.targetRegionSyncButton.bottomAnchor constraintEqualToAnchor:controlView.contentView.bottomAnchor constant:-12],
    ]];
}

- (void)refreshPinnedCoordinates {
    // Set the main title directly
    self.title = @"Security";
    
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

    // Create a custom view for the left bar button item (IP address)
    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
    
    // Create IP label
    UILabel *ipLabel = [[UILabel alloc] init];
    ipLabel.textColor = [UIColor secondaryLabelColor];
    ipLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    ipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ipLabel.adjustsFontSizeToFitWidth = YES;
    ipLabel.minimumScaleFactor = 0.8;
    ipLabel.textAlignment = NSTextAlignmentLeft;
    ipLabel.tag = 1001; // Tag for easy reference to update later
    
    // Set initial text
    NSString *lastKnownIP = [[IPMonitorService sharedInstance] loadLastKnownIP];
    if (lastKnownIP) {
        ipLabel.text = [NSString stringWithFormat:@"IP: %@", lastKnownIP];
    } else {
        ipLabel.text = @"Fetching IP...";
    }
    
    [leftView addSubview:ipLabel];
    
    // Set up constraints for left view
    [NSLayoutConstraint activateConstraints:@[
        [ipLabel.centerYAnchor constraintEqualToAnchor:leftView.centerYAnchor],
        [ipLabel.leadingAnchor constraintEqualToAnchor:leftView.leadingAnchor],
        [ipLabel.trailingAnchor constraintEqualToAnchor:leftView.trailingAnchor]
    ]];
    
    // Get pinned location
    NSDictionary *pinnedLocation = [[LocationSpoofingManager sharedManager] loadSpoofingLocation];
    if (pinnedLocation && pinnedLocation[@"latitude"] && pinnedLocation[@"longitude"]) {
        double lat = [pinnedLocation[@"latitude"] doubleValue];
        double lon = [pinnedLocation[@"longitude"] doubleValue];
        
        // Initially set coordinates without flag
        coordsLabel.text = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
        coordsLabel.hidden = NO;
        self.timeLabel.hidden = NO;
        
        // Get timezone and update time
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat, lon);
        [self getTimeZoneForLocation:coordinate completion:^(NSTimeZone *timeZone, NSString *timeZoneId) {
            if (timeZone) {
                self.currentTimeZoneId = timeZoneId;
                
                // Update time immediately
                [self updateTimeForTimeZone:timeZone];
                
                // Remove timer-based updates to prevent crashes
                [self.timeUpdateTimer invalidate];
                self.timeUpdateTimer = nil;
                
                // Add tap gesture to time label if not already added
                if (![self.timeLabel.gestureRecognizers count]) {
                    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showTimeZoneOptions)];
                    [self.timeLabel addGestureRecognizer:tapGesture];
                    self.timeLabel.userInteractionEnabled = YES;
                }
            }
        }];
        
        // Fetch country info and update label
        [self fetchCountryForCoordinates:lat longitude:lon completion:^(NSString *countryCode, NSString *flag) {
            if (flag) {
                NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:
                    [NSString stringWithFormat:@"%@ %.4f, %.4f", flag, lat, lon]
                    attributes:@{
                        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightRegular],
                        NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                    }];
                coordsLabel.attributedText = attributedText;
                PXLog(@"[WeaponX] Updated title with flag: %@ for country: %@", flag, countryCode);
                
                // Save location data to iplocationtime.plist
                Class cacheManagerClass = NSClassFromString(@"IPStatusCacheManager");
                if (cacheManagerClass && 
                    [cacheManagerClass respondsToSelector:@selector(savePinnedLocation:countryCode:flagEmoji:timestamp:)]) {
                    
                    CLLocationCoordinate2D coords;
                    coords.latitude = lat;
                    coords.longitude = lon;
                    
                    [cacheManagerClass savePinnedLocation:coords
                                              countryCode:countryCode
                                               flagEmoji:flag
                                               timestamp:[NSDate date]];
                    PXLog(@"[WeaponX] Saved pinned location to iplocationtime.plist: %.4f, %.4f", coords.latitude, coords.longitude);
                }
            }
        }];
        
        // Create bar button items with the custom views
        UIBarButtonItem *rightBarItem = [[UIBarButtonItem alloc] initWithCustomView:rightView];
        UIBarButtonItem *leftBarItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
        
        self.navigationItem.rightBarButtonItem = rightBarItem;
        self.navigationItem.leftBarButtonItem = leftBarItem;
    } else {
        // If no pinned location, still show the IP on the left
        UIBarButtonItem *leftBarItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
        self.navigationItem.leftBarButtonItem = leftBarItem;
    }
    
    // Fetch the current IP
    [self fetchCurrentIP];
}

- (void)fetchCurrentIP {
    // Create a URL session with timeout
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 8.0;
    config.timeoutIntervalForResource = 15.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Use ipwhois.app to get additional country info
    NSString *ipwhoisURL = @"https://ipwhois.app/json/";
    NSURL *url = [NSURL URLWithString:ipwhoisURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"WeaponX iOS App" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            // Fallback to simpler IP services if ipwhois fails
            PXLog(@"[IPDisplay] ipwhois.app request failed: %@", error);
            [self fetchSimpleIP];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            PXLog(@"[IPDisplay] JSON parsing failed: %@", jsonError);
            [self fetchSimpleIP];
            return;
        }
        
        // Debug to see all fields
        PXLog(@"[IPDisplay] ipwhois response: %@", json);
        
        NSString *ip = json[@"ip"];
        NSString *countryCode = json[@"country_code"];
        
        // Get timezone info and format current time
        NSString *currentTime = nil;
        NSString *timezoneName = json[@"timezone"];
        
        if (timezoneName) {
            // Create timezone from name (e.g., "America/New_York")
            NSTimeZone *tz = [NSTimeZone timeZoneWithName:timezoneName];
            if (tz) {
                // Format current time in the IP's timezone
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.timeZone = tz;
                formatter.dateFormat = @"h:mm a"; // 12-hour format with AM/PM
                currentTime = [formatter stringFromDate:[NSDate date]];
                PXLog(@"[IPDisplay] Formatted current time for %@: %@", timezoneName, currentTime);
            }
        }
        
        // If we couldn't format the time, fall back to timezone_gmt
        if (!currentTime) {
            currentTime = json[@"timezone_gmt"];
        }
        
        PXLog(@"[IPDisplay] IP: %@, Country: %@, Time: %@", ip, countryCode, currentTime);
        
        if (ip) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateIPLabelWithIP:ip countryCode:countryCode currentTime:currentTime];
            });
        } else {
            [self fetchSimpleIP];
        }
    }];
    
    [task resume];
}

- (void)fetchSimpleIP {
    // Fallback to simpler IP service without country info
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 5.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org"];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:[NSURLRequest requestWithURL:url] 
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            return;
        }
        
        NSString *ip = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (ip && ip.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateIPLabelWithIP:ip countryCode:nil currentTime:nil];
            });
        }
    }];
    
    [task resume];
}

- (void)updateIPLabelWithIP:(NSString *)ip countryCode:(NSString *)countryCode currentTime:(NSString *)currentTime {
    // Get the views
    UIView *leftView = self.navigationItem.leftBarButtonItem.customView;
    UILabel *ipLabel = [leftView viewWithTag:1001];
    UILabel *ipTimeLabel = [leftView viewWithTag:1002];
    
    if (!ipTimeLabel && leftView) {
        // Create time label if it doesn't exist
        ipTimeLabel = [[UILabel alloc] init];
        ipTimeLabel.textColor = [UIColor secondaryLabelColor];
        ipTimeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
        ipTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        ipTimeLabel.adjustsFontSizeToFitWidth = YES;
        ipTimeLabel.minimumScaleFactor = 0.8;
        ipTimeLabel.textAlignment = NSTextAlignmentLeft;
        ipTimeLabel.tag = 1002;
        [leftView addSubview:ipTimeLabel];
        
        // Position time label below IP label
        [NSLayoutConstraint activateConstraints:@[
            [ipTimeLabel.topAnchor constraintEqualToAnchor:ipLabel.bottomAnchor constant:2],
            [ipTimeLabel.leadingAnchor constraintEqualToAnchor:ipLabel.leadingAnchor],
            [ipTimeLabel.trailingAnchor constraintEqualToAnchor:ipLabel.trailingAnchor]
        ]];
        
        PXLog(@"[IPDisplay] Created time label: %@", ipTimeLabel);
    }
    
    if (ipLabel) {
        // Format the IP address (abbreviate IPv6)
        NSString *formattedIP = [self formatIPAddress:ip];
        NSString *flagEmoji = nil;
        
        if (countryCode) {
            // Get flag emoji for country code
            flagEmoji = [self flagEmojiForCountryCode:countryCode];
            if (flagEmoji) {
                // Show flag + IP
                ipLabel.text = [NSString stringWithFormat:@"%@ %@", flagEmoji, formattedIP];
            } else {
                // Fallback to just IP
                ipLabel.text = formattedIP;
            }
        } else {
            // No country info, just show IP
            ipLabel.text = formattedIP;
        }
        
        // Update time label if we have time info
        if (ipTimeLabel && currentTime) {
            ipTimeLabel.text = currentTime;
            ipTimeLabel.hidden = NO;
            PXLog(@"[IPDisplay] Updated time label: %@ with time: %@", ipTimeLabel, currentTime);
        } else if (ipTimeLabel) {
            ipTimeLabel.hidden = YES;
            PXLog(@"[IPDisplay] Hiding time label due to no time data");
        }
        
        // Save to iplocationtime.plist
        if (ip) {
            // Import IPStatusCacheManager if needed
            Class cacheManagerClass = NSClassFromString(@"IPStatusCacheManager");
            if (cacheManagerClass && 
                [cacheManagerClass respondsToSelector:@selector(savePublicIP:countryCode:flagEmoji:timestamp:)]) {
                [cacheManagerClass savePublicIP:ip 
                                   countryCode:countryCode 
                                    flagEmoji:flagEmoji 
                                    timestamp:[NSDate date]];
                PXLog(@"[IPDisplay] Saved IP data to iplocationtime.plist: %@", ip);
            }
        }
    }
    
    // Make sure to update the frame of the left view to accommodate both labels
    [leftView setNeedsLayout];
    [leftView layoutIfNeeded];
    // Make sure left view is tall enough for both labels
    CGRect frame = leftView.frame;
    frame.size.height = 44;
    leftView.frame = frame;
}

- (NSString *)formatIPAddress:(NSString *)ipAddress {
    if (!ipAddress) return @"";
    
    // If IP length exceeds 17 characters, truncate it
    if (ipAddress.length > 17) {
        // If it's IPv6 (contains colons)
    if ([ipAddress containsString:@":"]) {
            NSString *start = [ipAddress substringToIndex:8];
            NSString *end = [ipAddress substringFromIndex:ipAddress.length - 4];
            return [NSString stringWithFormat:@"%@...%@", start, end];
        } else {
            // For any other long address, simply truncate with ellipsis
            return [NSString stringWithFormat:@"%@...", [ipAddress substringToIndex:14]];
        }
    }
    
    // Return full IP for addresses 17 chars or shorter
    return ipAddress;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPinnedCoordinates];
    
    // Refresh network identifiers from the current profile
    [self refreshNetworkIdentifiers];
    
    // Resume matrix animation if enabled
    if (self.matrixRainEnabled) {
        [self.matrixRainView startAnimation];
    }
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
    
    // Add Matrix Rain view (behind everything)
    self.matrixRainView = [[MatrixRainView alloc] initWithFrame:self.view.bounds];
    self.matrixRainView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.matrixRainView];
    
    // Check if Matrix Rain is enabled
    self.matrixRainEnabled = [self.securitySettings boolForKey:@"matrixRainEnabled"];
    if (self.matrixRainEnabled) {
        [self.matrixRainView startAnimation];
    }
    
    // Add tap gesture recognizer to dismiss keyboard when tapping elsewhere
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fixVersionAppsChanged:)
                                                 name:@"com.hydra.projectx.fixVersionAppsChanged"
                                               object:nil];
    
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
    
    // Add Matrix Rain toggle control
    [self setupMatrixControl:contentView];
    
    // Add Profile Indicator toggle control
    [self setupProfileIndicatorControl:contentView];
    
    // Add Jailbreak Detection Bypass toggle control
    [self setupJailbreakDetectionControl:contentView];
    
    // Add Network Data Spoof toggle control
    [self setupNetworkDataSpoofControl:contentView];
    
    // Add Network Connection Type control (WiFi/Cellular)
    [self setupNetworkConnectionTypeControl:contentView];
    
    // Add Device Specific Spoofing control
    [self setupDeviceSpecificSpoofingControl:contentView];
    
    // Add App Version Spoofing control
    [self setupAppVersionSpoofingControl:contentView];

    // Deep Clean (global clear-data verify scan)
    [self setupDeepCleanControl:contentView];

    // Allow system-app keychain wipe (dangerous)
    [self setupSystemKeychainWipeControl:contentView];

    // Fix Version (runtime-capped) control
    [self setupFixVersionControl:contentView];
    
    // Add Domain Blocking control
    [self setupDomainBlockingControl:contentView];
    
    // Add Canvas Fingerprinting Protection control
    [self setupCanvasFingerprintingControl:contentView];
    
    // Add IP Monitor control above Setup Alert Check
    [self setupIPMonitorControl:contentView];
    // Add VPN Detection Bypass control
    [self setupVPNDetectionBypassControl:contentView];
    // Add Setup Alert Check control
    [self setupAlertChecksSection:contentView];
    // Add Time Spoofing control
    [self setupTimeSpoofingControl:contentView];
    // Add Canvas Fingerprinting control
    [self setupCanvasFingerprintingControl:contentView];
    
    // Add HYDRA copyright at bottom
    [self setupCopyrightLabel:contentView];
}

static NSString *PXFlagEmojiFromCountryCode(NSString *cc) {
    if (![cc isKindOfClass:[NSString class]] || cc.length != 2) return @"";
    NSString *u = [cc uppercaseString];
    unichar c1 = [u characterAtIndex:0];
    unichar c2 = [u characterAtIndex:1];
    if (c1 < 'A' || c1 > 'Z' || c2 < 'A' || c2 > 'Z') return @"";
    // Regional indicator symbols start at U+1F1E6 for 'A'
    uint32_t base = 0x1F1E6;
    uint32_t r1 = base + (uint32_t)(c1 - 'A');
    uint32_t r2 = base + (uint32_t)(c2 - 'A');
    NSString *s1 = [[NSString alloc] initWithBytes:&r1 length:4 encoding:NSUTF32LittleEndianStringEncoding];
    NSString *s2 = [[NSString alloc] initWithBytes:&r2 length:4 encoding:NSUTF32LittleEndianStringEncoding];
    if (!s1.length || !s2.length) return @"";
    return [s1 stringByAppendingString:s2];
}

- (NSDictionary *)targetRegionDefaultsForCountryCode:(NSString *)countryCode {
    NSString *cc = [[countryCode ?: @"" uppercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cc.length != 2) cc = @"US";

    // Minimal mapping table. Extend as needed.
    if ([cc isEqualToString:@"VN"]) {
        return @{
            @"carrierISO": @"vn",
            @"mcc": @"452",
            @"mnc": @"01",
            @"carrierName": @"ProjectX",
            @"localeIdentifier": @"vi_VN",
            @"preferredLanguages": @[ @"vi-VN", @"en-US" ]
        };
    }
    if ([cc isEqualToString:@"US"]) {
        return @{
            @"carrierISO": @"us",
            @"mcc": @"310",
            @"mnc": @"260",
            @"carrierName": @"ProjectX",
            @"localeIdentifier": @"en_US",
            @"preferredLanguages": @[ @"en-US" ]
        };
    }

    // Fallback: keep defaults sane.
    return @{
        @"carrierISO": [[cc lowercaseString] copy],
        @"mcc": @"310",
        @"mnc": @"260",
        @"carrierName": @"ProjectX",
        @"localeIdentifier": [NSString stringWithFormat:@"en_%@", cc],
        @"preferredLanguages": @[ @"en-US" ]
    };
}

- (void)targetRegionFollowsIPToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"targetRegionFollowsIPEnabled"];
    [self.securitySettings synchronize];

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.carrierDetailsChanged"), NULL, NULL, YES);
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkISOCountryCodeChanged"), NULL, NULL, YES);
    }
}

- (void)syncTargetRegionFromIPTapped:(id)sender {
    // Fetch geo from IP and pin it. We intentionally do NOT auto-update on IP change.
    NSURL *url = [NSURL URLWithString:@"https://ip-api.com/json/?fields=status,message,countryCode,lat,lon,timezone,query"];
    if (!url) {
        [self showToastWithMessage:@"Invalid IP API URL"]; 
        return;
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10.0;
    cfg.timeoutIntervalForResource = 15.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    [self showToastWithMessage:@"Syncing TargetRegion from IP..."];
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"IP geo fetch failed"]; 
            });
            return;
        }

        NSDictionary *json = nil;
        @try {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        } @catch (__unused NSException *e) {
        }

        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"IP geo parse failed"]; 
            });
            return;
        }

        NSString *status = [json[@"status"] isKindOfClass:[NSString class]] ? json[@"status"] : @"";
        if (![status isEqualToString:@"success"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"IP geo service error"]; 
            });
            return;
        }

        NSString *cc = [json[@"countryCode"] isKindOfClass:[NSString class]] ? json[@"countryCode"] : nil;
        NSNumber *latN = [json[@"lat"] isKindOfClass:[NSNumber class]] ? json[@"lat"] : nil;
        NSNumber *lonN = [json[@"lon"] isKindOfClass:[NSNumber class]] ? json[@"lon"] : nil;
        NSString *tz = [json[@"timezone"] isKindOfClass:[NSString class]] ? json[@"timezone"] : nil;
        NSString *ip = [json[@"query"] isKindOfClass:[NSString class]] ? json[@"query"] : nil;

        if (!cc.length || !latN || !lonN || !tz.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"IP geo missing fields"]; 
            });
            return;
        }

        NSDictionary *defaults = [self targetRegionDefaultsForCountryCode:cc];
        NSString *carrierISO = defaults[@"carrierISO"];
        NSString *mcc = defaults[@"mcc"];
        NSString *mnc = defaults[@"mnc"];
        NSString *carrierName = defaults[@"carrierName"];
        NSString *localeId = defaults[@"localeIdentifier"];
        NSArray *langs = defaults[@"preferredLanguages"];

        // Persist pinned TargetRegion in security settings.
        [self.securitySettings setBool:YES forKey:@"targetRegionFollowsIPEnabled"]; 
        [self.securitySettings setObject:[cc uppercaseString] forKey:@"targetRegionPinnedCountryCode"]; 
        [self.securitySettings setObject:tz forKey:@"targetRegionPinnedTimeZoneName"]; 
        [self.securitySettings setObject:localeId forKey:@"targetRegionPinnedLocaleIdentifier"]; 
        if ([langs isKindOfClass:[NSArray class]]) {
            [self.securitySettings setObject:langs forKey:@"targetRegionPinnedPreferredLanguages"]; 
        }
        [self.securitySettings setObject:carrierISO forKey:@"targetRegionPinnedCarrierISO"]; 
        [self.securitySettings setObject:mcc forKey:@"targetRegionPinnedCarrierMCC"]; 
        [self.securitySettings setObject:mnc forKey:@"targetRegionPinnedCarrierMNC"]; 
        [self.securitySettings setObject:carrierName forKey:@"targetRegionPinnedCarrierName"]; 
        [self.securitySettings setDouble:[latN doubleValue] forKey:@"targetRegionPinnedLatitude"]; 
        [self.securitySettings setDouble:[lonN doubleValue] forKey:@"targetRegionPinnedLongitude"]; 
        [self.securitySettings setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"targetRegionPinnedTimestamp"]; 
        if (ip.length) {
            [self.securitySettings setObject:ip forKey:@"targetRegionPinnedSourceIP"]; 
        }

        // Keep legacy key used by NetworkConnectionTypeHooks.
        if (carrierISO.length) {
            [self.securitySettings setObject:carrierISO forKey:@"networkISOCountryCode"]; 
        }

        [self.securitySettings synchronize];

        // Update pinned GPS location (so CLLocation spoof stays consistent with IP region).
        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake([latN doubleValue], [lonN doubleValue]);
        NSString *flag = PXFlagEmojiFromCountryCode(cc);
        [IPStatusCacheManager savePinnedLocation:coord countryCode:[cc uppercaseString] flagEmoji:flag timestamp:[NSDate date]];

        // Also write to the GPS spoofing plist used by LocationSpoofingManager.
        NSString *gpsPlist = @"/var/mobile/Library/Preferences/com.weaponx.gpsspoofing.plist";
        NSMutableDictionary *gpsSettings = [NSMutableDictionary dictionaryWithContentsOfFile:gpsPlist];
        if (!gpsSettings) gpsSettings = [NSMutableDictionary dictionary];
        gpsSettings[@"PinnedLocation"] = @{ @"latitude": @([latN doubleValue]), @"longitude": @([lonN doubleValue]) };
        gpsSettings[@"GPSSpoofingToggleEnabled"] = @YES;
        [gpsSettings writeToFile:gpsPlist atomically:YES];

        // Notify tweak.
        CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
        if (darwinCenter) {
            CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
            CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.carrierDetailsChanged"), NULL, NULL, YES);
            CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.networkISOCountryCodeChanged"), NULL, NULL, YES);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.targetRegionFollowsIPToggleSwitch) {
                [self.targetRegionFollowsIPToggleSwitch setOn:YES animated:YES];
            }
            [self showToastWithMessage:[NSString stringWithFormat:@"Pinned %@ (%@)", [cc uppercaseString], tz]];
        });
    }] resume];
}

- (void)fixVersionAppsChanged:(NSNotification *)note {
    [self refreshFixVersionAppsButtonTitle];
}

- (void)setupMatrixControl:(UIView *)contentView {
    // Create a simple glassmorphic control for Matrix Rain toggle
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Matrix label
    self.matrixLabel = [[UILabel alloc] init];
    self.matrixLabel.text = @"Matrix Rain Effect";
    self.matrixLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.matrixLabel.textColor = [UIColor labelColor];
    self.matrixLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.matrixLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.matrixInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.matrixInfoButton.tintColor = [UIColor systemBlueColor];
    self.matrixInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.matrixInfoButton addTarget:self action:@selector(showMatrixInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.matrixInfoButton];
    
    // Matrix toggle switch
    self.matrixToggleSwitch = [[UISwitch alloc] init];
    self.matrixToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.matrixToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.matrixToggleSwitch setOn:self.matrixRainEnabled animated:NO];
    [self.matrixToggleSwitch addTarget:self action:@selector(matrixToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.matrixToggleSwitch];
    
    // Position toggle control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:60],
        
        [self.matrixLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.matrixLabel.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.matrixLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.matrixInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.matrixInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        [self.matrixToggleSwitch.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.matrixToggleSwitch.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor]
    ]];
}

- (void)setupProfileIndicatorControl:(UIView *)contentView {
    // Create a glassmorphic control for Profile Indicator toggle
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Profile indicator label
    self.profileIndicatorLabel = [[UILabel alloc] init];
    self.profileIndicatorLabel.text = @"Profile Indicator";
    self.profileIndicatorLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.profileIndicatorLabel.textColor = [UIColor labelColor];
    self.profileIndicatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.profileIndicatorLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.profileIndicatorInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.profileIndicatorInfoButton.tintColor = [UIColor systemBlueColor];
    self.profileIndicatorInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.profileIndicatorInfoButton addTarget:self action:@selector(showProfileIndicatorInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.profileIndicatorInfoButton];
    
    // Profile Indicator toggle switch
    self.profileIndicatorToggleSwitch = [[UISwitch alloc] init];
    self.profileIndicatorToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.profileIndicatorToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Check if profile indicator is enabled
    BOOL profileIndicatorEnabled = [self.securitySettings boolForKey:@"profileIndicatorEnabled"];
    [self.profileIndicatorToggleSwitch setOn:profileIndicatorEnabled animated:NO];
    
    [self.profileIndicatorToggleSwitch addTarget:self action:@selector(profileIndicatorToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.profileIndicatorToggleSwitch];
    
    // Position control under the matrix control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:100], // Position below Matrix control
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:60],
        
        [self.profileIndicatorLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.profileIndicatorLabel.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.profileIndicatorLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.profileIndicatorInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.profileIndicatorInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        [self.profileIndicatorToggleSwitch.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.profileIndicatorToggleSwitch.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor]
    ]];
}

- (void)setupJailbreakDetectionControl:(UIView *)contentView {
    // Create a glassmorphic control for Jailbreak Detection Bypass toggle
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Jailbreak detection bypass label
    self.jailbreakDetectionLabel = [[UILabel alloc] init];
    self.jailbreakDetectionLabel.text = @"Jailbreak Detection Bypass";
    self.jailbreakDetectionLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.jailbreakDetectionLabel.textColor = [UIColor labelColor];
    self.jailbreakDetectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.jailbreakDetectionLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.jailbreakDetectionInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.jailbreakDetectionInfoButton.tintColor = [UIColor systemBlueColor];
    self.jailbreakDetectionInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.jailbreakDetectionInfoButton addTarget:self action:@selector(showJailbreakDetectionInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.jailbreakDetectionInfoButton];
    
    // Jailbreak Detection Bypass toggle switch
    self.jailbreakDetectionToggleSwitch = [[UISwitch alloc] init];
    self.jailbreakDetectionToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.jailbreakDetectionToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Check if jailbreak detection bypass is enabled
    BOOL jailbreakDetectionEnabled = [self.securitySettings boolForKey:@"jailbreakDetectionEnabled"];
    [self.jailbreakDetectionToggleSwitch setOn:jailbreakDetectionEnabled animated:NO];
    
    [self.jailbreakDetectionToggleSwitch addTarget:self action:@selector(jailbreakDetectionToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.jailbreakDetectionToggleSwitch];
    
    // Position control under the profile indicator control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:180], // Position below Profile Indicator control
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:60],
        
        [self.jailbreakDetectionLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.jailbreakDetectionLabel.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.jailbreakDetectionLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.jailbreakDetectionInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.jailbreakDetectionInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        [self.jailbreakDetectionToggleSwitch.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.jailbreakDetectionToggleSwitch.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor]
    ]];
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
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:260], // Position below Jailbreak Detection control
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
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:340], // Position below Network Data Spoof control
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

- (void)matrixToggleChanged:(UISwitch *)sender {
    self.matrixRainEnabled = sender.isOn;
    [self.securitySettings setBool:self.matrixRainEnabled forKey:@"matrixRainEnabled"];
    
    if (self.matrixRainEnabled) {
        [self.matrixRainView startAnimation];
    } else {
        [self.matrixRainView stopAnimation];
    }
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)profileIndicatorToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // Save setting immediately and synchronize
    [self.securitySettings setBool:enabled forKey:@"profileIndicatorEnabled"];
    [self.securitySettings synchronize];
    
    // Regular in-process notification with all necessary context
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(enabled) forKey:@"enabled"];
    [userInfo setObject:@"SecurityTabView" forKey:@"sender"];
    [userInfo setObject:[NSDate date] forKey:@"timestamp"];
    
    // Post notification immediately on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.toggleProfileIndicator" 
                                                            object:nil 
                                                          userInfo:userInfo];
    });
    
    // Also send Darwin notification to reach SpringBoard
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    NSString *notificationName = enabled ? @"com.hydra.projectx.enableProfileIndicator" : @"com.hydra.projectx.disableProfileIndicator";
    
    // Post the Darwin notification synchronously to ensure immediate handling
    CFNotificationCenterPostNotification(darwinCenter, (__bridge CFStringRef)notificationName, NULL, NULL, YES);
    
    PXLog(@"Profile indicator %@, saved to user defaults: %d, Darwin notification sent: %@", 
           enabled ? @"enabled" : @"disabled", 
           [self.securitySettings boolForKey:@"profileIndicatorEnabled"],
           notificationName);
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)jailbreakDetectionToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;

    // 1) Persist to the security settings plist (source of truth)
    NSString *securitySettingsPath = @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
    NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
    settingsDict[@"jailbreakDetectionEnabled"] = @(enabled);
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:settingsDict
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:nil];
    if (plistData) {
        [plistData writeToFile:securitySettingsPath atomically:YES];
    }

    // 2) Update NSUserDefaults suites
    NSArray *suiteNames = @[
        @"com.weaponx.securitySettings",
        @"com.hydra.projectx.SecuritySettings",
        @"com.hydra.projectx"
    ];
    for (NSString *suiteName in suiteNames) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults setBool:enabled forKey:@"jailbreakDetectionEnabled"];
        [defaults synchronize];
    }
    [self.securitySettings setBool:enabled forKey:@"jailbreakDetectionEnabled"];
    [self.securitySettings synchronize];

    // 3) Notify tweaks/processes
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter,
                                            CFSTR("com.hydra.projectx.settings.changed"),
                                            NULL,
                                            NULL,
                                            YES);
        CFNotificationCenterPostNotification(darwinCenter,
                                            CFSTR("com.hydra.projectx.jailbreakBypassChanged"),
                                            NULL,
                                            NULL,
                                            YES);
    }

    // 4) Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)networkDataSpoofToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // 1. Update plist file - THE SOURCE OF TRUTH
    NSString *securitySettingsPath = @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
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

- (void)showMatrixInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Matrix Rain Effect"
                               message:@"Enables the Matrix-style rain animation in the background of the Security tab. This effect is optimized to use minimal system resources."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction 
                              actionWithTitle:@"OK" 
                              style:UIAlertActionStyleDefault 
                              handler:nil];
    
    [alert addAction:okAction];
    
    // Find top view controller to present the alert
    UIViewController *rootVC = nil;
    
    // For iOS 13 and above, use the window scene approach
    if (@available(iOS 13.0, *)) {
        // Cast to the right type to avoid incompatible pointer types warning
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
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
        if (!rootVC && connectedScenes.count > 0) {
            for (UIScene *scene in connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    rootVC = windowScene.windows.firstObject.rootViewController;
                    if (rootVC) break;
                }
            }
        }
    } else {
        // Fallback for iOS 12 and below
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
#pragma clang diagnostic pop
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)showProfileIndicatorInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Profile Indicator"
                               message:@"Shows a floating indicator with your current profile number on screen at all times. This helps you always know which identity profile is active on your device. Also by tapping on it can open the app."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction 
                              actionWithTitle:@"OK" 
                              style:UIAlertActionStyleDefault 
                              handler:nil];
    
    [alert addAction:okAction];
    
    // Find top view controller to present the alert
    UIViewController *rootVC = nil;
    
    // For iOS 13 and above, use the window scene approach
    if (@available(iOS 13.0, *)) {
        // Cast to the right type to avoid incompatible pointer types warning
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
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
        if (!rootVC && connectedScenes.count > 0) {
            for (UIScene *scene in connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    rootVC = windowScene.windows.firstObject.rootViewController;
                    if (rootVC) break;
                }
            }
        }
    } else {
        // Fallback for iOS 12 and below
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
#pragma clang diagnostic pop
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)showJailbreakDetectionInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Jailbreak Detection Bypass"
                               message:@"Enables the Jailbreak Detection Bypass feature. This feature helps you bypass certain security measures that might be in place to prevent unauthorized access to your device."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction 
                              actionWithTitle:@"OK" 
                              style:UIAlertActionStyleDefault 
                              handler:nil];
    
    [alert addAction:okAction];
    
    // Find top view controller to present the alert
    UIViewController *rootVC = nil;
    
    // For iOS 13 and above, use the window scene approach
    if (@available(iOS 13.0, *)) {
        // Cast to the right type to avoid incompatible pointer types warning
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
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
        if (!rootVC && connectedScenes.count > 0) {
            for (UIScene *scene in connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    rootVC = windowScene.windows.firstObject.rootViewController;
                    if (rootVC) break;
                }
            }
        }
    } else {
        // Fallback for iOS 12 and below
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
#pragma clang diagnostic pop
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
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

- (void)setupVPNDetectionBypassControl:(UIView *)contentView {
    // Create a glassmorphic control for VPN/PROXY Detection Bypass
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];

    // Label
    self.vpnDetectionLabel = [[UILabel alloc] init];
    self.vpnDetectionLabel.text = @"VPN/PROXY Detection Bypass";
    self.vpnDetectionLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.vpnDetectionLabel.textColor = [UIColor labelColor];
    self.vpnDetectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.vpnDetectionLabel];

    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];

    self.vpnDetectionInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.vpnDetectionInfoButton.tintColor = [UIColor systemBlueColor];
    self.vpnDetectionInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.vpnDetectionInfoButton addTarget:self action:@selector(showVPNDetectionInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.vpnDetectionInfoButton];

    // Toggle
    self.vpnDetectionToggleSwitch = [[UISwitch alloc] init];
    self.vpnDetectionToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.vpnDetectionToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL enabled = [self.securitySettings boolForKey:@"vpnDetectionBypassEnabled"];
    [self.vpnDetectionToggleSwitch setOn:enabled animated:NO];
    [self.vpnDetectionToggleSwitch addTarget:self action:@selector(vpnDetectionToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:self.vpnDetectionToggleSwitch];

    // Position above Setup Alert Checks (e.g., top: 790)
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1470],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:60],

        [self.vpnDetectionLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.vpnDetectionLabel.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],

        [infoBgView.leadingAnchor constraintEqualToAnchor:self.vpnDetectionLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],

        [self.vpnDetectionInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.vpnDetectionInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],

        [self.vpnDetectionToggleSwitch.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [self.vpnDetectionToggleSwitch.centerYAnchor constraintEqualToAnchor:controlView.contentView.centerYAnchor]
    ]];
}

- (void)setupAlertChecksSection:(UIView *)contentView {
    // Create a glassmorphic container for alert checks
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Section title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"! SETUP ALERT CHECKS";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor systemRedColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:titleLabel];
    
    // Add "Recommended" label
    UILabel *recommendedLabel = [[UILabel alloc] init];
    recommendedLabel.text = @"(Recommended)";
    recommendedLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    recommendedLabel.textColor = [UIColor systemGrayColor];
    recommendedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:recommendedLabel];
    
    // Bluetooth alert item with checkmark
    UILabel *bluetoothLabel = [[UILabel alloc] init];
    bluetoothLabel.text = @"✓ 1 TURN OFF BLUETOOTH";
    bluetoothLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    bluetoothLabel.textColor = [UIColor labelColor];
    bluetoothLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bluetoothLabel];
    
    // Apple ID logout item with checkmark
    UILabel *appleIDLabel = [[UILabel alloc] init];
    appleIDLabel.text = @"✓ 2 LOGOUT APPLE ID";
    appleIDLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    appleIDLabel.textColor = [UIColor labelColor];
    appleIDLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:appleIDLabel];
    
    // Notification item with checkmark
    UILabel *notificationLabel = [[UILabel alloc] init];
    notificationLabel.text = @"✓ 3 DONT ALLOW NOTIFICATION/TRACKING";
    notificationLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    notificationLabel.textColor = [UIColor labelColor];
    notificationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:notificationLabel];

    // Brightness auto item with checkmark
    UILabel *brightnessLabel = [[UILabel alloc] init];
    brightnessLabel.text = @"✓ 4 SET BRIGHTNESS TO AUTO";
    brightnessLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    brightnessLabel.textColor = [UIColor labelColor];
    brightnessLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:brightnessLabel];
    
    // Touch ID & Passcode item with checkmark
    UILabel *touchIDLabel = [[UILabel alloc] init];
    touchIDLabel.text = @"✓ 5 REMOVE TOUCH ID & PASSCODE";
    touchIDLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    touchIDLabel.textColor = [UIColor labelColor];
    touchIDLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:touchIDLabel];
    
    // Clean var from RootHide app item with checkmark
    UILabel *cleanVarLabel = [[UILabel alloc] init];
    cleanVarLabel.text = @"✓ 6 CLEAN VAR FROM ROOTHIDE APP";
    cleanVarLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cleanVarLabel.textColor = [UIColor labelColor];
    cleanVarLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:cleanVarLabel];
    
    // Position control between app version spoofing and copyright
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:self.vpnDetectionLabel.superview.bottomAnchor constant:15], // Directly below VPN/PROXY Detection Bypass card
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:215], // Increased height for six items
        
        // Position title at the top
        [titleLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        [titleLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position "Recommended" label to the right of the title
        [recommendedLabel.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:8],
        [recommendedLabel.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:-1],
        
        // Position item 1 below the title
        [bluetoothLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
        [bluetoothLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position item 2 below item 1
        [appleIDLabel.topAnchor constraintEqualToAnchor:bluetoothLabel.bottomAnchor constant:5],
        [appleIDLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position item 3 below item 2
        [notificationLabel.topAnchor constraintEqualToAnchor:appleIDLabel.bottomAnchor constant:5],
        [notificationLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position item 4 below item 3
        [brightnessLabel.topAnchor constraintEqualToAnchor:notificationLabel.bottomAnchor constant:5],
        [brightnessLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position item 5 below item 4
        [touchIDLabel.topAnchor constraintEqualToAnchor:brightnessLabel.bottomAnchor constant:5],
        [touchIDLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        // Position item 6 below item 5
        [cleanVarLabel.topAnchor constraintEqualToAnchor:touchIDLabel.bottomAnchor constant:5],
        [cleanVarLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20]
    ]];
}

#pragma mark - Time Spoofing Control

- (void)setupTimeSpoofingControl:(UIView *)contentView {
    // Create glassmorphic control
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    controlView.tag = 2001;
    [contentView addSubview:controlView];

    // Label
    UILabel *label = [[UILabel alloc] init];
    label.text = @"Time spoofing using IP/location";
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:label];
    
    // IP Label
    self.ipLabel = [[UILabel alloc] init];
    self.ipLabel.font = [UIFont systemFontOfSize:14];
    self.ipLabel.textColor = [UIColor secondaryLabelColor];
    self.ipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.ipLabel.textAlignment = NSTextAlignmentLeft;
    self.ipLabel.numberOfLines = 2;
    self.ipLabel.hidden = [self.securitySettings integerForKey:@"timeSpoofingMode"] != 1;
    [controlView.contentView addSubview:self.ipLabel];

    // Location label (shares the same position as IP label)
    self.locationLabel = [[UILabel alloc] init];
    self.locationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.locationLabel.font = [UIFont systemFontOfSize:14];
    self.locationLabel.textColor = [UIColor secondaryLabelColor];
    self.locationLabel.textAlignment = NSTextAlignmentLeft;
    self.locationLabel.numberOfLines = 2;
    self.locationLabel.hidden = [self.securitySettings integerForKey:@"timeSpoofingMode"] != 2;
    [controlView.contentView addSubview:self.locationLabel];

    // Info button
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];

    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.tintColor = [UIColor systemBlueColor];
    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [infoButton addTarget:self action:@selector(showTimeSpoofingInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:infoButton];

    // Segmented control
    NSArray *segments = @[@"OFF", @"USE IP", @"USE LOCATION"];
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:segments];
    segment.translatesAutoresizingMaskIntoConstraints = NO;
    NSInteger savedValue = [self.securitySettings integerForKey:@"timeSpoofingMode"];
    if (savedValue < 0 || savedValue > 2) savedValue = 0;
    [segment setSelectedSegmentIndex:savedValue];
    [segment addTarget:self action:@selector(timeSpoofingModeChanged:) forControlEvents:UIControlEventValueChanged];
    [controlView.contentView addSubview:segment];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1780],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:140],
        
        [label.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        [label.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        
        [infoBgView.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [infoBgView.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [infoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [infoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        [segment.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:14],
        [segment.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [segment.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [segment.heightAnchor constraintEqualToConstant:32],
        
        // Position IP label below segmented control
        [self.ipLabel.topAnchor constraintEqualToAnchor:segment.bottomAnchor constant:10],
        [self.ipLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.ipLabel.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        
        // Position location label in the SAME position as IP label (they will never be visible at the same time)
        [self.locationLabel.topAnchor constraintEqualToAnchor:segment.bottomAnchor constant:10],
        [self.locationLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.locationLabel.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20]
    ]];
}

// Helper method to convert a timestamp to a "time ago" format
- (NSString *)timeAgoFromTimestamp:(NSString *)timestamp {
    if (!timestamp) return nil;
    
    // Create date formatter to parse the stored timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *date = [formatter dateFromString:timestamp];
    
    if (!date) {
        // Try to parse timestamp from a NSTimeInterval if stored that way
        NSNumber *timestampNum = nil;
        if ([timestamp doubleValue] > 0) {
            timestampNum = @([timestamp doubleValue]);
        }
        
        if (timestampNum) {
            date = [NSDate dateWithTimeIntervalSince1970:[timestampNum doubleValue]];
        } else {
            return @"unknown time";
        }
    }
    
    NSTimeInterval timeSince = -[date timeIntervalSinceNow];
    
    if (timeSince < 60) {
        return @"just now";
    } else if (timeSince < 3600) {
        int minutes = (int)(timeSince / 60);
        return [NSString stringWithFormat:@"%d %@ ago", minutes, minutes == 1 ? @"minute" : @"minutes"];
    } else if (timeSince < 86400) {
        int hours = (int)(timeSince / 3600);
        return [NSString stringWithFormat:@"%d %@ ago", hours, hours == 1 ? @"hour" : @"hours"];
    } else if (timeSince < 2592000) { // 30 days
        int days = (int)(timeSince / 86400);
        return [NSString stringWithFormat:@"%d %@ ago", days, days == 1 ? @"day" : @"days"];
    } else if (timeSince < 31536000) { // 365 days
        int months = (int)(timeSince / 2592000);
        return [NSString stringWithFormat:@"%d %@ ago", months, months == 1 ? @"month" : @"months"];
    } else {
        int years = (int)(timeSince / 31536000);
        return [NSString stringWithFormat:@"%d %@ ago", years, years == 1 ? @"year" : @"years"];
    }
}

- (void)timeSpoofingModeChanged:(UISegmentedControl *)sender {
    NSInteger selected = sender.selectedSegmentIndex;
    [self.securitySettings setInteger:selected forKey:@"timeSpoofingMode"];
    [self.securitySettings synchronize];
    
    // Show/hide the appropriate labels
    self.ipLabel.hidden = selected != 1;
    self.locationLabel.hidden = selected != 2;

    // Update IP data only when IP mode is selected
    if (selected == 1) {
        // Get IP data from the iplocationtime.plist file
        NSDictionary *ipData = [IPStatusCacheManager getPublicIPData];
        NSString *ip = ipData[@"publicIP"];
        NSString *flagEmoji = ipData[@"ipFlagEmoji"];
        NSString *timestamp = ipData[@"ipTimestamp"];
        
        if (ip) {
            // Create attributed string for IP with country flag on first line
            NSMutableAttributedString *attributedString;
            if (flagEmoji) {
                attributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"IP: %@ %@", flagEmoji, ip]];
            } else {
                attributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"IP: %@", ip]];
            }
            
            // Add timestamp in "time ago" format on a new line with smaller font
            if (timestamp) {
                NSString *timeAgo = [self timeAgoFromTimestamp:timestamp];
                if (timeAgo) {
                    [attributedString appendAttributedString:[[NSAttributedString alloc] 
                        initWithString:[NSString stringWithFormat:@"\nRecorded: %@", timeAgo]
                        attributes:@{
                            NSFontAttributeName: [UIFont systemFontOfSize:10],
                            NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                        }]];
                }
            }
            
            self.ipLabel.attributedText = attributedString;
        } else {
            // Fallback to old method if no data in plist
            NSString *fallbackIp = [[IPMonitorService sharedInstance] loadLastKnownIP];
            if (fallbackIp && [fallbackIp length] > 0) {
                self.ipLabel.text = [NSString stringWithFormat:@"IP: %@", fallbackIp];
            } else {
                self.ipLabel.text = @"IP: Not available";
            }
        }
    }
    
    // Update location data only when location mode is selected
    if (selected == 2) {
        // Get location data from the iplocationtime.plist file
        NSDictionary *locationData = [IPStatusCacheManager getPinnedLocationData];
        NSNumber *latitude = locationData[@"latitude"];
        NSNumber *longitude = locationData[@"longitude"];
        NSString *flagEmoji = locationData[@"locationFlagEmoji"];
        NSString *timestamp = locationData[@"locationTimestamp"];
        
        if (latitude && longitude) {
            // Create attributed string for location with country flag on first line
            NSMutableAttributedString *attributedString;
            if (flagEmoji) {
                attributedString = [[NSMutableAttributedString alloc] 
                    initWithString:[NSString stringWithFormat:@"Location: %@ %.6f, %.6f", 
                                  flagEmoji, [latitude doubleValue], [longitude doubleValue]]];
            } else {
                attributedString = [[NSMutableAttributedString alloc] 
                    initWithString:[NSString stringWithFormat:@"Location: %.6f, %.6f", 
                                  [latitude doubleValue], [longitude doubleValue]]];
            }
            
            // Add timestamp in "time ago" format on a new line with smaller font
            if (timestamp) {
                NSString *timeAgo = [self timeAgoFromTimestamp:timestamp];
                if (timeAgo) {
                    [attributedString appendAttributedString:[[NSAttributedString alloc] 
                        initWithString:[NSString stringWithFormat:@"\nRecorded: %@", timeAgo]
                        attributes:@{
                            NSFontAttributeName: [UIFont systemFontOfSize:10],
                            NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                        }]];
                }
            }
            
            self.locationLabel.attributedText = attributedString;
        } else {
            // Fallback to old method if no data in plist
        NSDictionary *pinned = [[LocationSpoofingManager sharedManager] loadSpoofingLocation];
        if (pinned && pinned[@"latitude"] && pinned[@"longitude"]) {
                self.locationLabel.text = [NSString stringWithFormat:@"Location: %.6f, %.6f", 
                                          [pinned[@"latitude"] doubleValue], [pinned[@"longitude"] doubleValue]];
        } else {
                self.locationLabel.text = @"Location: Not available";
            }
        }
    }
}

- (void)showTimeSpoofingInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Time Spoofing using IP/location"
        message:@"Choose how the system should spoof time:\n\n• OFF - Disables time spoofing\n• USE IP - Uses your public IP address to determine time zone, displays with country flag\n• USE LOCATION - Uses your pinned location to determine time zone, displays with country flag\n\nTime data is stored in the iplocationtime.plist file and includes timestamp information."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupCopyrightLabel:(UIView *)contentView {
    // Create copyright label
    self.copyrightLabel = [[UILabel alloc] init];
    self.copyrightLabel.text = @" HYDRA SECURE SYSTEMS • ALL RIGHTS RESERVED";
    self.copyrightLabel.font = [UIFont fontWithName:@"Menlo" size:10.0] ?: [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    self.copyrightLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.8]; // Matrix green
    self.copyrightLabel.textAlignment = NSTextAlignmentCenter;
    self.copyrightLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.copyrightLabel.alpha = 0.7;
    [contentView addSubview:self.copyrightLabel];
    
    // Add subtle glow effect
    self.copyrightLabel.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0].CGColor;
    self.copyrightLabel.layer.shadowOffset = CGSizeZero;
    self.copyrightLabel.layer.shadowRadius = 3.0;
    self.copyrightLabel.layer.shadowOpacity = 0.3;
    
    // Position at the bottom of the page after the Canvas Fingerprinting control
    [NSLayoutConstraint activateConstraints:@[
        [self.copyrightLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.copyrightLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.copyrightLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:2220], // Positioned after Canvas Fingerprinting
        [self.copyrightLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30] // More bottom padding
    ]];
    
    // Add subtle pulsing animation
    [self animateCopyrightLabel];
}

- (void)animateCopyrightLabel {
    [UIView animateWithDuration:2.5 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
        self.copyrightLabel.alpha = 0.5;
    } completion:^(BOOL finished) {
        self.copyrightLabel.alpha = 0.7;
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Pause matrix animation when view is not visible
    [self.matrixRainView stopAnimation];
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

- (void)vpnDetectionToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"vpnDetectionBypassEnabled"];
    [self.securitySettings synchronize];
    // TODO: Add logic to enable/disable VPN/Proxy detection bypass in your backend
}

- (void)showVPNDetectionInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"VPN/PROXY Detection Bypass"
                               message:@"Enables bypassing VPN/Proxy detection in apps. When enabled, apps will not be able to detect that you are using a VPN or Proxy."
                               preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // We don't use the table view anymore, but need to implement the required method
    return 0;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Check if time spoofing is enabled and which mode it's using
    NSInteger timeSpoofingMode = [self.securitySettings integerForKey:@"timeSpoofingMode"];
    
    // Only update the IP label if we're using IP-based time spoofing (mode 1)
    if (timeSpoofingMode == 1) {
        // Get IP data from the iplocationtime.plist file
        NSDictionary *ipData = [IPStatusCacheManager getPublicIPData];
        NSString *ip = ipData[@"publicIP"];
        NSString *flagEmoji = ipData[@"ipFlagEmoji"];
        NSString *timestamp = ipData[@"ipTimestamp"];
        
        if (ip) {
            // Create attributed string for IP with country flag on first line
            NSMutableAttributedString *attributedString;
            if (flagEmoji) {
                attributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"IP: %@ %@", flagEmoji, ip]];
    } else {
                attributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"IP: %@", ip]];
            }
            
            // Add timestamp in "time ago" format on a new line with smaller font
            if (timestamp) {
                NSString *timeAgo = [self timeAgoFromTimestamp:timestamp];
                if (timeAgo) {
                    [attributedString appendAttributedString:[[NSAttributedString alloc] 
                        initWithString:[NSString stringWithFormat:@"\nRecorded: %@", timeAgo]
                        attributes:@{
                            NSFontAttributeName: [UIFont systemFontOfSize:10],
                            NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                        }]];
                }
            }
            
            self.ipLabel.attributedText = attributedString;
        } else {
            // Fallback to old method if no data in plist
            NSString *fallbackIp = [[IPMonitorService sharedInstance] loadLastKnownIP];
            if (fallbackIp && [fallbackIp length] > 0) {
                self.ipLabel.text = [NSString stringWithFormat:@"IP: %@", fallbackIp];
            } else {
                self.ipLabel.text = @"IP: Not available";
            }
        }
    }
    
    // Only update the location label if we're using location-based time spoofing (mode 2)
    if (timeSpoofingMode == 2) {
        // Get location data from the iplocationtime.plist file
        NSDictionary *locationData = [IPStatusCacheManager getPinnedLocationData];
        NSNumber *latitude = locationData[@"latitude"];
        NSNumber *longitude = locationData[@"longitude"];
        NSString *flagEmoji = locationData[@"locationFlagEmoji"];
        NSString *timestamp = locationData[@"locationTimestamp"];
        
        if (latitude && longitude) {
            // Create attributed string for location with country flag on first line
            NSMutableAttributedString *attributedString;
            if (flagEmoji) {
                attributedString = [[NSMutableAttributedString alloc] 
                    initWithString:[NSString stringWithFormat:@"Location: %@ %.6f, %.6f", 
                                   flagEmoji, [latitude doubleValue], [longitude doubleValue]]];
            } else {
                attributedString = [[NSMutableAttributedString alloc] 
                    initWithString:[NSString stringWithFormat:@"Location: %.6f, %.6f", 
                                  [latitude doubleValue], [longitude doubleValue]]];
            }
            
            // Add timestamp in "time ago" format on a new line with smaller font
            if (timestamp) {
                NSString *timeAgo = [self timeAgoFromTimestamp:timestamp];
                if (timeAgo) {
                    [attributedString appendAttributedString:[[NSAttributedString alloc] 
                        initWithString:[NSString stringWithFormat:@"\nRecorded: %@", timeAgo]
                        attributes:@{
                            NSFontAttributeName: [UIFont systemFontOfSize:10],
                            NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                        }]];
                }
            }
            
            self.locationLabel.attributedText = attributedString;
        } else {
            // Fallback to old method if no data in plist
    NSDictionary *locationDict = [[LocationSpoofingManager sharedManager] loadSpoofingLocation];
    if (locationDict && locationDict[@"latitude"] && locationDict[@"longitude"]) {
        double lat = [locationDict[@"latitude"] doubleValue];
        double lon = [locationDict[@"longitude"] doubleValue];
                self.locationLabel.text = [NSString stringWithFormat:@"Location: %.6f, %.6f", lat, lon];
    } else {
                self.locationLabel.text = @"Location: Not available";
    }
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // We don't use the table view anymore, but need to implement the required method
    return [[UITableViewCell alloc] init];
}

- (void)setupDeviceSpecificSpoofingControl:(UIView *)contentView {
    // Create a glassmorphic control for Device Specific Spoofing
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Device specific spoofing label
    self.deviceSpoofingLabel = [[UILabel alloc] init];
    self.deviceSpoofingLabel.text = @"Device Specific Spoofing";
    self.deviceSpoofingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.deviceSpoofingLabel.textColor = [UIColor labelColor];
    self.deviceSpoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.deviceSpoofingLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.tintColor = [UIColor systemBlueColor];
    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [infoButton addTarget:self action:@selector(showDeviceSpoofingInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:infoButton];
    
    // Container view for bottom row elements
    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];
    
    // Create Apple icon with circular background
    UIView *appleBgView = [[UIView alloc] init];
    appleBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    appleBgView.layer.cornerRadius = 12;
    appleBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:appleBgView];
    
    UIImageView *appleIconView = [[UIImageView alloc] init];
    appleIconView.image = [UIImage systemImageNamed:@"apple.logo"];
    appleIconView.tintColor = [UIColor systemBlueColor];
    appleIconView.contentMode = UIViewContentModeScaleAspectFit;
    appleIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [appleBgView addSubview:appleIconView];
    
    // Access button for Device Specific Spoofing
    self.deviceSpoofingAccessButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = @"Access";
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] forKey:NSFontAttributeName];
            return newAttributes;
        };
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 12, 4, 12);
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseForegroundColor = [UIColor whiteColor];
        [self.deviceSpoofingAccessButton safeSetConfiguration:config];
    } else {
        [self.deviceSpoofingAccessButton setTitle:@"Access" forState:UIControlStateNormal];
        self.deviceSpoofingAccessButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.deviceSpoofingAccessButton.backgroundColor = [UIColor systemBlueColor];
        self.deviceSpoofingAccessButton.layer.cornerRadius = 15;
        self.deviceSpoofingAccessButton.tintColor = [UIColor whiteColor];
        // contentEdgeInsets is deprecated but needed for iOS 14 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.deviceSpoofingAccessButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        #pragma clang diagnostic pop
    }
    self.deviceSpoofingAccessButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.deviceSpoofingAccessButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.deviceSpoofingAccessButton.layer.shadowOpacity = 0.2;
    self.deviceSpoofingAccessButton.layer.shadowRadius = 2;
    self.deviceSpoofingAccessButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deviceSpoofingAccessButton addTarget:self action:@selector(deviceSpoofingAccessTapped:) forControlEvents:UIControlEventTouchUpInside];
    [bottomRowContainer addSubview:self.deviceSpoofingAccessButton];
    
    // Device spoofing toggle switch
    self.deviceSpoofingToggleSwitch = [[UISwitch alloc] init];
    self.deviceSpoofingToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.deviceSpoofingToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Check if device spoofing is enabled
    BOOL deviceSpoofingEnabled = [self.securitySettings boolForKey:@"deviceSpoofingEnabled"];
    [self.deviceSpoofingToggleSwitch setOn:deviceSpoofingEnabled animated:NO];
    
    [self.deviceSpoofingToggleSwitch addTarget:self action:@selector(deviceSpoofingToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.deviceSpoofingToggleSwitch];

    // Safari/Auth Stack spoofing row (applies to SafariViewService/WebKit/ASWebAuthenticationSession)
    UIView *safariRow = [[UIView alloc] init];
    safariRow.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:safariRow];

    self.safariStackSpoofingLabel = [[UILabel alloc] init];
    self.safariStackSpoofingLabel.text = @"Safari/Auth Stack Spoofing";
    self.safariStackSpoofingLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.safariStackSpoofingLabel.textColor = [UIColor secondaryLabelColor];
    self.safariStackSpoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [safariRow addSubview:self.safariStackSpoofingLabel];

    self.safariStackSpoofingToggleSwitch = [[UISwitch alloc] init];
    self.safariStackSpoofingToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.safariStackSpoofingToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    id safariPref = [self.securitySettings objectForKey:@"safariStackSpoofEnabled"]; // may be nil
    BOOL safariEnabled = safariPref ? [safariPref boolValue] : deviceSpoofingEnabled;
    [self.safariStackSpoofingToggleSwitch setOn:safariEnabled animated:NO];
    [self.safariStackSpoofingToggleSwitch addTarget:self action:@selector(safariStackSpoofingToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [safariRow addSubview:self.safariStackSpoofingToggleSwitch];

    // WebCompat iOS range row (generation-only; does not modify existing profiles)
    UIView *webCompatRow = [[UIView alloc] init];
    webCompatRow.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:webCompatRow];

    self.webCompatIOSRangeLabel = [[UILabel alloc] init];
    self.webCompatIOSRangeLabel.text = @"WebCompat iOS Range (<= 16.3.1)";
    self.webCompatIOSRangeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.webCompatIOSRangeLabel.textColor = [UIColor secondaryLabelColor];
    self.webCompatIOSRangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [webCompatRow addSubview:self.webCompatIOSRangeLabel];

    self.webCompatIOSRangeToggleSwitch = [[UISwitch alloc] init];
    self.webCompatIOSRangeToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.webCompatIOSRangeToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL webCompatEnabled = [self.securitySettings boolForKey:@"webCompatIOSRangeEnabled"];
    [self.webCompatIOSRangeToggleSwitch setOn:webCompatEnabled animated:NO];
    [self.webCompatIOSRangeToggleSwitch addTarget:self action:@selector(webCompatIOSRangeToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [webCompatRow addSubview:self.webCompatIOSRangeToggleSwitch];

    self.webCompatIOSRangeWarningLabel = [[UILabel alloc] init];
    self.webCompatIOSRangeWarningLabel.text = @"WebCompat is ON, but this profile uses iOS > 16.3.1. Regenerate to apply.";
    self.webCompatIOSRangeWarningLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.webCompatIOSRangeWarningLabel.textColor = [UIColor systemOrangeColor];
    self.webCompatIOSRangeWarningLabel.numberOfLines = 2;
    self.webCompatIOSRangeWarningLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.webCompatIOSRangeWarningLabel];

    // Full spoof test mode row (forces Safari/Auth stack spoofing for testing)
    UIView *fullSpoofRow = [[UIView alloc] init];
    fullSpoofRow.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:fullSpoofRow];

    self.fullSpoofTestModeLabel = [[UILabel alloc] init];
    self.fullSpoofTestModeLabel.text = @"Full Spoof Test Mode";
    self.fullSpoofTestModeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.fullSpoofTestModeLabel.textColor = [UIColor secondaryLabelColor];
    self.fullSpoofTestModeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [fullSpoofRow addSubview:self.fullSpoofTestModeLabel];

    self.fullSpoofTestModeToggleSwitch = [[UISwitch alloc] init];
    self.fullSpoofTestModeToggleSwitch.onTintColor = [UIColor systemRedColor];
    self.fullSpoofTestModeToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL fullSpoofEnabled = [self.securitySettings boolForKey:@"fullSpoofTestModeEnabled"];
    [self.fullSpoofTestModeToggleSwitch setOn:fullSpoofEnabled animated:NO];
    [self.fullSpoofTestModeToggleSwitch addTarget:self action:@selector(fullSpoofTestModeToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [fullSpoofRow addSubview:self.fullSpoofTestModeToggleSwitch];

    // UI scale spoof row (can cause UI zoom)
    UIView *uiScaleRow = [[UIView alloc] init];
    uiScaleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:uiScaleRow];

    self.displayUIScaleSpoofLabel = [[UILabel alloc] init];
    self.displayUIScaleSpoofLabel.text = @"UI Scale Spoof (Zoom UI)";
    self.displayUIScaleSpoofLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.displayUIScaleSpoofLabel.textColor = [UIColor secondaryLabelColor];
    self.displayUIScaleSpoofLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [uiScaleRow addSubview:self.displayUIScaleSpoofLabel];

    self.displayUIScaleSpoofToggleSwitch = [[UISwitch alloc] init];
    self.displayUIScaleSpoofToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.displayUIScaleSpoofToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    id uiScalePref = [self.securitySettings objectForKey:@"displayUIScaleSpoofEnabled"]; // may be nil
    BOOL uiScaleEnabled = uiScalePref ? [uiScalePref boolValue] : YES;
    [self.displayUIScaleSpoofToggleSwitch setOn:uiScaleEnabled animated:NO];
    [self.displayUIScaleSpoofToggleSwitch addTarget:self action:@selector(displayUIScaleSpoofToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [uiScaleRow addSubview:self.displayUIScaleSpoofToggleSwitch];
    
    // Enable/disable access button based on toggle state
    self.deviceSpoofingAccessButton.enabled = deviceSpoofingEnabled;
    if (!deviceSpoofingEnabled) {
        if ([UIButton buttonConfigurationClassExists]) {
            if (self.deviceSpoofingAccessButton.configuration) {
                UIButtonConfiguration *config = [self.deviceSpoofingAccessButton.configuration copy];
                config.background.backgroundColor = [UIColor systemGrayColor];
                [self.deviceSpoofingAccessButton safeSetConfiguration:config];
            }
            self.deviceSpoofingAccessButton.alpha = 0.6;
        } else {
            self.deviceSpoofingAccessButton.backgroundColor = [UIColor systemGrayColor];
            self.deviceSpoofingAccessButton.alpha = 0.6;
        }
    }
    
    // Position control under the network connection type control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:520], // Increased spacing below Network Connection Type
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:240], // Extra rows for Safari/Auth stack + WebCompat + Test toggles
        
        // Position label at the top
        [self.deviceSpoofingLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.deviceSpoofingLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        
        // Position info button to the right of the label
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.deviceSpoofingLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.deviceSpoofingLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [infoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [infoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        // Position bottom row container
        [bottomRowContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:self.deviceSpoofingLabel.bottomAnchor constant:10],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],

        // Safari row
        [safariRow.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [safariRow.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [safariRow.topAnchor constraintEqualToAnchor:bottomRowContainer.bottomAnchor constant:8],
        [safariRow.heightAnchor constraintEqualToConstant:30],

        [self.safariStackSpoofingLabel.leadingAnchor constraintEqualToAnchor:safariRow.leadingAnchor],
        [self.safariStackSpoofingLabel.centerYAnchor constraintEqualToAnchor:safariRow.centerYAnchor],

        [self.safariStackSpoofingToggleSwitch.trailingAnchor constraintEqualToAnchor:safariRow.trailingAnchor],
        [self.safariStackSpoofingToggleSwitch.centerYAnchor constraintEqualToAnchor:safariRow.centerYAnchor],

        // WebCompat row
        [webCompatRow.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [webCompatRow.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [webCompatRow.topAnchor constraintEqualToAnchor:safariRow.bottomAnchor constant:8],
        [webCompatRow.heightAnchor constraintEqualToConstant:30],

        [self.webCompatIOSRangeLabel.leadingAnchor constraintEqualToAnchor:webCompatRow.leadingAnchor],
        [self.webCompatIOSRangeLabel.centerYAnchor constraintEqualToAnchor:webCompatRow.centerYAnchor],

        [self.webCompatIOSRangeToggleSwitch.trailingAnchor constraintEqualToAnchor:webCompatRow.trailingAnchor],
        [self.webCompatIOSRangeToggleSwitch.centerYAnchor constraintEqualToAnchor:webCompatRow.centerYAnchor],

        // WebCompat warning label
        [self.webCompatIOSRangeWarningLabel.topAnchor constraintEqualToAnchor:webCompatRow.bottomAnchor constant:2],
        [self.webCompatIOSRangeWarningLabel.leadingAnchor constraintEqualToAnchor:webCompatRow.leadingAnchor],
        [self.webCompatIOSRangeWarningLabel.trailingAnchor constraintEqualToAnchor:webCompatRow.trailingAnchor],

        // Full spoof row
        [fullSpoofRow.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [fullSpoofRow.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [fullSpoofRow.topAnchor constraintEqualToAnchor:self.webCompatIOSRangeWarningLabel.bottomAnchor constant:8],
        [fullSpoofRow.heightAnchor constraintEqualToConstant:30],

        [self.fullSpoofTestModeLabel.leadingAnchor constraintEqualToAnchor:fullSpoofRow.leadingAnchor],
        [self.fullSpoofTestModeLabel.centerYAnchor constraintEqualToAnchor:fullSpoofRow.centerYAnchor],

        [self.fullSpoofTestModeToggleSwitch.trailingAnchor constraintEqualToAnchor:fullSpoofRow.trailingAnchor],
        [self.fullSpoofTestModeToggleSwitch.centerYAnchor constraintEqualToAnchor:fullSpoofRow.centerYAnchor],

        // UI scale row
        [uiScaleRow.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [uiScaleRow.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [uiScaleRow.topAnchor constraintEqualToAnchor:fullSpoofRow.bottomAnchor constant:8],
        [uiScaleRow.heightAnchor constraintEqualToConstant:30],

        [self.displayUIScaleSpoofLabel.leadingAnchor constraintEqualToAnchor:uiScaleRow.leadingAnchor],
        [self.displayUIScaleSpoofLabel.centerYAnchor constraintEqualToAnchor:uiScaleRow.centerYAnchor],

        [self.displayUIScaleSpoofToggleSwitch.trailingAnchor constraintEqualToAnchor:uiScaleRow.trailingAnchor],
        [self.displayUIScaleSpoofToggleSwitch.centerYAnchor constraintEqualToAnchor:uiScaleRow.centerYAnchor],

        // Position elements inside bottom row container
        [appleBgView.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [appleBgView.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [appleBgView.widthAnchor constraintEqualToConstant:24],
        [appleBgView.heightAnchor constraintEqualToConstant:24],
        
        [appleIconView.centerXAnchor constraintEqualToAnchor:appleBgView.centerXAnchor],
        [appleIconView.centerYAnchor constraintEqualToAnchor:appleBgView.centerYAnchor],
        [appleIconView.widthAnchor constraintEqualToConstant:16],
        [appleIconView.heightAnchor constraintEqualToConstant:16],
        
        [self.deviceSpoofingAccessButton.leadingAnchor constraintEqualToAnchor:appleBgView.trailingAnchor constant:10],
        [self.deviceSpoofingAccessButton.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.deviceSpoofingAccessButton.widthAnchor constraintEqualToConstant:90],
        [self.deviceSpoofingAccessButton.heightAnchor constraintEqualToConstant:30],
        
        [self.deviceSpoofingToggleSwitch.leadingAnchor constraintEqualToAnchor:self.deviceSpoofingAccessButton.trailingAnchor constant:10],
        [self.deviceSpoofingToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.deviceSpoofingToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor]
    ]];

    // Disable safari-stack toggle when global device spoofing is off
    self.safariStackSpoofingToggleSwitch.enabled = deviceSpoofingEnabled;
    self.safariStackSpoofingToggleSwitch.alpha = deviceSpoofingEnabled ? 1.0 : 0.5;

    // Disable WebCompat toggle when global device spoofing is off
    self.webCompatIOSRangeToggleSwitch.enabled = deviceSpoofingEnabled;
    self.webCompatIOSRangeToggleSwitch.alpha = deviceSpoofingEnabled ? 1.0 : 0.5;

    self.fullSpoofTestModeToggleSwitch.enabled = deviceSpoofingEnabled;
    self.fullSpoofTestModeToggleSwitch.alpha = deviceSpoofingEnabled ? 1.0 : 0.5;

    self.displayUIScaleSpoofToggleSwitch.enabled = deviceSpoofingEnabled;
    self.displayUIScaleSpoofToggleSwitch.alpha = deviceSpoofingEnabled ? 1.0 : 0.5;

    // Initial warning visibility
    NSString *currentIOSVersion = [[IdentifierManager sharedManager] currentValueForIdentifier:@"IOSVersion"];
    BOOL showWarning = deviceSpoofingEnabled && webCompatEnabled && currentIOSVersion.length && (PXCompareVersions(currentIOSVersion, @"16.3.1") == NSOrderedDescending);
    self.webCompatIOSRangeWarningLabel.hidden = !showWarning;

    self.webCompatIOSRangeWarningHeightConstraint = [self.webCompatIOSRangeWarningLabel.heightAnchor constraintEqualToConstant:(showWarning ? 24.0 : 0.0)];
    self.webCompatIOSRangeWarningHeightConstraint.active = YES;
}

- (void)webCompatIOSRangeToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;

    [self.securitySettings setBool:enabled forKey:@"webCompatIOSRangeEnabled"];
    [self.securitySettings synchronize];

    NSString *currentIOSVersion = [[IdentifierManager sharedManager] currentValueForIdentifier:@"IOSVersion"];
    BOOL deviceSpoofingEnabled = [self.securitySettings boolForKey:@"deviceSpoofingEnabled"];
    BOOL showWarning = deviceSpoofingEnabled && enabled && currentIOSVersion.length && (PXCompareVersions(currentIOSVersion, @"16.3.1") == NSOrderedDescending);
    self.webCompatIOSRangeWarningLabel.hidden = !showWarning;
    if (self.webCompatIOSRangeWarningHeightConstraint) {
        self.webCompatIOSRangeWarningHeightConstraint.constant = showWarning ? 24.0 : 0.0;
    }

    // Broadcast changes so generators/tweaks can react.
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
    }
}

- (void)fullSpoofTestModeToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;

    [self.securitySettings setBool:enabled forKey:@"fullSpoofTestModeEnabled"];

    // In test mode, we want Safari/Auth stack spoofing ON for consistency.
    if (enabled) {
        [self.securitySettings setBool:YES forKey:@"safariStackSpoofEnabled"];
        if (self.safariStackSpoofingToggleSwitch) {
            [self.safariStackSpoofingToggleSwitch setOn:YES animated:YES];
        }
    }

    [self.securitySettings synchronize];

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.safariStackSpoofToggleChanged"), NULL, NULL, YES);
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
    }
}

- (void)displayUIScaleSpoofToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"displayUIScaleSpoofEnabled"];
    [self.securitySettings synchronize];

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
    }
}

- (void)safariStackSpoofingToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;

    // Persist user override; effective enablement still follows global deviceSpoofingEnabled.
    [self.securitySettings setBool:enabled forKey:@"safariStackSpoofEnabled"];
    [self.securitySettings synchronize];

    // Broadcast changes so all tweaks clear caches.
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.safariStackSpoofToggleChanged"), NULL, NULL, YES);
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
    }
}

- (void)showDeviceSpoofingInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Device Specific Spoofing"
                               message:@"Allows you to spoof device-specific information such as device model, hardware details, and system information to protect your privacy."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction 
                              actionWithTitle:@"OK" 
                              style:UIAlertActionStyleDefault 
                              handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deviceSpoofingToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // Save setting immediately and synchronize
    [self.securitySettings setBool:enabled forKey:@"deviceSpoofingEnabled"];
    [self.securitySettings synchronize];

    // Safari/Auth stack spoof toggle: default ON when global spoof is ON.
    if (self.safariStackSpoofingToggleSwitch) {
        self.safariStackSpoofingToggleSwitch.enabled = enabled;
        self.safariStackSpoofingToggleSwitch.alpha = enabled ? 1.0 : 0.5;

        if (enabled) {
            // Only auto-default if user hasn't explicitly set the key.
            if ([self.securitySettings objectForKey:@"safariStackSpoofEnabled"] == nil) {
                [self.safariStackSpoofingToggleSwitch setOn:YES animated:YES];
            }
        }
    }

    // WebCompat range toggle is only meaningful when device spoofing is enabled.
    if (self.webCompatIOSRangeToggleSwitch) {
        self.webCompatIOSRangeToggleSwitch.enabled = enabled;
        self.webCompatIOSRangeToggleSwitch.alpha = enabled ? 1.0 : 0.5;

        NSString *currentIOSVersion = [[IdentifierManager sharedManager] currentValueForIdentifier:@"IOSVersion"];
        BOOL webCompatEnabled = [self.securitySettings boolForKey:@"webCompatIOSRangeEnabled"];
        BOOL showWarning = enabled && webCompatEnabled && currentIOSVersion.length && (PXCompareVersions(currentIOSVersion, @"16.3.1") == NSOrderedDescending);
        self.webCompatIOSRangeWarningLabel.hidden = !showWarning;
        if (self.webCompatIOSRangeWarningHeightConstraint) {
            self.webCompatIOSRangeWarningHeightConstraint.constant = showWarning ? 24.0 : 0.0;
        }
    }

    if (self.fullSpoofTestModeToggleSwitch) {
        self.fullSpoofTestModeToggleSwitch.enabled = enabled;
        self.fullSpoofTestModeToggleSwitch.alpha = enabled ? 1.0 : 0.5;
    }

    if (self.displayUIScaleSpoofToggleSwitch) {
        self.displayUIScaleSpoofToggleSwitch.enabled = enabled;
        self.displayUIScaleSpoofToggleSwitch.alpha = enabled ? 1.0 : 0.5;
    }
    
    // Enable/disable access button based on toggle state
    self.deviceSpoofingAccessButton.enabled = enabled;
    
    // Animate alpha and background color change
    [UIView animateWithDuration:0.2 animations:^{
        if ([UIButton buttonConfigurationClassExists]) {
            UIButtonConfiguration *config = [self.deviceSpoofingAccessButton.configuration copy];
            if (enabled) {
                config.background.backgroundColor = [UIColor systemBlueColor];
                self.deviceSpoofingAccessButton.alpha = 1.0;
            } else {
                config.background.backgroundColor = [UIColor systemGrayColor];
                self.deviceSpoofingAccessButton.alpha = 0.6;
            }
            [self.deviceSpoofingAccessButton setConfiguration:config];
        } else {
            if (enabled) {
                self.deviceSpoofingAccessButton.alpha = 1.0;
                self.deviceSpoofingAccessButton.backgroundColor = [UIColor systemBlueColor];
            } else {
                self.deviceSpoofingAccessButton.alpha = 0.6;
                self.deviceSpoofingAccessButton.backgroundColor = [UIColor systemGrayColor];
            }
        }
    }];
    
    // Send notification about the setting change
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(enabled) forKey:@"enabled"];
    [userInfo setObject:@"SecurityTabView" forKey:@"sender"];
    
    // Post notification on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.toggleDeviceSpoofing" 
                                                            object:nil 
                                                          userInfo:userInfo];
    });

    // Darwin notifications for injected tweaks (cache invalidation)
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    if (darwinCenter) {
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.settings.changed"), NULL, NULL, YES);
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.toggleDeviceSpoofing"), NULL, NULL, YES);
    }
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)deviceSpoofingAccessTapped:(UIButton *)sender {
    // This will be implemented later to open the device specific spoofing tab
    if (!self.deviceSpoofingToggleSwitch.isOn) {
        return; // Don't allow access if toggle is off
    }
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    // Navigate to DeviceSpecificSpoofingViewController
    DeviceSpecificSpoofingViewController *vc = [[DeviceSpecificSpoofingViewController alloc] init];
    vc.hidesBottomBarWhenPushed = NO;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)setupAppVersionSpoofingControl:(UIView *)contentView {
    // Create a glassmorphic control for App Version Spoofing
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // App version spoofing label
    self.appVersionSpoofingLabel = [[UILabel alloc] init];
    self.appVersionSpoofingLabel.text = @"APP Specific Version Spoofing";
    self.appVersionSpoofingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.appVersionSpoofingLabel.textColor = [UIColor labelColor];
    self.appVersionSpoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.appVersionSpoofingLabel];
    
    // Info button with circular background
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.tintColor = [UIColor systemBlueColor];
    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [infoButton addTarget:self action:@selector(showAppVersionSpoofingInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:infoButton];
    
    // Container view for bottom row elements
    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];
    
    // Create App icon with circular background
    UIView *appBgView = [[UIView alloc] init];
    appBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    appBgView.layer.cornerRadius = 12;
    appBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:appBgView];
    
    UIImageView *appIconView = [[UIImageView alloc] init];
    appIconView.image = [UIImage systemImageNamed:@"app.badge"];
    appIconView.tintColor = [UIColor systemBlueColor];
    appIconView.contentMode = UIViewContentModeScaleAspectFit;
    appIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [appBgView addSubview:appIconView];
    
    // Access button for APP Version Spoofing
    self.appVersionSpoofingAccessButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = @"Access";
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] forKey:NSFontAttributeName];
            return newAttributes;
        };
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 12, 4, 12);
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseForegroundColor = [UIColor whiteColor];
        [self.appVersionSpoofingAccessButton safeSetConfiguration:config];
    } else {
        [self.appVersionSpoofingAccessButton setTitle:@"Access" forState:UIControlStateNormal];
        self.appVersionSpoofingAccessButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.appVersionSpoofingAccessButton.backgroundColor = [UIColor systemBlueColor];
        self.appVersionSpoofingAccessButton.layer.cornerRadius = 15;
        self.appVersionSpoofingAccessButton.tintColor = [UIColor whiteColor];
        // contentEdgeInsets is deprecated but needed for iOS 14 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.appVersionSpoofingAccessButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        #pragma clang diagnostic pop
    }
    self.appVersionSpoofingAccessButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.appVersionSpoofingAccessButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.appVersionSpoofingAccessButton.layer.shadowOpacity = 0.2;
    self.appVersionSpoofingAccessButton.layer.shadowRadius = 2;
    self.appVersionSpoofingAccessButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.appVersionSpoofingAccessButton addTarget:self action:@selector(appVersionSpoofingAccessTapped:) forControlEvents:UIControlEventTouchUpInside];
    [bottomRowContainer addSubview:self.appVersionSpoofingAccessButton];
    
    // App version spoofing toggle switch
    self.appVersionSpoofingToggleSwitch = [[UISwitch alloc] init];
    self.appVersionSpoofingToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.appVersionSpoofingToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Check if app version spoofing is enabled
    BOOL appVersionSpoofingEnabled = [self.securitySettings boolForKey:@"appVersionSpoofingEnabled"];
    [self.appVersionSpoofingToggleSwitch setOn:appVersionSpoofingEnabled animated:NO];
    
    [self.appVersionSpoofingToggleSwitch addTarget:self action:@selector(appVersionSpoofingToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.appVersionSpoofingToggleSwitch];
    
    // Enable/disable access button based on toggle state
    self.appVersionSpoofingAccessButton.enabled = appVersionSpoofingEnabled;
    if (!appVersionSpoofingEnabled) {
        if ([UIButton buttonConfigurationClassExists]) {
            if (self.appVersionSpoofingAccessButton.configuration) {
                UIButtonConfiguration *config = [self.appVersionSpoofingAccessButton.configuration copy];
                config.background.backgroundColor = [UIColor systemGrayColor];
                [self.appVersionSpoofingAccessButton safeSetConfiguration:config];
            }
            self.appVersionSpoofingAccessButton.alpha = 0.6;
        } else {
            self.appVersionSpoofingAccessButton.backgroundColor = [UIColor systemGrayColor];
            self.appVersionSpoofingAccessButton.alpha = 0.6;
        }
    }
    
    // Position control under the device specific spoofing control
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:780], // Increased spacing below Device Specific Spoofing
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:100], // Increased height to accommodate vertical layout
        
        // Position label at the top
        [self.appVersionSpoofingLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.appVersionSpoofingLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        
        // Position info button to the right of the label
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.appVersionSpoofingLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.appVersionSpoofingLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [infoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [infoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        // Position bottom row container
        [bottomRowContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:self.appVersionSpoofingLabel.bottomAnchor constant:15],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],
        
        // Position elements inside bottom row container
        [appBgView.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [appBgView.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [appBgView.widthAnchor constraintEqualToConstant:24],
        [appBgView.heightAnchor constraintEqualToConstant:24],
        
        [appIconView.centerXAnchor constraintEqualToAnchor:appBgView.centerXAnchor],
        [appIconView.centerYAnchor constraintEqualToAnchor:appBgView.centerYAnchor],
        [appIconView.widthAnchor constraintEqualToConstant:16],
        [appIconView.heightAnchor constraintEqualToConstant:16],
        
        [self.appVersionSpoofingAccessButton.leadingAnchor constraintEqualToAnchor:appBgView.trailingAnchor constant:10],
        [self.appVersionSpoofingAccessButton.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.appVersionSpoofingAccessButton.widthAnchor constraintEqualToConstant:90],
        [self.appVersionSpoofingAccessButton.heightAnchor constraintEqualToConstant:30],
        
        [self.appVersionSpoofingToggleSwitch.leadingAnchor constraintEqualToAnchor:self.appVersionSpoofingAccessButton.trailingAnchor constant:10],
        [self.appVersionSpoofingToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.appVersionSpoofingToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor]
    ]];
}

- (void)setupFixVersionControl:(UIView *)contentView {
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];

    self.fixVersionLabel = [[UILabel alloc] init];
    self.fixVersionLabel.text = @"Fix Version";
    self.fixVersionLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.fixVersionLabel.textColor = [UIColor labelColor];
    self.fixVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.fixVersionLabel];

    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];

    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.tintColor = [UIColor systemBlueColor];
    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [infoButton addTarget:self action:@selector(showFixVersionInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:infoButton];

    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];

    UIView *wrenchBgView = [[UIView alloc] init];
    wrenchBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    wrenchBgView.layer.cornerRadius = 12;
    wrenchBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:wrenchBgView];

    UIImageView *wrenchIconView = [[UIImageView alloc] init];
    wrenchIconView.image = [UIImage systemImageNamed:@"wrench.and.screwdriver"];
    wrenchIconView.tintColor = [UIColor systemBlueColor];
    wrenchIconView.contentMode = UIViewContentModeScaleAspectFit;
    wrenchIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [wrenchBgView addSubview:wrenchIconView];

    self.fixVersionAppsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = @"Apps";
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] forKey:NSFontAttributeName];
            return newAttributes;
        };
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 12, 4, 12);
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseForegroundColor = [UIColor whiteColor];
        [self.fixVersionAppsButton safeSetConfiguration:config];
    } else {
        [self.fixVersionAppsButton setTitle:@"Apps" forState:UIControlStateNormal];
        self.fixVersionAppsButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.fixVersionAppsButton.backgroundColor = [UIColor systemBlueColor];
        self.fixVersionAppsButton.layer.cornerRadius = 15;
        self.fixVersionAppsButton.tintColor = [UIColor whiteColor];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.fixVersionAppsButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        #pragma clang diagnostic pop
    }
    self.fixVersionAppsButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.fixVersionAppsButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.fixVersionAppsButton.layer.shadowOpacity = 0.2;
    self.fixVersionAppsButton.layer.shadowRadius = 2;
    self.fixVersionAppsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fixVersionAppsButton addTarget:self action:@selector(fixVersionAppsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [bottomRowContainer addSubview:self.fixVersionAppsButton];

    self.fixVersionToggleSwitch = [[UISwitch alloc] init];
    self.fixVersionToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.fixVersionToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL enabled = [self.securitySettings boolForKey:@"fixVersionEnabled"];
    [self.fixVersionToggleSwitch setOn:enabled animated:NO];
    [self.fixVersionToggleSwitch addTarget:self action:@selector(fixVersionToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.fixVersionToggleSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1140],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:100],

        [self.fixVersionLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.fixVersionLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],

        [infoBgView.leadingAnchor constraintEqualToAnchor:self.fixVersionLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.fixVersionLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],

        [infoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [infoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],

        [bottomRowContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:self.fixVersionLabel.bottomAnchor constant:15],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],

        [wrenchBgView.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [wrenchBgView.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [wrenchBgView.widthAnchor constraintEqualToConstant:24],
        [wrenchBgView.heightAnchor constraintEqualToConstant:24],

        [wrenchIconView.centerXAnchor constraintEqualToAnchor:wrenchBgView.centerXAnchor],
        [wrenchIconView.centerYAnchor constraintEqualToAnchor:wrenchBgView.centerYAnchor],
        [wrenchIconView.widthAnchor constraintEqualToConstant:16],
        [wrenchIconView.heightAnchor constraintEqualToConstant:16],

        [self.fixVersionAppsButton.leadingAnchor constraintEqualToAnchor:wrenchBgView.trailingAnchor constant:10],
        [self.fixVersionAppsButton.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.fixVersionAppsButton.widthAnchor constraintEqualToConstant:120],
        [self.fixVersionAppsButton.heightAnchor constraintEqualToConstant:30],

        [self.fixVersionToggleSwitch.leadingAnchor constraintEqualToAnchor:self.fixVersionAppsButton.trailingAnchor constant:10],
        [self.fixVersionToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.fixVersionToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor]
    ]];

    [self refreshFixVersionAppsButtonTitle];
}

- (void)setupDeepCleanControl:(UIView *)contentView {
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];

    self.deepCleanLabel = [[UILabel alloc] init];
    self.deepCleanLabel.text = @"Deep Clean";
    self.deepCleanLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.deepCleanLabel.textColor = [UIColor labelColor];
    self.deepCleanLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.deepCleanLabel];

    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];

    self.deepCleanInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.deepCleanInfoButton.tintColor = [UIColor systemBlueColor];
    self.deepCleanInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deepCleanInfoButton addTarget:self action:@selector(showDeepCleanInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.deepCleanInfoButton];

    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];

    UIView *sparkBgView = [[UIView alloc] init];
    sparkBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    sparkBgView.layer.cornerRadius = 12;
    sparkBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:sparkBgView];

    UIImageView *sparkIconView = [[UIImageView alloc] init];
    if (@available(iOS 13.0, *)) {
        sparkIconView.image = [UIImage systemImageNamed:@"sparkles"];
    }
    sparkIconView.tintColor = [UIColor systemBlueColor];
    sparkIconView.contentMode = UIViewContentModeScaleAspectFit;
    sparkIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [sparkBgView addSubview:sparkIconView];

    UILabel *modeLabel = [[UILabel alloc] init];
    modeLabel.text = @"Deep verify scan";
    modeLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    modeLabel.textColor = [UIColor labelColor];
    modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:modeLabel];

    self.deepCleanToggleSwitch = [[UISwitch alloc] init];
    self.deepCleanToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.deepCleanToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL enabled = [self.securitySettings boolForKey:@"deepCleanEnabled"];
    [self.deepCleanToggleSwitch setOn:enabled animated:NO];
    [self.deepCleanToggleSwitch addTarget:self action:@selector(deepCleanToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.deepCleanToggleSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:900],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:100],

        [self.deepCleanLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.deepCleanLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],

        [infoBgView.leadingAnchor constraintEqualToAnchor:self.deepCleanLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.deepCleanLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],

        [self.deepCleanInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.deepCleanInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],

        [bottomRowContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:self.deepCleanLabel.bottomAnchor constant:15],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],

        [sparkBgView.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [sparkBgView.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [sparkBgView.widthAnchor constraintEqualToConstant:24],
        [sparkBgView.heightAnchor constraintEqualToConstant:24],

        [sparkIconView.centerXAnchor constraintEqualToAnchor:sparkBgView.centerXAnchor],
        [sparkIconView.centerYAnchor constraintEqualToAnchor:sparkBgView.centerYAnchor],
        [sparkIconView.widthAnchor constraintEqualToConstant:16],
        [sparkIconView.heightAnchor constraintEqualToConstant:16],

        [modeLabel.leadingAnchor constraintEqualToAnchor:sparkBgView.trailingAnchor constant:10],
        [modeLabel.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],

        [self.deepCleanToggleSwitch.leadingAnchor constraintEqualToAnchor:modeLabel.trailingAnchor constant:10],
        [self.deepCleanToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.deepCleanToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor]
    ]];
}

- (void)setupSystemKeychainWipeControl:(UIView *)contentView {
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];

    self.systemKeychainWipeLabel = [[UILabel alloc] init];
    self.systemKeychainWipeLabel.text = @"System Keychain Wipe";
    self.systemKeychainWipeLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.systemKeychainWipeLabel.textColor = [UIColor labelColor];
    self.systemKeychainWipeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.systemKeychainWipeLabel];

    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];

    self.systemKeychainWipeInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    self.systemKeychainWipeInfoButton.tintColor = [UIColor systemRedColor];
    self.systemKeychainWipeInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.systemKeychainWipeInfoButton addTarget:self action:@selector(showSystemKeychainWipeInfo) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.systemKeychainWipeInfoButton];

    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];

    UILabel *modeLabel = [[UILabel alloc] init];
    modeLabel.text = @"Allow com.apple.*";
    modeLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    modeLabel.textColor = [UIColor labelColor];
    modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomRowContainer addSubview:modeLabel];

    self.systemKeychainWipeToggleSwitch = [[UISwitch alloc] init];
    self.systemKeychainWipeToggleSwitch.onTintColor = [UIColor systemRedColor];
    self.systemKeychainWipeToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL enabled = [self.securitySettings boolForKey:@"allowSystemKeychainWipeEnabled"];
    [self.systemKeychainWipeToggleSwitch setOn:enabled animated:NO];
    [self.systemKeychainWipeToggleSwitch addTarget:self action:@selector(systemKeychainWipeToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.systemKeychainWipeToggleSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1020],
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:100],

        [self.systemKeychainWipeLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.systemKeychainWipeLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],

        [infoBgView.leadingAnchor constraintEqualToAnchor:self.systemKeychainWipeLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.systemKeychainWipeLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],

        [self.systemKeychainWipeInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.systemKeychainWipeInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],

        [bottomRowContainer.centerXAnchor constraintEqualToAnchor:controlView.contentView.centerXAnchor],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:self.systemKeychainWipeLabel.bottomAnchor constant:15],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],

        [modeLabel.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [modeLabel.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],

        [self.systemKeychainWipeToggleSwitch.leadingAnchor constraintEqualToAnchor:modeLabel.trailingAnchor constant:10],
        [self.systemKeychainWipeToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        [self.systemKeychainWipeToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor]
    ]];
}

- (void)showSystemKeychainWipeInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"System Keychain Wipe"
                                                                   message:@"Dangerous. Enables Keychain Wipe for com.apple.* apps in Clear Data.\n\nThis may remove system accounts, credentials, Apple ID tokens, and can break system services. Use only if you know what you're doing."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)systemKeychainWipeToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"allowSystemKeychainWipeEnabled"];
    [self.securitySettings synchronize];

    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)showDeepCleanInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Deep Clean"
                                                                   message:@"Global Clear Data mode.\n\nON: Deep verify scan (slow) - scans inside containers for token/encrypted leftovers after wipe.\n\nOFF: Fast mode - assumes wiped containers are clean."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deepCleanToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"deepCleanEnabled"];
    [self.securitySettings synchronize];

    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)showFixVersionInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fix Version"
                                                                   message:@"Runtime-capped OS version for selected apps.\n\nIf an app crashes when kern.osproductversion is spoofed, enable Fix Version and add that app to the list."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fixVersionToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    [self.securitySettings setBool:enabled forKey:@"fixVersionEnabled"];
    [self.securitySettings synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.fixVersionChanged"
                                                        object:nil
                                                      userInfo:@{ @"enabled": @(enabled) }];

    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)fixVersionAppsTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];

    FixVersionAppsViewController *vc = [[FixVersionAppsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)refreshFixVersionAppsButtonTitle {
    NSArray *apps = [self.securitySettings objectForKey:@"fixVersionApps"];
    NSUInteger count = [apps isKindOfClass:[NSArray class]] ? [(NSArray *)apps count] : 0;
    NSString *title = (count > 0) ? [NSString stringWithFormat:@"Apps (%lu)", (unsigned long)count] : @"Apps";
    if ([UIButton buttonConfigurationClassExists]) {
        if (self.fixVersionAppsButton.configuration) {
            UIButtonConfiguration *config = [self.fixVersionAppsButton.configuration copy];
            config.title = title;
            [self.fixVersionAppsButton setConfiguration:config];
            return;
        }
    }
    [self.fixVersionAppsButton setTitle:title forState:UIControlStateNormal];
}

- (void)showAppVersionSpoofingInfo {
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"APP Specific Version Spoofing"
                               message:@"Allows you to spoof app version information to bypass version checks and maintain compatibility with services that require specific app versions."
                               preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction 
                              actionWithTitle:@"OK" 
                              style:UIAlertActionStyleDefault 
                              handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)appVersionSpoofingToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // Save setting immediately and synchronize
    [self.securitySettings setBool:enabled forKey:@"appVersionSpoofingEnabled"];
    [self.securitySettings synchronize];
    
    // Enable/disable access button based on toggle state
    self.appVersionSpoofingAccessButton.enabled = enabled;
    
    // Animate alpha and background color change
    [UIView animateWithDuration:0.2 animations:^{
        if ([UIButton buttonConfigurationClassExists]) {
            UIButtonConfiguration *config = [self.appVersionSpoofingAccessButton.configuration copy];
            if (enabled) {
                config.background.backgroundColor = [UIColor systemBlueColor];
                self.appVersionSpoofingAccessButton.alpha = 1.0;
            } else {
                config.background.backgroundColor = [UIColor systemGrayColor];
                self.appVersionSpoofingAccessButton.alpha = 0.6;
            }
            [self.appVersionSpoofingAccessButton setConfiguration:config];
        } else {
            if (enabled) {
                self.appVersionSpoofingAccessButton.alpha = 1.0;
                self.appVersionSpoofingAccessButton.backgroundColor = [UIColor systemBlueColor];
            } else {
                self.appVersionSpoofingAccessButton.alpha = 0.6;
                self.appVersionSpoofingAccessButton.backgroundColor = [UIColor systemGrayColor];
            }
        }
    }];
    
    // Send notification about the setting change
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(enabled) forKey:@"enabled"];
    [userInfo setObject:@"SecurityTabView" forKey:@"sender"];
    
    // Post notification on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.toggleAppVersionSpoofing" 
                                                            object:nil 
                                                          userInfo:userInfo];
    });
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)appVersionSpoofingAccessTapped:(UIButton *)sender {
    // Don't allow access if toggle is off
    if (!self.appVersionSpoofingToggleSwitch.isOn) {
        return;
    }
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    // Refresh version/build info for all scoped apps before presenting
    [[IdentifierManager sharedManager] refreshScopedAppsInfoIfNeeded];
    
    // Pass toast message to AppVersionSpoofingViewController and present it
    AppVersionSpoofingViewController *appVersionVC = [[AppVersionSpoofingViewController alloc] init];
    appVersionVC.toastMessageToShow = @"Scoped Apps Info Updated\nAPPS real Version / Build";
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:appVersionVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navController animated:YES completion:nil];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.timeUpdateTimer invalidate];
    self.timeUpdateTimer = nil;
}

- (void)getTimeZoneForLocation:(CLLocationCoordinate2D)coordinate completion:(void (^)(NSTimeZone *timeZone, NSString *timeZoneId))completion {
    CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (error || placemarks.count == 0) {
            completion(nil, nil);
            return;
        }
        
        CLPlacemark *placemark = placemarks.firstObject;
        NSTimeZone *timeZone = placemark.timeZone;
        NSString *timeZoneId = timeZone.name;
        completion(timeZone, timeZoneId);
    }];
}

- (void)updateTimeForTimeZone:(id)timeZoneOrTimer {
    NSTimeZone *timeZone = nil;
    
    // Handle both direct timeZone calls and timer calls
    if ([timeZoneOrTimer isKindOfClass:[NSTimeZone class]]) {
        timeZone = timeZoneOrTimer;
    } else if ([timeZoneOrTimer isKindOfClass:[NSTimer class]]) {
        // For legacy timer calls - this shouldn't happen anymore but kept for safety
        timeZone = [(NSTimer *)timeZoneOrTimer userInfo];
    }
    
    if (!timeZone) return;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.timeZone = timeZone;
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]; // Ensure AM/PM format
    formatter.dateFormat = @"h:mm a"; // 12-hour format with AM/PM
    
    NSString *currentTime = [formatter stringFromDate:[NSDate date]];
    self.timeLabel.text = currentTime;
}

- (void)showTimeZoneOptions {
    if (!self.currentTimeZoneId) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Time Zone Info"
                                                                 message:[NSString stringWithFormat:@"Time Zone ID: %@", self.currentTimeZoneId]
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add action to open iOS Time Settings
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Time Settings"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * _Nonnull action) {
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if ([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
            [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    // For iPad
    alert.popoverPresentationController.sourceView = self.timeLabel;
    alert.popoverPresentationController.sourceRect = self.timeLabel.bounds;
    
    [self presentViewController:alert animated:YES completion:nil];
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
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:1940], // Position between App Version Spoofing and Canvas Fingerprinting
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
}

- (void)setupCanvasFingerprintingControl:(UIView *)contentView {
    // Create a glassmorphic control with EXACT same style as other cells (like VPN/PROXY Detection Bypass)
    UIVisualEffectView *controlView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    controlView.layer.cornerRadius = 20;
    controlView.clipsToBounds = YES;
    controlView.alpha = 0.8;
    controlView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controlView];
    
    // Set background color to match other controls
    if (@available(iOS 13.0, *)) {
        controlView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        controlView.backgroundColor = [UIColor whiteColor];
    }
    
    // Canvas fingerprinting label
    self.canvasFingerprintingLabel = [[UILabel alloc] init];
    self.canvasFingerprintingLabel.text = @"Canvas Fingerprint Protection";
    self.canvasFingerprintingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.canvasFingerprintingLabel.textColor = [UIColor labelColor];
    self.canvasFingerprintingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:self.canvasFingerprintingLabel];
    
    // Info button with circular background (styled EXACTLY like other info buttons)
    UIView *infoBgView = [[UIView alloc] init];
    infoBgView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    infoBgView.layer.cornerRadius = 12;
    infoBgView.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:infoBgView];
    
    self.canvasFingerprintingInfoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    if (@available(iOS 13.0, *)) {
        UIImage *infoImage = [UIImage systemImageNamed:@"info.circle"];
        [self.canvasFingerprintingInfoButton setImage:infoImage forState:UIControlStateNormal];
    }
    self.canvasFingerprintingInfoButton.tintColor = [UIColor systemBlueColor];
    self.canvasFingerprintingInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.canvasFingerprintingInfoButton addTarget:self action:@selector(canvasFingerprintingInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [infoBgView addSubview:self.canvasFingerprintingInfoButton];
    
    // Container view for bottom row elements
    UIView *bottomRowContainer = [[UIView alloc] init];
    bottomRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:bottomRowContainer];
    
    // Initialize toggle state FIRST - before setting up the reset button
    // Get initial toggle state from multiple sources to ensure proper state restoration
    
    // 1. First check NSUserDefaults directly (most reliable for persistence)
    BOOL toggleEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"canvasFingerprintingEnabled"];
    // If not found, check alternate key name
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"canvasFingerprintingEnabled"]) {
        toggleEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"CanvasFingerprint"];
    }
    
    // 2. Then check security settings
    if (![self.securitySettings objectForKey:@"canvasFingerprintingEnabled"] && 
        ![self.securitySettings objectForKey:@"CanvasFingerprint"]) {
        // If not in standard defaults, check security settings
        toggleEnabled = [self.securitySettings boolForKey:@"canvasFingerprintingEnabled"] || 
                       [self.securitySettings boolForKey:@"CanvasFingerprint"];
    }
    
    // 3. Then check plist file directly
    if (!toggleEnabled) {
        NSString *securitySettingsPath = @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
        NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:securitySettingsPath];
        if (settingsDict) {
            toggleEnabled = [settingsDict[@"canvasFingerprintingEnabled"] boolValue] || 
                           [settingsDict[@"CanvasFingerprint"] boolValue];
        }
    }
    
    // 4. Finally, check IdentifierManager (authoritative source)
    Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
    if (identifierManagerClass) {
        id manager = [identifierManagerClass sharedManager];
        if ([manager respondsToSelector:@selector(isCanvasFingerprintProtectionEnabled)]) {
            toggleEnabled = [manager isCanvasFingerprintProtectionEnabled];
            // Log the state we're getting from IdentifierManager
            PXLog(@"[SecurityTab] 🎨 Canvas Fingerprinting: Loading state %@ from IdentifierManager", 
                  toggleEnabled ? @"ENABLED" : @"DISABLED");
        }
    }

    // Reset button with icon (styled like other buttons in the app)
    self.canvasFingerprintingResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = @"Reset Noise";
        config.image = [UIImage systemImageNamed:@"arrow.clockwise"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium] forKey:NSFontAttributeName];
            return newAttributes;
        };
        [self.canvasFingerprintingResetButton setConfiguration:config];
    } else {
        // For older iOS versions
        if (@available(iOS 13.0, *)) {
            UIImage *resetImage = [UIImage systemImageNamed:@"arrow.clockwise"];
            [self.canvasFingerprintingResetButton setImage:resetImage forState:UIControlStateNormal];
            [self.canvasFingerprintingResetButton setTitle:@" Reset Noise" forState:UIControlStateNormal];
        } else {
            [self.canvasFingerprintingResetButton setTitle:@"↻ Reset Noise" forState:UIControlStateNormal];
        }
        self.canvasFingerprintingResetButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    }
    self.canvasFingerprintingResetButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvasFingerprintingResetButton.tintColor = [UIColor systemBlueColor];
    
    // Set initial state based on toggle position - now toggleEnabled is defined
    self.canvasFingerprintingResetButton.enabled = toggleEnabled;
    self.canvasFingerprintingResetButton.alpha = toggleEnabled ? 1.0 : 0.5;
    
    [self.canvasFingerprintingResetButton addTarget:self action:@selector(canvasFingerprintingResetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [bottomRowContainer addSubview:self.canvasFingerprintingResetButton];
    
    // Toggle switch
    self.canvasFingerprintingToggleSwitch = [[UISwitch alloc] init];
    self.canvasFingerprintingToggleSwitch.onTintColor = [UIColor systemBlueColor];
    self.canvasFingerprintingToggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Set the toggle switch state
    [self.canvasFingerprintingToggleSwitch setOn:toggleEnabled animated:NO];
    [self.canvasFingerprintingToggleSwitch addTarget:self action:@selector(canvasFingerprintingToggleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [bottomRowContainer addSubview:self.canvasFingerprintingToggleSwitch];
    
    // Description label (matching style of other controls)
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"Prevents browser fingerprinting through canvas operations";
    descriptionLabel.font = [UIFont systemFontOfSize:12];
    if (@available(iOS 13.0, *)) {
        descriptionLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        descriptionLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    }
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlView.contentView addSubview:descriptionLabel];
    
    // Position control between Domain Blocking and Copyright label
    [NSLayoutConstraint activateConstraints:@[
        [controlView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:2080], // Moved down to be below Domain Blocking
        [controlView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [controlView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [controlView.heightAnchor constraintEqualToConstant:120],
        
        // Position label at the top
        [self.canvasFingerprintingLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [self.canvasFingerprintingLabel.topAnchor constraintEqualToAnchor:controlView.contentView.topAnchor constant:15],
        
        // Position info button to the right of the label
        [infoBgView.leadingAnchor constraintEqualToAnchor:self.canvasFingerprintingLabel.trailingAnchor constant:10],
        [infoBgView.centerYAnchor constraintEqualToAnchor:self.canvasFingerprintingLabel.centerYAnchor],
        [infoBgView.widthAnchor constraintEqualToConstant:24],
        [infoBgView.heightAnchor constraintEqualToConstant:24],
        
        [self.canvasFingerprintingInfoButton.centerXAnchor constraintEqualToAnchor:infoBgView.centerXAnchor],
        [self.canvasFingerprintingInfoButton.centerYAnchor constraintEqualToAnchor:infoBgView.centerYAnchor],
        
        // Description label below the title
        [descriptionLabel.topAnchor constraintEqualToAnchor:self.canvasFingerprintingLabel.bottomAnchor constant:8],
        [descriptionLabel.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [descriptionLabel.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        
        // Position bottom row container
        [bottomRowContainer.leadingAnchor constraintEqualToAnchor:controlView.contentView.leadingAnchor constant:20],
        [bottomRowContainer.trailingAnchor constraintEqualToAnchor:controlView.contentView.trailingAnchor constant:-20],
        [bottomRowContainer.topAnchor constraintEqualToAnchor:descriptionLabel.bottomAnchor constant:15],
        [bottomRowContainer.heightAnchor constraintEqualToConstant:30],
        
        // Position reset button in bottom row container
        [self.canvasFingerprintingResetButton.leadingAnchor constraintEqualToAnchor:bottomRowContainer.leadingAnchor],
        [self.canvasFingerprintingResetButton.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor],
        
        // Position toggle switch at the right side of bottom row
        [self.canvasFingerprintingToggleSwitch.trailingAnchor constraintEqualToAnchor:bottomRowContainer.trailingAnchor],
        [self.canvasFingerprintingToggleSwitch.centerYAnchor constraintEqualToAnchor:bottomRowContainer.centerYAnchor]
    ]];
}

- (void)canvasFingerprintingToggleSwitchChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    // ONLY update the plist file - THE SINGLE SOURCE OF TRUTH
    NSString *securitySettingsPath = @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";
    NSMutableDictionary *settingsDict = [NSMutableDictionary dictionaryWithContentsOfFile:securitySettingsPath] ?: [NSMutableDictionary dictionary];
    settingsDict[@"canvasFingerprintingEnabled"] = @(enabled);
    settingsDict[@"CanvasFingerprint"] = @(enabled); // Also use old key for compatibility
    
    // Ensure the plist is written atomically and with proper permissions
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:settingsDict
                                                                  format:NSPropertyListXMLFormat_v1_0
                                                                 options:0
                                                                   error:nil];
    if (plistData) {
        [plistData writeToFile:securitySettingsPath atomically:YES];
        PXLog(@"[SecurityTab] 🎨 Canvas Fingerprinting: Updated plist at %@", securitySettingsPath);
    }
    
    // 5. Call the IdentifierManager method to handle the toggle
    Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
    if (identifierManagerClass) {
        id manager = [identifierManagerClass sharedManager];
        if ([manager respondsToSelector:@selector(setCanvasFingerprintProtection:)]) {
            [manager setCanvasFingerprintProtection:enabled];
            PXLog(@"[SecurityTab] 🎨 Canvas Fingerprinting: Updated via IdentifierManager");
        }
    }
    
    // 6. Update UI
    // Enable/disable reset button based on toggle state
    self.canvasFingerprintingResetButton.enabled = enabled;
    if (enabled) {
        self.canvasFingerprintingResetButton.alpha = 1.0;
    } else {
        self.canvasFingerprintingResetButton.alpha = 0.5;
    }
    
    // 7. Send notifications with enhanced information
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(enabled) forKey:@"enabled"];
    [userInfo setObject:@"SecurityTabView" forKey:@"sender"];
    [userInfo setObject:[NSDate date] forKey:@"timestamp"];
    [userInfo setObject:@YES forKey:@"forceReload"];
    [userInfo setObject:securitySettingsPath forKey:@"settingsPath"];
    
    // Post notification immediately on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        PXLog(@"[SecurityTab] 🎨 Broadcasting canvas fingerprint protection toggle change: %@", enabled ? @"ON" : @"OFF");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.toggleCanvasFingerprintProtection" 
                                                            object:nil 
                                                          userInfo:userInfo];
    });
    
    // Also send Darwin notifications for system-wide changes
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    
    // Enhanced notification system - send specific state notifications to ensure clarity
    if (enabled) {
        // Specific ON notification
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.enableCanvasFingerprintProtection"), NULL, NULL, YES);
        // Generic change notification
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.canvasFingerprintToggleChanged"), NULL, NULL, YES);
        // Original notification name for compatibility
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.toggleCanvasFingerprint"), NULL, NULL, YES);
    } else {
        // Specific OFF notification
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.disableCanvasFingerprintProtection"), NULL, NULL, YES);
        // Generic change notification
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.canvasFingerprintToggleChanged"), NULL, NULL, YES);
        // Original notification name for compatibility
        CFNotificationCenterPostNotification(darwinCenter, CFSTR("com.hydra.projectx.toggleCanvasFingerprint"), NULL, NULL, YES);
    }
    
    // Reset NSUserDefaults to ensure data is consistent across all processes
    NSString *resetCmd = enabled ? @"ON" : @"OFF";
    notify_post([@"com.hydra.projectx.resetCanvasFingerprint." stringByAppendingString:resetCmd].UTF8String);
    
    // Show simple toast instead of alert (consistent with other controls)
    NSString *message = enabled ? 
        @"Canvas Fingerprinting Protection Enabled" : 
        @"Canvas Fingerprinting Protection Disabled";
    [self showToastWithMessage:message];
    
    // Add haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    PXLog(@"[SecurityTab] 🎨 Canvas Fingerprinting %@: Persistent settings updated across all domains", 
           enabled ? @"ENABLED" : @"DISABLED");
}

- (void)canvasFingerprintingInfoButtonTapped:(UIButton *)sender {
    // Show an information dialog about canvas fingerprinting
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Canvas Fingerprinting Protection" 
                        message:@"Canvas fingerprinting is a tracking technique that allows websites to identify your device by generating unique images. This protection adds subtle noise to canvas operations to prevent tracking while maintaining normal website functionality." 
                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)canvasFingerprintingResetButtonTapped:(UIButton *)sender {
    // Add visual feedback - briefly highlight the button
    UIColor *originalColor = sender.backgroundColor;
    UIColor *originalTintColor = sender.tintColor;
    [UIView animateWithDuration:0.1 animations:^{
        sender.backgroundColor = [UIColor systemBlueColor];
        sender.tintColor = [UIColor whiteColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = originalColor;
            sender.tintColor = originalTintColor;
        }];
    }];
    
    // Reset the noise patterns using IdentifierManager
    Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
    if (identifierManagerClass) {
        id manager = [identifierManagerClass sharedManager];
        if ([manager respondsToSelector:@selector(resetCanvasNoise)]) {
            [manager resetCanvasNoise];
            
            // Show toast notification instead of alert for consistency
            [self showToastWithMessage:@"Canvas Fingerprint Noise Patterns Reset"];
            
            // Add haptic feedback
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
        }
    }
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
