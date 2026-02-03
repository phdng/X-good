#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
// #import <ellekit/ellekit.h> // Removed for rootful - using Substrate

#import "PXScope.h"

// Cache for bundle decisions
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSDate *cacheTimestamp = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds

// Configuration for fingerprint noise
static CGFloat kNoiseIntensity = 0.02;  // Default noise intensity (2% variation)
static BOOL kConsistentNoise = YES;     // Whether to use consistent noise per session

// Cache for noise seed values (to keep consistent noise per app session)
static NSMutableDictionary *noiseSeedCache = nil;

#pragma mark - Helper Functions

// Helper: Always read enablement from profile/plist, not IdentifierManager
static BOOL isCanvasFingerprintProtectionEnabledForCurrentApp(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return NO;
    NSArray *possiblePaths = @[@"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
                               @"/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
                               @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist"];
    NSDictionary *settingsDict = nil;
    for (NSString *path in possiblePaths) {
        settingsDict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (settingsDict) break;
    }
    if (!settingsDict) return NO;
    NSNumber *enabled = settingsDict[@"canvasFingerprintingEnabled"];
    if (!enabled) enabled = settingsDict[@"CanvasFingerprint"];
    return enabled ? [enabled boolValue] : NO;
}

static NSDictionary *PXReadCurrentDeviceIdsForFingerprint(void) {
    @try {
        NSArray *possibleProfilesPaths = @[@"/var/mobile/Library/WeaponX/Profiles",
                                          @"/private/var/mobile/Library/WeaponX/Profiles",
                                          @"/var/mobile/Library/WeaponX/Profiles"];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *profilesPath in possibleProfilesPaths) {
            if (![fm fileExistsAtPath:profilesPath]) continue;
            NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
            NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
            NSString *profileId = centralInfo[@"ProfileId"];
            if (!profileId.length) continue;
            NSString *identityDir = [[profilesPath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            if ([deviceIds isKindOfClass:[NSDictionary class]] && deviceIds.count) {
                return deviceIds;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static uint32_t PXStableSeedForBundle(NSString *bundleID, NSDictionary *deviceIds) {
    // FNV-1a 32-bit
    uint32_t h = 2166136261u;
    NSString *model = [deviceIds[@"DeviceModel"] isKindOfClass:[NSString class]] ? deviceIds[@"DeviceModel"] : @"";
    NSString *build = [deviceIds[@"IOSBuild"] isKindOfClass:[NSString class]] ? deviceIds[@"IOSBuild"] : @"";
    NSString *s = [NSString stringWithFormat:@"%@|%@|%@", bundleID ?: @"", model, build];
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        h ^= bytes[i];
        h *= 16777619u;
    }
    if (h == 0) h = 1;
    return h;
}

static BOOL PXParseResolutionString(NSString *res, NSInteger *outW, NSInteger *outH) {
    if (!outW || !outH) return NO;
    *outW = 0; *outH = 0;
    if (![res isKindOfClass:[NSString class]] || res.length == 0) return NO;
    NSArray *parts = [res componentsSeparatedByString:@"x"];
    if (parts.count != 2) return NO;
    NSInteger w = [parts[0] integerValue];
    NSInteger h = [parts[1] integerValue];
    if (w <= 0 || h <= 0) return NO;
    *outW = w; *outH = h;
    return YES;
}

static NSString *PXBuildWebScreenSpoofScript(NSDictionary *deviceIds) {
    if (!PXDisplayWebScreenSpoofEnabled()) return nil;

    NSString *viewportRes = [deviceIds[@"ViewportResolution"] isKindOfClass:[NSString class]] ? deviceIds[@"ViewportResolution"] : nil;
    NSNumber *dprNum = [deviceIds[@"DevicePixelRatio"] isKindOfClass:[NSNumber class]] ? deviceIds[@"DevicePixelRatio"] : nil;
    CGFloat dpr = dprNum ? [dprNum floatValue] : 0.0;
    if (dpr <= 0.0) dpr = 1.0;

    NSInteger vwPx = 0, vhPx = 0;
    if (!PXParseResolutionString(viewportRes, &vwPx, &vhPx)) {
        return nil;
    }

    // Convert pixels -> CSS pixels/points.
    NSInteger wPt = (NSInteger)llround((double)vwPx / (double)dpr);
    NSInteger hPt = (NSInteger)llround((double)vhPx / (double)dpr);
    NSInteger sw = MIN(wPt, hPt);
    NSInteger sh = MAX(wPt, hPt);

    return [NSString stringWithFormat:
            @"(function(){try{\n"
             "if(window.__weaponx_screen_spoof__)return;\n"
             "window.__weaponx_screen_spoof__=true;\n"
             "const dpr=%.6g;const sw=%ld;const sh=%ld;\n"
             "function def(obj,prop,val){try{Object.defineProperty(obj,prop,{get:function(){return val;},configurable:true});}catch(e){}}\n"
             "def(window,'devicePixelRatio',dpr);\n"
             "try{if(window.screen){def(screen,'width',sw);def(screen,'height',sh);def(screen,'availWidth',sw);def(screen,'availHeight',sh);} }catch(e){}\n"
             "def(window,'innerWidth',sw);def(window,'innerHeight',sh);\n"
             "def(window,'outerWidth',sw);def(window,'outerHeight',sh);\n"
             "try{if(window.visualViewport){def(visualViewport,'width',sw);def(visualViewport,'height',sh);def(visualViewport,'scale',1);} }catch(e){}\n"
             "}catch(e){}})();",
            dpr, (long)sw, (long)sh];
}

static NSString *PXBuildSeededFingerprintProtectionScript(NSString *bundleID) {
    NSDictionary *deviceIds = PXReadCurrentDeviceIdsForFingerprint();
    if (!deviceIds) return nil;

    uint32_t seed = PXStableSeedForBundle(bundleID, deviceIds);

    NSString *unmaskedVendor = @"Apple Inc.";
    NSString *unmaskedRenderer = [deviceIds[@"GPUFamily"] isKindOfClass:[NSString class]] ? deviceIds[@"GPUFamily"] : nil;
    if (!unmaskedRenderer.length) {
        unmaskedRenderer = [deviceIds[@"WebGLRenderer"] isKindOfClass:[NSString class]] ? deviceIds[@"WebGLRenderer"] : @"Apple GPU";
    }

    // NOTE: This script is intended for test builds. It is deterministic per bundle/profile.
    return [NSString stringWithFormat:
            @"(function(){try{\n"
             "if(window.__weaponx_fp_spoof__)return;\n"
             "window.__weaponx_fp_spoof__=true;\n"
             "let __wxSeed=%u>>>0;\n"
             "function __wxRand(){__wxSeed^=(__wxSeed<<13);__wxSeed>>>=0;__wxSeed^=(__wxSeed>>>17);__wxSeed>>>=0;__wxSeed^=(__wxSeed<<5);__wxSeed>>>=0;return(__wxSeed>>>0)/4294967296;}\n"
             "function __wxShuffle(a){for(let i=a.length-1;i>0;i--){const j=Math.floor(__wxRand()*(i+1));const t=a[i];a[i]=a[j];a[j]=t;}return a;}\n"
             "const origToDataURL=HTMLCanvasElement&&HTMLCanvasElement.prototype?HTMLCanvasElement.prototype.toDataURL:null;\n"
             "const origToBlob=HTMLCanvasElement&&HTMLCanvasElement.prototype?HTMLCanvasElement.prototype.toBlob:null;\n"
             "const origGetImageData=window.CanvasRenderingContext2D?CanvasRenderingContext2D.prototype.getImageData:null;\n"
             "function addNoise(canvas){try{const ctx=canvas.getContext('2d');if(!ctx)return;const imageData=ctx.getImageData(0,0,canvas.width,canvas.height);const pixels=imageData.data;for(let i=0;i<pixels.length;i+=4){if(__wxRand()<0.02){const s=(__wxRand()<0.5?-1:1);pixels[i]=Math.max(0,Math.min(255,pixels[i]+s));pixels[i+1]=Math.max(0,Math.min(255,pixels[i+1]+s));pixels[i+2]=Math.max(0,Math.min(255,pixels[i+2]+s));}}ctx.putImageData(imageData,0,0);}catch(e){}}\n"
             "if(origToDataURL){HTMLCanvasElement.prototype.toDataURL=function(){addNoise(this);return origToDataURL.apply(this,arguments);};}\n"
             "if(origToBlob){HTMLCanvasElement.prototype.toBlob=function(callback){addNoise(this);return origToBlob.apply(this,arguments);};}\n"
             "if(origGetImageData){CanvasRenderingContext2D.prototype.getImageData=function(){const imageData=origGetImageData.apply(this,arguments);try{const pixels=imageData.data;for(let i=0;i<pixels.length;i+=4){if(__wxRand()<0.02){const s=(__wxRand()<0.5?-1:1);pixels[i]=Math.max(0,Math.min(255,pixels[i]+s));pixels[i+1]=Math.max(0,Math.min(255,pixels[i+1]+s));pixels[i+2]=Math.max(0,Math.min(255,pixels[i+2]+s));}}}catch(e){}return imageData;};}\n"
             "if(window.WebGLRenderingContext){\n"
             "const spoofedVendor='%@';const spoofedRenderer='%@';\n"
             "const origGetParameter=WebGLRenderingContext.prototype.getParameter;\n"
             "WebGLRenderingContext.prototype.getParameter=function(param){if(param===37445)return spoofedVendor;if(param===37446)return spoofedRenderer;return origGetParameter.call(this,param);};\n"
             "const origGetSupportedExtensions=WebGLRenderingContext.prototype.getSupportedExtensions;\n"
             "WebGLRenderingContext.prototype.getSupportedExtensions=function(){const exts=origGetSupportedExtensions.call(this)||[];return __wxShuffle(exts.slice());};\n"
             "const origGetShaderPrecisionFormat=WebGLRenderingContext.prototype.getShaderPrecisionFormat;\n"
             "WebGLRenderingContext.prototype.getShaderPrecisionFormat=function(){const res=origGetShaderPrecisionFormat.apply(this,arguments);try{if(res&&typeof res==='object'){res.precision+=Math.floor(__wxRand()*2);}}catch(e){}return res;};\n"
             "}\n"
             "if(window.AnalyserNode){const orig=AnalyserNode.prototype.getFloatFrequencyData;AnalyserNode.prototype.getFloatFrequencyData=function(array){orig.call(this,array);for(let i=0;i<array.length;i++){array[i]+=(__wxRand()-0.5)*0.1;}};}\n"
             "if(window.AudioBuffer){const orig=AudioBuffer.prototype.getChannelData;AudioBuffer.prototype.getChannelData=function(){const data=orig.apply(this,arguments);for(let i=0;i<data.length;i+=100){data[i]+=(__wxRand()-0.5)*0.0001;}return data;};}\n"
             "if(window.CanvasRenderingContext2D){const orig=CanvasRenderingContext2D.prototype.measureText;CanvasRenderingContext2D.prototype.measureText=function(text){const r=orig.apply(this,arguments);try{Object.defineProperty(r,'width',{value:r.width*(1+(__wxRand()-0.5)*0.01)});}catch(e){}return r;};}\n"
             "if(window.navigator&&window.navigator.fonts&&window.navigator.fonts.query){const orig=window.navigator.fonts.query;window.navigator.fonts.query=function(){return orig.apply(this,arguments).then(function(fonts){try{return __wxShuffle(fonts.slice());}catch(e){return fonts;}});};}\n"
             "}catch(e){}})();",
            seed, unmaskedVendor, unmaskedRenderer];
}

// Update shouldProtectBundle to use only the new function
static BOOL shouldProtectBundle(NSString *bundleID) {
    if (!bundleID) return NO;
    // Check cache first
    if (!cachedBundleDecisions) {
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    } else {
        NSNumber *cachedDecision = cachedBundleDecisions[bundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]];
        if (cachedDecision && decisionTimestamp && 
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    BOOL shouldProtect = isCanvasFingerprintProtectionEnabledForCurrentApp() || PXFullSpoofTestModeEnabled();
    cachedBundleDecisions[bundleID] = @(shouldProtect);
    cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    return shouldProtect;
}

// Get or create a noise seed for consistent variations
static NSInteger getNoiseSeedForBundle(NSString *bundleID) {
    if (!noiseSeedCache) {
        noiseSeedCache = [NSMutableDictionary dictionary];
    }
    
    NSNumber *cachedSeed = noiseSeedCache[bundleID];
    if (cachedSeed) {
        return [cachedSeed integerValue];
    }
    
    // Create a new random seed
    NSInteger seed = arc4random_uniform(1000000);
    noiseSeedCache[bundleID] = @(seed);
    
    return seed;
}

// Add subtle noise to image data based on seed
static void addNoiseToImageData(NSMutableData *imageData, NSString *bundleID) {
    if (!imageData || imageData.length == 0) return;
    
    NSInteger seed = kConsistentNoise ? getNoiseSeedForBundle(bundleID) : arc4random_uniform(1000000);
    srand((unsigned int)seed);
    
    UInt8 *bytes = (UInt8 *)imageData.mutableBytes;
    NSUInteger length = imageData.length;
    
    // Skip the first 8 bytes (header data) to preserve PNG/JPEG validity
    NSUInteger startOffset = 8;
    
    // Add subtle noise to pixel values
    for (NSUInteger i = startOffset; i < length; i++) {
        // Apply noise with probability based on intensity
        if ((CGFloat)rand() / RAND_MAX < kNoiseIntensity) {
            // Add -1, 0, or +1 variation to byte value
            int variation = (rand() % 3) - 1;
            
            // Apply variation ensuring value stays within 0-255 range
            int newValue = bytes[i] + variation;
            bytes[i] = (UInt8)MAX(0, MIN(255, newValue));
        }
    }
}

// Helper: Check if current app is in the scoped apps list (copied from WiFiHook.x)
static BOOL isInScopedAppsList(void) {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || [bundleID length] == 0) {
            return NO;
        }
        NSArray *possiblePaths = @[@"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                                   @"/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                                   @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *validPath = nil;
        for (NSString *path in possiblePaths) {
            if ([fileManager fileExistsAtPath:path]) {
                validPath = path;
                break;
            }
        }
        if (!validPath) return NO;
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) return NO;
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) return NO;
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
    } @catch (NSException *e) {
        return NO;
    }
}

// Helper: Re-inject JS into all live WKWebViews
static void reinjectFingerprintProtectionScriptToAllWKWebViews() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return;

    NSDictionary *deviceIds = PXReadCurrentDeviceIdsForFingerprint();
    NSString *fpScript = shouldProtectBundle(bundleID) ? PXBuildSeededFingerprintProtectionScript(bundleID) : nil;
    NSString *screenScript = deviceIds ? PXBuildWebScreenSpoofScript(deviceIds) : nil;
    if (!fpScript && !screenScript) return;

    // Modern iOS 15+ way: enumerate all UIWindowScene windows
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            for (UIView *view in window.subviews) {
                if ([view isKindOfClass:[WKWebView class]]) {
                    WKWebView *webView = (WKWebView *)view;
                    if (screenScript) [webView evaluateJavaScript:screenScript completionHandler:nil];
                    if (fpScript) [webView evaluateJavaScript:fpScript completionHandler:nil];
                }
                // Recursively search subviews
                NSMutableArray *stack = [NSMutableArray arrayWithArray:view.subviews];
                while (stack.count > 0) {
                    UIView *subview = [stack lastObject];
                    [stack removeLastObject];
                    if ([subview isKindOfClass:[WKWebView class]]) {
                        WKWebView *webView = (WKWebView *)subview;
                        if (screenScript) [webView evaluateJavaScript:screenScript completionHandler:nil];
                        if (fpScript) [webView evaluateJavaScript:fpScript completionHandler:nil];
                    }
                    [stack addObjectsFromArray:subview.subviews];
                }
            }
        }
    }
}

