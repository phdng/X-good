//
//  UIButtonCompat.m
//  ProjectX
//
//  Created for iOS 12+ compatibility.
//

#import "UIButtonCompat.h"
#import "UIButton+SafeConfiguration.h"

@implementation UIButtonCompat

+ (UIButton *)filledButtonWithTitle:(NSString *)title
                        tintColor:(nullable UIColor *)tintColor
                  backgroundColor:(nullable UIColor *)backgroundColor {
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.title = title;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        if (backgroundColor) {
            config.background.backgroundColor = backgroundColor;
        }
        if (tintColor) {
            config.baseForegroundColor = tintColor;
        }
        [button safeSetConfiguration:config];
    } else {
        [button setTitle:title forState:UIControlStateNormal];
        if (tintColor) {
            [button setTitleColor:tintColor forState:UIControlStateNormal];
        }
        if (backgroundColor) {
            button.backgroundColor = backgroundColor;
        } else {
            button.backgroundColor = [UIColor systemBlueColor];
        }
        button.layer.cornerRadius = 8;
        button.clipsToBounds = YES;
        
        // Add some padding
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        button.contentEdgeInsets = UIEdgeInsetsMake(8, 16, 8, 16);
        #pragma clang diagnostic pop
    }
    
    return button;
}

+ (UIButton *)plainButtonWithTitle:(NSString *)title
                       tintColor:(nullable UIColor *)tintColor
                           image:(nullable UIImage *)image {
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = title;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        if (tintColor) {
            config.baseForegroundColor = tintColor;
        }
        if (image) {
            config.image = image;
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            config.imagePadding = 4;
        }
        [button safeSetConfiguration:config];
    } else {
        [button setTitle:title forState:UIControlStateNormal];
        if (tintColor) {
            [button setTitleColor:tintColor forState:UIControlStateNormal];
            button.tintColor = tintColor;
        }
        if (image) {
            [button setImage:image forState:UIControlStateNormal];
            
            // Add spacing between image and title
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            button.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
            button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
            #pragma clang diagnostic pop
        }
    }
    
    return button;
}

+ (UIButton *)buttonWithTitle:(NSString *)title
                        image:(nullable UIImage *)image
               imagePlacement:(NSDirectionalRectEdge)placement
                    tintColor:(nullable UIColor *)tintColor
              backgroundColor:(nullable UIColor *)backgroundColor {
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if ([UIButton buttonConfigurationClassExists]) {
        UIButtonConfiguration *config;
        if (backgroundColor) {
            config = [UIButtonConfiguration filledButtonConfiguration];
            config.background.backgroundColor = backgroundColor;
        } else {
            config = [UIButtonConfiguration plainButtonConfiguration];
        }
        
        config.title = title;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        
        if (tintColor) {
            config.baseForegroundColor = tintColor;
        }
        
        if (image) {
            config.image = image;
            config.imagePlacement = placement;
            config.imagePadding = 4;
        }
        
        [button safeSetConfiguration:config];
    } else {
        [button setTitle:title forState:UIControlStateNormal];
        
        if (tintColor) {
            [button setTitleColor:tintColor forState:UIControlStateNormal];
            button.tintColor = tintColor;
        }
        
        if (backgroundColor) {
            button.backgroundColor = backgroundColor;
            button.layer.cornerRadius = 8;
            button.clipsToBounds = YES;
        }
        
        if (image) {
            [button setImage:image forState:UIControlStateNormal];
            
            // Adjust image position based on placement
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if (placement == NSDirectionalRectEdgeTrailing) {
                // Image on right
                button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
            }
            button.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
            button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
            #pragma clang diagnostic pop
        }
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        button.contentEdgeInsets = UIEdgeInsetsMake(8, 16, 8, 16);
        #pragma clang diagnostic pop
    }
    
    return button;
}

@end
