#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "BatteryManager.h"
#import "IdentifierManager.h"
#import "ProfileManager.h"

// Helper: get battery level from profile battery_info.plist
static NSString *getProfileBatteryLevel(void) {
    @try {
        // Get current profile ID
        NSString *identityDir = [[ProfileManager sharedManager] profileIdentityPath];
        NSString *batteryInfoPath = [identityDir stringByAppendingPathComponent:@"battery_info.plist"];
        NSDictionary *batteryInfo = [NSDictionary dictionaryWithContentsOfFile:batteryInfoPath];
        if (!batteryInfo) {
            return nil;
        }
        NSString *level = batteryInfo[@"BatteryLevel"];
        if (level && [level floatValue] >= 0.01 && [level floatValue] <= 1.0) {
            return level;
        }
        return nil;
    } @catch (NSException *e) {
        return nil;
    }
}

// Hook for -[UIDevice batteryLevel]
static float (*orig_batteryLevel)(UIDevice *, SEL);
static float hook_batteryLevel(UIDevice *self, SEL _cmd) {
    NSString *spoofed = getProfileBatteryLevel();
    if (spoofed) {
        float spoofedValue = [spoofed floatValue];
        if (spoofedValue >= 0.01 && spoofedValue <= 1.0) {
            return spoofedValue;
        }
    }
    return orig_batteryLevel(self,_cmd);
}

// Optionally, hook batteryState (returns UIDeviceBatteryState)
static NSInteger (*orig_batteryState)(UIDevice *, SEL);
static NSInteger hook_batteryState(UIDevice *self, SEL _cmd) {
    return 1; // UIDeviceBatteryStateUnplugged
}

%ctor {
    @autoreleasepool {
        if(!IsScope()) return;
        Class deviceClass = objc_getClass("UIDevice");
        if (deviceClass) {
            MSHookMessageEx(deviceClass, @selector(batteryLevel), (IMP)hook_batteryLevel, (IMP *)&orig_batteryLevel);
            MSHookMessageEx(deviceClass, @selector(batteryState), (IMP)hook_batteryState, (IMP *)&orig_batteryState);
        }
    }
} 