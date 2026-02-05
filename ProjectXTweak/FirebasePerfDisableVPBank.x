// FirebasePerfDisableVPBank.x
// VPBank NEO (com.vnp.VpBankOnline) crashes inside FirebasePerformance instrumentation.
// Disable Firebase Performance data collection/instrumentation for this app.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <syslog.h>

static BOOL PXIsVPBankNEO(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    return [bid isEqualToString:@"com.vnp.VpBankOnline"];
}

static void PXDisableFIRPerformance(void) {
    Class perfCls = NSClassFromString(@"FIRPerformance");
    if (!perfCls) {
        syslog(LOG_NOTICE, "[ProjectX] FIRPerformance not present");
        return;
    }

    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (![perfCls respondsToSelector:sharedSel]) {
        syslog(LOG_NOTICE, "[ProjectX] FIRPerformance sharedInstance missing");
        return;
    }

    id perf = ((id (*)(id, SEL))objc_msgSend)(perfCls, sharedSel);
    if (!perf) {
        syslog(LOG_NOTICE, "[ProjectX] FIRPerformance sharedInstance returned nil");
        return;
    }

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

    syslog(LOG_NOTICE, "[ProjectX] Disabled Firebase Performance for com.vnp.VpBankOnline");
}

__attribute__((constructor(101)))
static void PXFirebasePerfDisableCtor(void) {
    @autoreleasepool {
        if (!PXIsVPBankNEO()) return;

        // Run immediately and also retry on main queue (some Firebase classes may load later).
        PXDisableFIRPerformance();
        dispatch_async(dispatch_get_main_queue(), ^{
            PXDisableFIRPerformance();
        });
    }
}
