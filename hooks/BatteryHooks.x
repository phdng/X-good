#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "BatteryManager.h"
#import "IdentifierManager.h"
#import "ProfileManager.h"

// Helper to check if battery spoofing is enabled for this app/profile
static BOOL isBatterySpoofingEnabled(void) {
    @try {
        if (!IsScope()) {
            return NO;
        }
        Class managerClass = NSClassFromString(@"IdentifierManager");
        if (!managerClass) {
            return NO;
        }
        id manager = [managerClass respondsToSelector:@selector(sharedManager)] ? [managerClass sharedManager] : nil;
        if (!manager) {
            return NO;
        }
        SEL isEnabledSel = NSSelectorFromString(@"isIdentifierEnabled:");
        if (![manager respondsToSelector:isEnabledSel]) {
            return NO;
        }
        NSString *batteryStr = @"Battery";
        BOOL enabled = NO;
        NSMethodSignature *sig = [manager methodSignatureForSelector:isEnabledSel];
        if (sig) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setSelector:isEnabledSel];
            [invocation setTarget:manager];
            [invocation setArgument:&batteryStr atIndex:2];
            [invocation invoke];
            [invocation getReturnValue:&enabled];
        }
        return enabled;
    } @catch (...) {
        return NO;
    }
}

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
}

// Optionally, hook batteryState (returns UIDeviceBatteryState)
static NSInteger (*orig_batteryState)(UIDevice *, SEL);
static NSInteger hook_batteryState(UIDevice *self, SEL _cmd) {
    return 1; // UIDeviceBatteryStateUnplugged
}

%ctor {
    @autoreleasepool {
        if(!isBatterySpoofingEnabled){
            return;
        }
        Class deviceClass = objc_getClass("UIDevice");
        if (deviceClass) {
            MSHookMessageEx(deviceClass, @selector(batteryLevel), (IMP)hook_batteryLevel, (IMP *)&orig_batteryLevel);
            MSHookMessageEx(deviceClass, @selector(batteryState), (IMP)hook_batteryState, (IMP *)&orig_batteryState);
        }
    }
} 