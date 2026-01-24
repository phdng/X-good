//
//  UIButton+SafeConfiguration.h
//  ProjectX
//
//  Created for iOS 12+ compatibility with UIButtonConfiguration.
//  This category provides runtime-safe configuration methods.
//  IMPORTANT: DO NOT use @available - Theos bypasses it!
//

#import <UIKit/UIKit.h>

@interface UIButton (SafeConfiguration)

/**
 * Check if UIButtonConfiguration class exists at runtime (iOS 15+)
 * This is the ONLY reliable check - do NOT use @available!
 */
+ (BOOL)buttonConfigurationClassExists;

/**
 * Check if this button supports UIButtonConfiguration (iOS 15+)
 */
- (BOOL)supportsConfiguration;

/**
 * Safely applies a UIButtonConfiguration to this button.
 * On iOS 15+, applies the configuration normally.
 * On iOS < 15, this is a no-op (does nothing) to prevent crashes.
 *
 * IMPORTANT: Always call this method instead of directly setting .configuration
 * to ensure compatibility with iOS 12-14.
 */
- (void)safeSetConfiguration:(id)config;

@end
