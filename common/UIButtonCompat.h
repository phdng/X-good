//
//  UIButtonCompat.h
//  ProjectX
//
//  Created for iOS 12+ compatibility.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * UIButton helper for iOS 12+ compatibility.
 * Provides a unified API that uses UIButtonConfiguration on iOS 15+
 * and falls back to classic styling on iOS 12-14.
 */
@interface UIButtonCompat : NSObject

/**
 * Creates a button with filled style (solid background).
 * iOS 15+: Uses UIButtonConfiguration.filledButtonConfiguration
 * iOS 12-14: Uses classic UIButton with background color
 */
+ (UIButton *)filledButtonWithTitle:(NSString *)title
                        tintColor:(nullable UIColor *)tintColor
                  backgroundColor:(nullable UIColor *)backgroundColor;

/**
 * Creates a button with plain style (no background).
 * iOS 15+: Uses UIButtonConfiguration.plainButtonConfiguration
 * iOS 12-14: Uses classic UIButton
 */
+ (UIButton *)plainButtonWithTitle:(NSString *)title
                       tintColor:(nullable UIColor *)tintColor
                           image:(nullable UIImage *)image;

/**
 * Creates a button with image and title.
 * iOS 15+: Uses UIButtonConfiguration with imagePlacement
 * iOS 12-14: Uses classic UIButton
 */
+ (UIButton *)buttonWithTitle:(NSString *)title
                        image:(nullable UIImage *)image
               imagePlacement:(NSDirectionalRectEdge)placement
                    tintColor:(nullable UIColor *)tintColor
              backgroundColor:(nullable UIColor *)backgroundColor;

@end

NS_ASSUME_NONNULL_END