#pragma mark - WKWebView Configuration Hooks

// Inject JS at document start for all WKWebViews
%hook WKWebViewConfiguration

- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return;

    NSDictionary *deviceIds = PXReadCurrentDeviceIdsForFingerprint();
    BOOL wantFP = shouldProtectBundle(bundleID);
    BOOL wantScreen = (deviceIds != nil) && PXDisplayWebScreenSpoofEnabled();
    if (!wantFP && !wantScreen) return;

    BOOL hasFP = NO;
    BOOL hasScreen = NO;
    for (WKUserScript *script in userContentController.userScripts) {
        NSString *src = script.source;
        if ([src containsString:@"__weaponx_fp_spoof__"]) hasFP = YES;
        if ([src containsString:@"__weaponx_screen_spoof__"]) hasScreen = YES;
    }

    if (wantScreen && !hasScreen) {
        NSString *screenScript = PXBuildWebScreenSpoofScript(deviceIds);
        if (screenScript.length) {
            WKUserScript *s = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:screenScript injectionTime:0 forMainFrameOnly:NO];
            [userContentController addUserScript:s];
        }
    }

    if (wantFP && !hasFP) {
        NSString *fpScript = PXBuildSeededFingerprintProtectionScript(bundleID);
        if (fpScript.length) {
            WKUserScript *s = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:fpScript injectionTime:0 forMainFrameOnly:NO];
            [userContentController addUserScript:s];
        }
    }
}

