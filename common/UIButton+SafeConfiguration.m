//
//  UIButton+SafeConfiguration.m
//  ProjectX
//
//  Created for iOS 12+ compatibility with UIButtonConfiguration.
//

#import "UIButton+SafeConfiguration.h"

@implementation UIButton (SafeConfiguration)

- (BOOL)supportsConfiguration {
    // Runtime check - verify iOS version AND that the button actually responds to the selector
    if (@available(iOS 15.0, *)) {
        return [self respondsToSelector:@selector(setConfiguration:)];
    }
    return NO;
}

- (void)safeSetConfiguration:(id)config {
    // Double-check: @available guard AND respondsToSelector
    // This prevents crashes even if @available is bypassed by compiler optimizations
    if (@available(iOS 15.0, *)) {
        if ([self respondsToSelector:@selector(setConfiguration:)] && config != nil) {
            // Use performSelector to avoid compile-time issues on older SDKs
            // and ensure runtime safety
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self performSelector:@selector(setConfiguration:) withObject:config];
            #pragma clang diagnostic pop
        }
    }
    // On iOS < 15, this is a no-op - caller should handle fallback styling
}

@end
