#import "DBDebugLogger.h"
#import <Foundation/Foundation.h>

static NSString *PXDBDebugLogFilePath(void) {
    // Prefer a WeaponX-owned log directory (separate from os_log/syslog).
    NSArray<NSString *> *dirs = @[
        @"/var/mobile/Library/WeaponX/Logs",
        @"/private/var/mobile/Library/WeaponX/Logs"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
            return [dir stringByAppendingPathComponent:@"db_debug.log"];
        }
    }

    // Try to create the preferred directory.
    NSString *preferred = dirs.firstObject;
    if (preferred.length) {
        NSError *e = nil;
        [fm createDirectoryAtPath:preferred withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755, NSFileOwnerAccountName: @"mobile"} error:&e];
        if (!e) {
            return [preferred stringByAppendingPathComponent:@"db_debug.log"];
        }
    }

    // Last resort.
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"db_debug.log"];
}

void PXDBLog(NSString *format, ...) {
    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"]; 
    });

    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[DB %@] %@\n", ts, msg ?: @""];
        NSString *path = PXDBDebugLogFilePath();

        static NSObject *lock = nil;
        static dispatch_once_t lockOnce;
        dispatch_once(&lockOnce, ^{
            lock = [NSObject new];
        });

        @synchronized(lock) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                return;
            }

            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!fh) {
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                return;
            }
            [fh seekToEndOfFile];
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                [fh writeData:data];
            }
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {
        // Intentionally ignore logging failures.
    }
}
