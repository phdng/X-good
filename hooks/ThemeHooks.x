#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import "ProfileManager.h"
#import "IdentifierManager.h"
// Cache for bundle decisions and theme values
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSString *cachedThemeValue = nil;
static NSDate *cacheTimestamp = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds

// Define the possible theme values
typedef NS_ENUM(NSInteger, WeaponXThemeStyle) {
    WeaponXThemeStyleUnspecified,
    WeaponXThemeStyleLight,
    WeaponXThemeStyleDark
};



// Helper function to get theme value from profile
static WeaponXThemeStyle getThemeStyleFromProfile(void) {
    // Skip cache if it's more than 5 minutes old
    BOOL shouldRefresh = NO;
    if (!cacheTimestamp || [[NSDate date] timeIntervalSinceDate:cacheTimestamp] > kCacheValidityDuration) {
        shouldRefresh = YES;
    }
    
    // Use cached value if available and not expired
    if (!shouldRefresh && cachedThemeValue) {
        if ([cachedThemeValue isEqualToString:@"Dark"]) {
            return WeaponXThemeStyleDark;
        } else if ([cachedThemeValue isEqualToString:@"Light"]) {
            return WeaponXThemeStyleLight;
        }
    }
    
    // Read theme value directly from profile files
    NSString *themeValue = nil;
    
    // Try to get the current profile directory

    NSString *profileBasePath = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:profileBasePath]) {
        // Get current profile ID

            // Try to read theme from device_ids.plist
        NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        themeValue = deviceIds[@"DeviceTheme"];

        // Try to read from device_theme.plist
        NSString *deviceThemePath = [identityDir stringByAppendingPathComponent:@"device_theme.plist"];
        NSDictionary *deviceTheme = [NSDictionary dictionaryWithContentsOfFile:deviceThemePath];
        themeValue = deviceTheme[@"value"];
    }
    
    // Fallback to default if nothing found
    if (!themeValue) {
        themeValue = @"Light"; // Default to light theme
    }
    
    // Update cache
    cachedThemeValue = themeValue;
    cacheTimestamp = [NSDate date];
    
    // Return the appropriate theme style
    if ([themeValue isEqualToString:@"Dark"]) {
        return WeaponXThemeStyleDark;
    } else if ([themeValue isEqualToString:@"Light"]) {
        return WeaponXThemeStyleLight;
    }
    
    return WeaponXThemeStyleUnspecified;
}

// UIUserInterfaceStyle mapping function
static UIUserInterfaceStyle mapThemeStyleToUIUserInterfaceStyle(WeaponXThemeStyle themeStyle) {
    switch (themeStyle) {
        case WeaponXThemeStyleDark:
            return UIUserInterfaceStyleDark;
        case WeaponXThemeStyleLight:
            return UIUserInterfaceStyleLight;
        case WeaponXThemeStyleUnspecified:
        default:
            return UIUserInterfaceStyleUnspecified;
    }
}

// Hook definitions
%group ThemeHooks

// Hook UITraitCollection to intercept userInterfaceStyle
%hook UITraitCollection

// Method for getting userInterfaceStyle property
- (UIUserInterfaceStyle)userInterfaceStyle {
    WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
    
    if (themeStyle != WeaponXThemeStyleUnspecified) {
        UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
        
        // Log the first time we spoof for an app (to reduce spam)
        static NSMutableSet *loggedApps = nil;
        if (!loggedApps) {
            loggedApps = [NSMutableSet set];
        }
        
        
        return spoofedStyle;
    }

    // Return original value if not spoofing
    return %orig;
}

// For iOS 17, there's a new named retrieval method
- (UIUserInterfaceStyle)effectiveUserInterfaceStyle {
    if (@available(iOS 17.0, *)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            return mapThemeStyleToUIUserInterfaceStyle(themeStyle);
        }
    
    }
    
    // Return original value if not spoofing
    return %orig;
}

%end

// Hook UIScreen to intercept system-wide theme setting
%hook UIScreen

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    
    WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
    
    if (themeStyle != WeaponXThemeStyleUnspecified) {
        // Create a trait collection with our spoofed interface style
        UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
        
        UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
        
        // Merge with original trait collection to preserve other traits
        return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
    }

    
    return originalTraitCollection;
}

%end

// Hook UIView for apps that check theme at the view level
%hook UIView

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
    
    if (themeStyle != WeaponXThemeStyleUnspecified) {
        // Create a trait collection with our spoofed interface style
        UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
        
        UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
        
        // Merge with original trait collection to preserve other traits
        return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
    }
    
    
    return originalTraitCollection;
}

%end

// Hook UIViewController for apps that check theme at the controller level
%hook UIViewController

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
    
    if (themeStyle != WeaponXThemeStyleUnspecified) {
        // Create a trait collection with our spoofed interface style
        UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
        
        UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
        
        // Merge with original trait collection to preserve other traits
        return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
    }
    
    
    return originalTraitCollection;
}

%end

// Hook any WebKit bridges for web detection of dark mode
%hook WKWebView

// Hook preferredColorScheme for WebKit
- (void)_setPreferredColorScheme:(NSInteger)colorScheme {
    
    WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
    if (themeStyle != WeaponXThemeStyleUnspecified) {
        // Map our theme style to WebKit's color scheme values (0 = light, 1 = dark)
        NSInteger spoofedColorScheme = (themeStyle == WeaponXThemeStyleDark) ? 1 : 0;
        %orig(spoofedColorScheme);
        return;
    }
    
    %orig;
}

%end

%end // End of ThemeHooks group


// Constructor to initialize hooks
%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[ThemeHooks] Initializing theme hooks");
            
            // CRITICAL: Only install hooks if this app is actually scoped
            if (!IsScope()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                PXLog(@"[ThemeHooks] App is not scoped, skipping hook installation");
                return;
            }
            
            // Initialize hooks for scoped apps only
            %init(ThemeHooks);
            
            PXLog(@"[ThemeHooks] Theme hooks successfully initialized for scoped app");
            
        } @catch (NSException *e) {
            PXLog(@"[ThemeHooks] ❌ Exception in constructor: %@", e);
        }
    }
} 