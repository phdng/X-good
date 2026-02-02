#import <Foundation/Foundation.h>

// Centralized scope helpers for ProjectXTweak.
// Goal: keep spoofing decisions consistent across modules, especially for Safari/Auth stack.

BOOL PXDeviceSpoofingEnabled(void);
BOOL PXSafariStackSpoofEnabled(void);

BOOL PXIsSafariStackProcess(NSString *bundleID, NSString *processName);
BOOL PXAllowUnscopedSafariStack(void);
