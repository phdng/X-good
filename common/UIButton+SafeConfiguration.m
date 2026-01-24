//
//  UIButton+SafeConfiguration.m
//  ProjectX
//
//  Created for iOS 12+ compatibility with UIButtonConfiguration.
//  IMPORTANT: DO NOT use @available checks - Theos compiler bypasses them!
//  Only use runtime respondsToSelector: checks for safety.
//

#import "UIButton+SafeConfiguration.h"

@implementation UIButton (SafeConfiguration)

- (BOOL)supportsConfiguration {
    // Pure runtime check - DO NOT use @available, it's bypassed by Theos!
    return [self respondsToSelector:@selector(setConfiguration:)];
}

- (void)safeSetConfiguration:(id)config {
    // CRITICAL: Only use runtime respondsToSelector check
    // @available is NOT reliable in Theos builds!
    if (config != nil && [self respondsToSelector:@selector(setConfiguration:)]) {
        // Use performSelector to call setConfiguration: safely
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:@selector(setConfiguration:) withObject:config];
        #pragma clang diagnostic pop
    }
    // On iOS < 15, this is a no-op - caller handles fallback styling
}

@end