%end

#pragma mark - WKWebView Hooks

// Hook WKWebView to inject JavaScript that adds subtle noise to canvas operations
%hook WKWebView

- (void)_didFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return;

    NSDictionary *deviceIds = PXReadCurrentDeviceIdsForFingerprint();
    NSString *screenScript = deviceIds ? PXBuildWebScreenSpoofScript(deviceIds) : nil;
    NSString *fpScript = shouldProtectBundle(bundleID) ? PXBuildSeededFingerprintProtectionScript(bundleID) : nil;
    if (!screenScript && !fpScript) return;

    if (screenScript.length) {
        [self evaluateJavaScript:screenScript completionHandler:nil];
    }
    if (fpScript.length) {
        [self evaluateJavaScript:fpScript completionHandler:^(id result, NSError *error) {
            if (error) {
                PXLog(@"[CanvasFingerprint] Error injecting fingerprint protection script: %@", error);
            }
        }];
    }
}

%end

#pragma mark - UIImage+ImageIO Hooks

// Hook UIImage imageWithData method to protect screenshots and image generation
%hook UIImage

+ (UIImage *)imageWithData:(NSData *)data {
    UIImage *originalImage = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID) || !data) {
        return originalImage;
    }
    // Always add noise for protected apps
    @try {
        UIGraphicsBeginImageContextWithOptions(originalImage.size, NO, originalImage.scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        [originalImage drawInRect:CGRectMake(0, 0, originalImage.size.width, originalImage.size.height)];
        CGContextSetBlendMode(context, kCGBlendModeLighten);
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.01].CGColor);
        for (int i = 0; i < 20; i++) {
            CGFloat x = arc4random_uniform((uint32_t)originalImage.size.width);
            CGFloat y = arc4random_uniform((uint32_t)originalImage.size.height);
            CGContextFillRect(context, CGRectMake(x, y, 1, 1));
        }
        UIImage *modifiedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if (modifiedImage) {
            PXLog(@"[CanvasFingerprint] Noise added to image for %@", bundleID);
            return modifiedImage;
        }
    } @catch (NSException *exception) {
        PXLog(@"[CanvasFingerprint] Exception adding noise to image: %@", exception);
    }
    return originalImage;
}

