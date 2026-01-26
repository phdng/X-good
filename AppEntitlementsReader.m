#import "AppEntitlementsReader.h"

#import "AppDataCleaner.h"
#import "CommandRunner.h"

static NSString * const PXEntitlementsErrorDomain = @"com.hydra.projectx.entitlements";

@implementation AppEntitlementsReader

static NSString *PXShellQuote(NSString *s) {
    // Single-quote for /bin/sh; escape internal single quotes.
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]; // close, escape, reopen
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (NSArray<NSString *> *)applicationGroupsForBundleID:(NSString *)bundleID
                                                error:(NSError **)error {
    NSString *binaryPath = [self mainExecutablePathForBundleID:bundleID error:error];
    if (!binaryPath) {
        return @[];
    }

    CommandRunner *runner = [CommandRunner shared];
    NSString *ldidPath = [runner firstExistingPath:@[
        @"/usr/bin/ldid",
        @"/var/jb/usr/bin/ldid",
        @"/private/preboot/jb/usr/bin/ldid",
        @"/bin/ldid"
    ]];

    if (!ldidPath) {
        if (error) {
            *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"ldid not found"}];
        }
        return @[];
    }

    NSString *cmd = [NSString stringWithFormat:@"%@ -e %@", PXShellQuote(ldidPath), PXShellQuote(binaryPath)];
    CommandResult *res = [runner runAndCapture:cmd];
    if (res.exitCode != 0) {
        if (error) {
            NSString *msg = res.stderrString.length ? res.stderrString : @"ldid failed";
            *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return @[];
    }

    NSData *plistData = [res.stdoutString dataUsingEncoding:NSUTF8StringEncoding];
    if (!plistData.length) {
        if (error) {
            *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty entitlements output"}];
        }
        return @[];
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    NSError *plistError = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:plistData
                                                       options:NSPropertyListImmutable
                                                        format:&format
                                                         error:&plistError];
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = plistError ?: [NSError errorWithDomain:PXEntitlementsErrorDomain
                                                       code:4
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse entitlements plist"}];
        }
        return @[];
    }

    id groups = ((NSDictionary *)obj)[@"com.apple.security.application-groups"];
    if (![groups isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id g in (NSArray *)groups) {
        if ([g isKindOfClass:[NSString class]] && [(NSString *)g length] > 0) {
            [out addObject:g];
        }
    }
    return out;
}

- (NSString *)mainExecutablePathForBundleID:(NSString *)bundleID
                                     error:(NSError **)error {
    AppDataCleaner *cleaner = [AppDataCleaner sharedManager];
    NSString *bundleUUID = [cleaner findBundleContainerUUIDForBundleID:bundleID];
    if (!bundleUUID.length) {
        if (error) {
            *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bundle container UUID not found"}];
        }
        return nil;
    }

    NSArray<NSString *> *bundleBaseDirs = @[
        @"/var/containers/Bundle/Application",
        @"/var/mobile/Containers/Bundle/Application",
        @"/containers/Bundle/Application"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *base in bundleBaseDirs) {
        NSString *uuidPath = [base stringByAppendingPathComponent:bundleUUID];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:uuidPath isDirectory:&isDir] || !isDir) {
            continue;
        }

        NSError *listErr = nil;
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:uuidPath error:&listErr];
        if (!items.count) {
            continue;
        }

        for (NSString *item in items) {
            if (![item hasSuffix:@".app"]) {
                continue;
            }
            NSString *appPath = [uuidPath stringByAppendingPathComponent:item];
            NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            if (![info isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *foundBundleID = info[@"CFBundleIdentifier"];
            if (![foundBundleID isKindOfClass:[NSString class]] || ![foundBundleID isEqualToString:bundleID]) {
                continue;
            }
            NSString *exe = info[@"CFBundleExecutable"];
            if (![exe isKindOfClass:[NSString class]] || !exe.length) {
                if (error) {
                    *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                                 code:11
                                             userInfo:@{NSLocalizedDescriptionKey: @"CFBundleExecutable missing"}];
                }
                return nil;
            }
            NSString *binaryPath = [appPath stringByAppendingPathComponent:exe];
            if ([fm fileExistsAtPath:binaryPath]) {
                return binaryPath;
            }
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:PXEntitlementsErrorDomain
                                     code:12
                                 userInfo:@{NSLocalizedDescriptionKey: @"Main executable not found in bundle container"}];
    }
    return nil;
}

@end
