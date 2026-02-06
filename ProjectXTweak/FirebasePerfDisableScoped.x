// FirebasePerfDisableScoped.x
// FirebasePerformance has been observed crashing in some apps when combined with other
// instrumentation / hooks. Disable Firebase Performance collection+instrumentation for
// apps that are in ProjectX scope.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <syslog.h>
#include <string.h>

#import "PXScope.h"

static BOOL PXIsInProjectXScope(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return NO;

    // Respect Safari/Auth stack allowance when spoofing is enabled.
    if (PXAllowUnscopedSafariStack()) return YES;

    Class mgrCls = NSClassFromString(@"IdentifierManager");
    if (!mgrCls) return NO;

    SEL sharedSel = NSSelectorFromString(@"sharedManager");
    if (![mgrCls respondsToSelector:sharedSel]) return NO;

    id mgr = ((id (*)(id, SEL))objc_msgSend)(mgrCls, sharedSel);
    if (!mgr) return NO;

    SEL enabledSel = NSSelectorFromString(@"isApplicationEnabled:");
    if (![mgr respondsToSelector:enabledSel]) return NO;

    BOOL enabled = ((BOOL (*)(id, SEL, id))objc_msgSend)(mgr, enabledSel, bundleID);
    return enabled;
}

static void PXDisableFIRPerformance(void) {
    Class perfCls = NSClassFromString(@"FIRPerformance");
    if (!perfCls) return;

    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (![perfCls respondsToSelector:sharedSel]) return;

    id perf = ((id (*)(id, SEL))objc_msgSend)(perfCls, sharedSel);
    if (!perf) return;

    // Turn off both collection and instrumentation when available.
    SEL setInstrSel = NSSelectorFromString(@"setInstrumentationEnabled:");
    if ([perf respondsToSelector:setInstrSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(perf, setInstrSel, NO);
    }

    SEL setDataSel = NSSelectorFromString(@"setDataCollectionEnabled:");
    if ([perf respondsToSelector:setDataSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(perf, setDataSel, NO);
    }

    // Some SDK versions expose class-level enable switch.
    SEL setCollSel = NSSelectorFromString(@"setPerformanceCollectionEnabled:");
    if ([perfCls respondsToSelector:setCollSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(perfCls, setCollSel, NO);
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"(unknown)";
    syslog(LOG_NOTICE, "[ProjectX] Disabled Firebase Performance for %s", bundleID.UTF8String);
}

__attribute__((constructor(101)))
static void PXFirebasePerfDisableCtor(void) {
    extern const char *__progname;
    if (__progname && strcmp(__progname, "MB Bank") == 0) {
        return;
    }
    @autoreleasepool {
        // Try early (some apps start Firebase very early).
        if (PXIsInProjectXScope()) {
            PXDisableFIRPerformance();
        }

        // Re-check on main queue (scope/Firebase may be ready later).
        dispatch_async(dispatch_get_main_queue(), ^{
            if (PXIsInProjectXScope()) {
                PXDisableFIRPerformance();
            }
        });
    }
}