%end

#pragma mark - WKNativeCanvas Hooks

// Hook WKNativeCanvas data access methods if they exist
%hook WKNativeCanvas

// Method for getting pixel data
- (NSData *)drawingData {
    NSData *originalData = %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID) || !originalData) {
        return originalData;
    }
    
    // Create a mutable copy to modify
    NSMutableData *modifiedData = [originalData mutableCopy];
    
    // Add noise to the image data
    addNoiseToImageData(modifiedData, bundleID);
    
    return modifiedData;
}

%end

#pragma mark - Notification Handlers

// Refresh settings when profile or settings change
static void refreshSettings(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    PXLog(@"[CanvasFingerprint] Received settings notification: %@", notificationName);
    [cachedBundleDecisions removeAllObjects];
    cacheTimestamp = [NSDate date];
        [noiseSeedCache removeAllObjects];
    reinjectFingerprintProtectionScriptToAllWKWebViews();
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        PXLog(@"[CanvasFingerprint] Initializing Canvas Fingerprint Protection hooks");
        BOOL allowSafari = PXAllowUnscopedSafariStack() && (isCanvasFingerprintProtectionEnabledForCurrentApp() || PXFullSpoofTestModeEnabled() || PXDisplayWebScreenSpoofEnabled());
        if (!isInScopedAppsList() && !allowSafari) {
            PXLog(@"[CanvasFingerprint] App is not scoped, skipping hook installation");
            return;
        }
        // Initialize caches
        cachedBundleDecisions = [NSMutableDictionary dictionary];
        noiseSeedCache = [NSMutableDictionary dictionary];
        cacheTimestamp = [NSDate date];
        // Register for notifications about profile or settings changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.settings.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.profileChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.toggleCanvasFingerprint"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.canvasFingerprintToggleChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.enableCanvasFingerprintProtection"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.disableCanvasFingerprintProtection"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.resetCanvasNoise"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        // Initialize hooks
        %init();
    }
} 
