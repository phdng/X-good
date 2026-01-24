//
//  UIButton+SafeConfiguration.m
//  ProjectX
//
//  Created for iOS 12+ compatibility with UIButtonConfiguration.
//  IMPORTANT: DO NOT use @available checks - Theos compiler bypasses them!
//  Only use runtime NSClassFromString and respondsToSelector checks for safety.
//

#import "UIButton+SafeConfiguration.h"

@implementation UIButton (SafeConfiguration)

+ (BOOL)buttonConfigurationClassExists {
    // Use NSClassFromString to check if UIButtonConfiguration class exists at runtime
    // This is the ONLY reliable check - @available is bypassed by Theos!
    static BOOL checked = NO;
    static BOOL exists = NO;
    if (!checked) {
        exists = (NSClassFromString(@"UIButtonConfiguration") != nil);
        checked = YES;
    }
    return exists;
}

- (BOOL)supportsConfiguration {
    // Check both class existence AND that this button responds to setConfiguration:
    return [UIButton buttonConfigurationClassExists] && 
           [self respondsToSelector:@selector(setConfiguration:)];
}

- (void)safeSetConfiguration:(id)config {
    // CRITICAL: Only proceed if UIButtonConfiguration class exists at runtime
    // This prevents crash when @available is bypassed by Theos
    if (config != nil && [self supportsConfiguration]) {
        // Use performSelector to call setConfiguration: safely
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:@selector(setConfiguration:) withObject:config];
        #pragma clang diagnostic pop
    }
    // On iOS < 15, this is a no-op - caller handles fallback styling
}

@end
