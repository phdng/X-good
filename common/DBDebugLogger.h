#import <Foundation/Foundation.h>

/// Appends DB/debug logs to a dedicated on-device file.
/// Rootful default path: /var/mobile/Library/WeaponX/Logs/db_debug.log
/// Falls back to /private/var/mobile/... when needed.
void PXDBLog(NSString *format, ...);
