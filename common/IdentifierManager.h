#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ProjectX.h"

// Declare this in a category to avoid duplicate interface


@interface IdentifierManager (AppManagement)

#pragma mark - App Management

- (void)addApplicationToScope:(NSString *)bundleID;
- (void)removeApplicationFromScope:(NSString *)bundleID;
- (void)setApplication:(NSString *)bundleID enabled:(BOOL)enabled;
- (NSDictionary *)getApplicationInfo:(NSString *)bundleID;


- (BOOL)isBundleIDMatch:(NSString *)targetBundleID withPattern:(NSString *)patternBundleID;
- (BOOL)isScope;

#pragma mark - Custom Values
- (NSString *) getValueForType:(NSString *)type;
- (BOOL) setValueForType: (NSString *) value forType:(NSString *)type;

- (NSDictionary *)currentIOSVersionInfo;


// Canvas Fingerprinting Protection
- (BOOL)toggleCanvasFingerprintProtection;
- (BOOL)isCanvasFingerprintProtectionEnabled;
- (BOOL)setCanvasFingerprintProtection:(BOOL)enabled;
- (void)resetCanvasNoise;
// Device Model
- (BOOL)setCustomDeviceModel:(NSString *)value;
- (NSString *)generateDeviceModel;

// Device Theme
- (BOOL)setCustomDeviceTheme:(NSString *)value;
- (NSString *)generateDeviceTheme;
- (NSString *)toggleDeviceTheme;

// Device Model Specifications
- (NSDictionary *)getDeviceModelSpecifications;
- (NSString *)getScreenResolution;
- (NSString *)getViewportResolution;
- (CGFloat)getDevicePixelRatio;
- (NSInteger)getScreenDensity;
- (NSString *)getCPUArchitecture;
- (NSInteger)getDeviceMemory;
- (NSString *)getGPUFamily;
- (NSDictionary *)getWebGLInfo;
- (NSInteger)getCPUCoreCount;
- (NSString *)getMetalFeatureSet;

// IMEI/MEID
- (BOOL)setCustomIMEI:(NSString *)value;
- (BOOL)setCustomMEID:(NSString *)value;
- (NSString *)generateIMEI;
- (NSString *)generateMEID;

@end