#import "AppDataBackupManager.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "AppDataCleaner.h"
#import "FreezeManager.h"

#import "AppEntitlementsReader.h"
#import "AppGroupContainerResolver.h"
#import "CommandRunner.h"

#import <CommonCrypto/CommonDigest.h>

static NSString * const PXBackupErrorDomain = @"com.hydra.projectx.backup";

@implementation PXBackupResult
@end

@implementation PXRestoreResult
@end

@implementation AppDataBackupManager

static void PXDebugAppendLine(NSString *path, NSString *line) {
    if (!path.length || !line.length) return;
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (dir.length) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *out = [line stringByAppendingString:@"\n"];
        NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;

        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [data writeToFile:path atomically:YES];
            return;
        }
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {
        }
        [fh closeFile];
    }
}

static void PXDebugHeader(NSString *path, NSString *title) {
    PXDebugAppendLine(path, @"----------------------------------------");
    PXDebugAppendLine(path, [NSString stringWithFormat:@"[%@] %@", [NSDate date], title ?: @""]);
}

static void PXDebugRun(CommandRunner *runner, NSString *path, NSString *label, NSString *cmd) {
    if (!runner || !path.length || !cmd.length) return;
    PXDebugAppendLine(path, [NSString stringWithFormat:@"> %@", label ?: @"cmd"]);
    PXDebugAppendLine(path, [NSString stringWithFormat:@"$ %@", cmd]);
    CommandResult *res = [runner runAndCapture:cmd];
    PXDebugAppendLine(path, [NSString stringWithFormat:@"exit=%d", (int)res.exitCode]);
    if (res.stdoutString.length) {
        PXDebugAppendLine(path, @"[stdout]");
        PXDebugAppendLine(path, res.stdoutString);
    }
    if (res.stderrString.length) {
        PXDebugAppendLine(path, @"[stderr]");
        PXDebugAppendLine(path, res.stderrString);
    }
}

static NSDictionary *PXResolvePathsForBundleID(NSString *bundleID) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"bundleID"] = bundleID ?: @"";

    NSString *dataPath = PXDataContainerPathFromLaunchServices(bundleID);
    if (dataPath) out[@"lsDataContainerPath"] = dataPath;

    // Also capture containerURL for debugging (may be bundle container).
    NSString *containerURLPath = nil;
    @autoreleasepool {
        Class LSApplicationProxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (LSApplicationProxyClass && [LSApplicationProxyClass respondsToSelector:sel]) {
            id proxy = ((id (*)(id, SEL, id))objc_msgSend)(LSApplicationProxyClass, sel, bundleID);
            if (proxy) {
                id url = nil;
                @try { url = [proxy valueForKey:@"containerURL"]; } @catch (__unused NSException *e) {}
                if ([url isKindOfClass:[NSURL class]]) {
                    containerURLPath = [(NSURL *)url path];
                } else if ([url isKindOfClass:[NSString class]]) {
                    containerURLPath = (NSString *)url;
                }
            }
        }
    }
    if (containerURLPath) out[@"lsContainerURLPath"] = containerURLPath;

    return out;
}

+ (instancetype)shared {
    static AppDataBackupManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

static NSString *PXShellQuote(NSString *s) {
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]; 
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static NSString *PXSanitizeFilenameComponent(NSString *s) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"].invertedSet;
    NSString *out = [[s componentsSeparatedByCharactersInSet:allowed] componentsJoinedByString:@"_"];
    return out.length ? out : @"unknown";
}

static NSString *PXDataContainerPathFromLaunchServices(NSString *bundleID) {
    if (!bundleID.length) return nil;
    Class LSApplicationProxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!LSApplicationProxyClass) return nil;

    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![LSApplicationProxyClass respondsToSelector:sel]) return nil;

    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(LSApplicationProxyClass, sel, bundleID);
    if (!proxy) return nil;

    id url = nil;
    @try {
        url = [proxy valueForKey:@"dataContainerURL"]; 
        if (!url) {
            url = [proxy valueForKey:@"containerURL"]; 
        }
    } @catch (__unused NSException *e) {
        url = nil;
    }
    if ([url isKindOfClass:[NSURL class]]) {
        return [(NSURL *)url path];
    }
    if ([url isKindOfClass:[NSString class]]) {
        return (NSString *)url;
    }
    return nil;
}

static NSString *PXBackupKeychainGroupsKey(NSString *bundleID) {
    return [NSString stringWithFormat:@"dataBackupKeychainGroups_%@", bundleID ?: @""];
}

static NSData *PXFileSHA256(NSString *path) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    for (;;) {
        @autoreleasepool {
            NSData *data = [fh readDataOfLength:(1024 * 1024)];
            if (!data.length) {
                break;
            }
            CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
        }
    }
    [fh closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

static NSString *PXHexString(NSData *data) {
    if (!data.length) return @"";
    const unsigned char *bytes = data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [out appendFormat:@"%02x", bytes[i]];
    }
    return out;
}

static NSDictionary *PXArtifactInfo(NSString *path, NSString *name) {
    if (!path.length) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    NSNumber *size = attrs[NSFileSize];
    NSData *sha = PXFileSHA256(path);
    return @{
        @"name": name ?: path.lastPathComponent ?: @"",
        @"path": path,
        @"size": size ?: @0,
        @"sha256": sha ? PXHexString(sha) : @""
    };
}

static BOOL PXContainerUUIDMatchesBundleID(NSFileManager *fm, NSString *baseDir, NSString *uuid, NSString *bundleID) {
    if (!baseDir.length || !uuid.length || !bundleID.length) return NO;
    NSString *containerPath = [baseDir stringByAppendingPathComponent:uuid];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:containerPath isDirectory:&isDir] || !isDir) return NO;
    NSString *metadataPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
    id ident = [meta isKindOfClass:[NSDictionary class]] ? meta[@"MCMMetadataIdentifier"] : nil;
    if ([ident isKindOfClass:[NSString class]]) {
        return [(NSString *)ident isEqualToString:bundleID];
    }
    if ([ident isKindOfClass:[NSArray class]]) {
        return [(NSArray *)ident containsObject:bundleID];
    }
    return NO;
}

static NSString *PXFindDataContainerUUIDByMetadata(NSFileManager *fm, NSString *baseDir, NSString *bundleID) {
    if (!baseDir.length || !bundleID.length) return nil;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:baseDir isDirectory:&isDir] || !isDir) return nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:baseDir error:nil];
    for (NSString *uuid in items) {
        if (![uuid isKindOfClass:[NSString class]] || uuid.length < 8) continue;
        if ([uuid hasPrefix:@"."]) continue;
        if (PXContainerUUIDMatchesBundleID(fm, baseDir, uuid, bundleID)) {
            return uuid;
        }
    }
    return nil;
}

- (void)_killRelatedProcessesForBundleID:(NSString *)bundleID {
    // Always kill the main app process via existing manager.
    [[FreezeManager sharedManager] killApplication:bundleID];

    // Safari has multiple helper processes that can keep databases open.
    if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
        CommandRunner *runner = [CommandRunner shared];
        NSArray<NSString *> *names = @[
            @"MobileSafari",
            @"SafariViewService",
            @"com.apple.WebKit.WebContent",
            @"com.apple.WebKit.Networking"
        ];
        for (NSString *name in names) {
            [runner run:[NSString stringWithFormat:@"killall -9 %@ 2>/dev/null || true", PXShellQuote(name)]];
        }
    }
}

- (NSString *)_globalSafariLibraryPath {
    CommandRunner *runner = [CommandRunner shared];
    return [runner firstExistingPath:@[
        @"/var/mobile/Library/Safari",
        @"/private/var/mobile/Library/Safari",
        @"/var/jb/var/mobile/Library/Safari",
        @"/private/var/jb/var/mobile/Library/Safari"
    ]];
}

- (CommandResult *)_tarCreate:(NSString *)tarPath fromDir:(NSString *)sourceDir toArchive:(NSString *)archivePath {
    CommandRunner *runner = [CommandRunner shared];

    // Prefer preserving extended attributes (file protection class), ACLs and numeric owners.
    NSString *cmd = [NSString stringWithFormat:@"%@ --xattrs --acls --numeric-owner -czf %@ --exclude '.com.apple.mobile_container_manager.metadata.plist' --exclude '.com.apple.containermanagerd.metadata.plist' -C %@ .",
                     PXShellQuote(tarPath),
                     PXShellQuote(archivePath),
                     PXShellQuote(sourceDir)];
    CommandResult *res = [runner runAndCapture:cmd];
    if (res.exitCode == 0) {
        return res;
    }

    // Fallback for tar variants without these flags.
    NSString *fallback = [NSString stringWithFormat:@"%@ -czf %@ --exclude '.com.apple.mobile_container_manager.metadata.plist' --exclude '.com.apple.containermanagerd.metadata.plist' -C %@ .",
                          PXShellQuote(tarPath),
                          PXShellQuote(archivePath),
                          PXShellQuote(sourceDir)];
    return [runner runAndCapture:fallback];
}

- (CommandResult *)_tarExtract:(NSString *)tarPath archive:(NSString *)archivePath toDir:(NSString *)destDir {
    CommandRunner *runner = [CommandRunner shared];

    NSString *cmd = [NSString stringWithFormat:@"%@ --xattrs --acls -xzf %@ -C %@",
                     PXShellQuote(tarPath),
                     PXShellQuote(archivePath),
                     PXShellQuote(destDir)];
    CommandResult *res = [runner runAndCapture:cmd];
    if (res.exitCode == 0) {
        return res;
    }

    NSString *fallback = [NSString stringWithFormat:@"%@ -xzf %@ -C %@",
                          PXShellQuote(tarPath),
                          PXShellQuote(archivePath),
                          PXShellQuote(destDir)];
    return [runner runAndCapture:fallback];
}

- (NSString *)_preferencesDirectory {
    // Support rootful + common jailbreak layouts.
    CommandRunner *runner = [CommandRunner shared];
    NSString *dir = [runner firstExistingPath:@[
        @"/var/mobile/Library/Preferences",
        @"/private/var/mobile/Library/Preferences",
        @"/var/jb/var/mobile/Library/Preferences",
        @"/private/var/jb/var/mobile/Library/Preferences"
    ]];
    return dir ?: @"/var/mobile/Library/Preferences";
}

- (NSString *)_profileAppDataPathForBundleID:(NSString *)bundleID {
    NSString *profileId = [self _activeProfileId];
    if (!profileId.length || !bundleID.length) {
        return nil;
    }

    CommandRunner *runner = [CommandRunner shared];
    NSString *path = [runner firstExistingPath:@[
        [NSString stringWithFormat:@"/var/mobile/Library/WeaponX/Profiles/%@/appdata/%@", profileId, bundleID],
        [NSString stringWithFormat:@"/private/var/mobile/Library/WeaponX/Profiles/%@/appdata/%@", profileId, bundleID]
    ]];
    return path;
}

- (void)_wipeDirectoryContents:(NSString *)dirPath {
    if (!dirPath.length) {
        return;
    }
    // Wipe everything inside the directory, but preserve container metadata files.
    // Deleting these can break MCM/LaunchServices container mapping (especially for App Groups).
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *listErr = nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dirPath error:&listErr];
    if (!items.count) {
        return;
    }
    NSSet<NSString *> *preserve = [NSSet setWithArray:@[
        @".com.apple.mobile_container_manager.metadata.plist",
        @".com.apple.containermanagerd.metadata.plist"
    ]];
    for (NSString *name in items) {
        if (![name isKindOfClass:[NSString class]] || !name.length) continue;
        if ([preserve containsObject:name]) {
            continue;
        }
        NSString *p = [dirPath stringByAppendingPathComponent:name];
        [fm removeItemAtPath:p error:nil];
    }
}

- (NSString *)_preferencesPlistPathForBundleID:(NSString *)bundleID {
    NSString *prefsDir = [self _preferencesDirectory];
    return [prefsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
}

#pragma mark - Keychain Backup/Restore Helpers

- (NSString *)_keychainBackupScriptPath {
    CommandRunner *runner = [CommandRunner shared];
    return [runner firstExistingPath:@[
        @"/Library/WeaponX/keychain_backup.sh",
        @"/var/jb/Library/WeaponX/keychain_backup.sh"
    ]];
}

- (BOOL)_backupKeychainForBundleID:(NSString *)bundleID
                            groups:(NSArray<NSString *> *)groups
                            toFile:(NSString *)backupFile
                          warnings:(NSMutableArray<NSString *> *)warnings {
    NSString *scriptPath = [self _keychainBackupScriptPath];
    if (!scriptPath) {
        [warnings addObject:@"Keychain backup script not found; skipping keychain backup"];
        return NO;
    }
    
    CommandRunner *runner = [CommandRunner shared];
    NSString *groupsArg = groups.count ? [NSString stringWithFormat:@" --groups %@", PXShellQuote([groups componentsJoinedByString:@","])] : @"";
    NSString *cmd = [NSString stringWithFormat:@"%@ backup %@ %@%@",
                     PXShellQuote(scriptPath),
                     PXShellQuote(bundleID),
                     PXShellQuote(backupFile),
                     groupsArg];
    
    CommandResult *res = [runner runAndCapture:cmd];
    if (res.exitCode != 0) {
        NSString *stderrMsg = res.stderrString.length ? res.stderrString : @"";
        NSString *stdoutMsg = res.stdoutString.length ? res.stdoutString : @"";
        NSMutableString *msg = [NSMutableString stringWithString:@"Keychain backup failed"]; 
        if (stderrMsg.length) {
            [msg appendFormat:@"\nstderr: %@", stderrMsg];
        }
        if (stdoutMsg.length) {
            [msg appendFormat:@"\nstdout: %@", stdoutMsg];
        }
        [warnings addObject:[NSString stringWithFormat:@"Keychain backup: %@", msg]];
        return NO;
    }
    
    return [[NSFileManager defaultManager] fileExistsAtPath:backupFile];
}

- (BOOL)_restoreKeychainForBundleID:(NSString *)bundleID
                             groups:(NSArray<NSString *> *)groups
                           fromFile:(NSString *)backupFile
                          overwrite:(BOOL)overwrite
                           warnings:(NSMutableArray<NSString *> *)warnings {
    NSString *scriptPath = [self _keychainBackupScriptPath];
    if (!scriptPath) {
        [warnings addObject:@"Keychain backup script not found; skipping keychain restore"];
        return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:backupFile]) {
        [warnings addObject:@"Keychain backup file not found; skipping keychain restore"];
        return NO;
    }
    
    CommandRunner *runner = [CommandRunner shared];
    NSString *overwriteArg = overwrite ? @"--overwrite" : @"";
    NSString *groupsArg = groups.count ? [NSString stringWithFormat:@" --groups %@", PXShellQuote([groups componentsJoinedByString:@","])] : @"";
    NSString *cmd = [NSString stringWithFormat:@"%@ restore %@ %@ %@%@",
                     PXShellQuote(scriptPath),
                     PXShellQuote(bundleID),
                     PXShellQuote(backupFile),
                     overwriteArg,
                     groupsArg];
    
    CommandResult *res = [runner runAndCapture:cmd];
    // Store last keychain restore output for debugging
    NSDictionary *report = @{
        @"bundleID": bundleID ?: @"",
        @"groups": groups ?: @[],
        @"cmd": cmd ?: @"",
        @"exitCode": @(res.exitCode),
        @"stdout": res.stdoutString ?: @"",
        @"stderr": res.stderrString ?: @"",
    };
    [[NSUserDefaults standardUserDefaults] setObject:report forKey:[NSString stringWithFormat:@"PXKeychainRestoreResult_%@", bundleID]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (res.exitCode != 0) {
        NSString *stderrMsg = res.stderrString.length ? res.stderrString : @"";
        NSString *stdoutMsg = res.stdoutString.length ? res.stdoutString : @"";
        NSMutableString *msg = [NSMutableString stringWithString:@"Keychain restore failed"]; 
        if (stderrMsg.length) {
            [msg appendFormat:@"\nstderr: %@", stderrMsg];
        }
        if (stdoutMsg.length) {
            [msg appendFormat:@"\nstdout: %@", stdoutMsg];
        }
        [warnings addObject:[NSString stringWithFormat:@"Keychain restore: %@", msg]];
        return NO;
    }
    
    return YES;
}

- (NSString *)_backupRoot {
    NSString *profileId = [self _activeProfileId];
    if (profileId.length) {
        return [NSString stringWithFormat:@"/var/mobile/Library/WeaponX/Profiles/%@/backups", profileId];
    }
    // Fallback to legacy global backups directory
    return @"/var/mobile/Library/WeaponX/Backups";
}

// Central profile ID helper (profile switch integration)
- (NSString *)_activeProfileId {
    // Read from the same central store used across the project.
    NSString *centralInfoPath = @"/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
    NSString *profileId = [centralInfo isKindOfClass:[NSDictionary class]] ? centralInfo[@"ProfileId"] : nil;
    if ([profileId isKindOfClass:[NSString class]] && profileId.length) {
        return profileId;
    }

    NSString *fallbackPath = @"/var/mobile/Library/WeaponX/active_profile_info.plist";
    NSDictionary *fallbackInfo = [NSDictionary dictionaryWithContentsOfFile:fallbackPath];
    profileId = [fallbackInfo isKindOfClass:[NSDictionary class]] ? fallbackInfo[@"ProfileId"] : nil;
    if ([profileId isKindOfClass:[NSString class]] && profileId.length) {
        return profileId;
    }

    return nil;
}

- (NSString *)_timestampString {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"]; 
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    return [fmt stringFromDate:[NSDate date]];
}

- (NSArray<NSString *> *)listBackupDirectoriesForBundleID:(NSString *)bundleID {
    if (!bundleID.length) {
        return @[];
    }
    NSString *dir = [[self _backupRoot] stringByAppendingPathComponent:bundleID];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSMutableArray<NSString *> *dirs = [NSMutableArray array];

    BOOL isDir = NO;
    if ([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in items) {
            NSString *path = [dir stringByAppendingPathComponent:item];
            BOOL itemIsDir = NO;
            if ([fm fileExistsAtPath:path isDirectory:&itemIsDir] && itemIsDir) {
                NSString *manifest = [path stringByAppendingPathComponent:@"manifest.plist"];
                if ([fm fileExistsAtPath:manifest]) {
                    [dirs addObject:path];
                }
            }
        }
    }

    // Also include legacy global backups if present (so users can migrate smoothly)
    NSString *legacyDir = [@"/var/mobile/Library/WeaponX/Backups" stringByAppendingPathComponent:bundleID];
    BOOL legacyIsDir = NO;
    if (![legacyDir isEqualToString:dir] && [fm fileExistsAtPath:legacyDir isDirectory:&legacyIsDir] && legacyIsDir) {
        NSArray<NSString *> *legacyItems = [fm contentsOfDirectoryAtPath:legacyDir error:nil];
        for (NSString *item in legacyItems) {
            NSString *path = [legacyDir stringByAppendingPathComponent:item];
            BOOL itemIsDir = NO;
            if ([fm fileExistsAtPath:path isDirectory:&itemIsDir] && itemIsDir) {
                NSString *manifest = [path stringByAppendingPathComponent:@"manifest.plist"];
                if ([fm fileExistsAtPath:manifest]) {
                    [dirs addObject:path];
                }
            }
        }
    }

    [dirs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        // Sort newest-first based on the last path component (timestamp folder convention).
        return [b.lastPathComponent compare:a.lastPathComponent];
    }];
    return dirs;
}

- (NSDictionary *)readManifestAtBackupDirectory:(NSString *)backupDir
                                          error:(NSError **)error {
    NSString *manifest = [backupDir stringByAppendingPathComponent:@"manifest.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:manifest];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PXBackupErrorDomain
                                         code:200
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to read manifest"}];
        }
        return nil;
    }
    return dict;
}

- (void)createBackupForBundleID:(NSString *)bundleID
                        appName:(NSString *)appName
                        options:(PXBackupOptions)options
                     completion:(void (^)(PXBackupResult *, NSError *))completion {
    if (!bundleID.length) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:PXBackupErrorDomain
                                                code:100
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing bundleID"}]);
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSString *> *warnings = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        CommandRunner *runner = [CommandRunner shared];

        NSString *profileId = [self _activeProfileId];

        NSString *tarPath = [runner firstExistingPath:@[
            @"/usr/bin/tar",
            @"/var/jb/usr/bin/tar",
            @"/private/preboot/jb/usr/bin/tar",
            @"/bin/tar"
        ]];
        if (!tarPath) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:101
                                           userInfo:@{NSLocalizedDescriptionKey: @"tar not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        // Prefer LaunchServices-reported container path (active container).
        NSString *dataContainerPath = nil;
        NSString *dataUUID = nil;
        {
            NSString *lsPath = PXDataContainerPathFromLaunchServices(bundleID);
            BOOL isDir = NO;
            if (lsPath.length && [fm fileExistsAtPath:lsPath isDirectory:&isDir] && isDir) {
                dataContainerPath = lsPath;
                dataUUID = lsPath.lastPathComponent;
            }
        }

        if (!dataContainerPath) {
            NSArray<NSString *> *bases = @[@"/var/mobile/Containers/Data/Application", @"/private/var/mobile/Containers/Data/Application", @"/containers/Data/Application", @"/private/var/containers/Data/Application"]; 
            for (NSString *base in bases) {
                NSString *found = PXFindDataContainerUUIDByMetadata(fm, base, bundleID);
                if (found.length) {
                    NSString *p = [base stringByAppendingPathComponent:found];
                    BOOL isDir = NO;
                    if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                        dataUUID = found;
                        dataContainerPath = p;
                        break;
                    }
                }
            }
            if (!dataContainerPath.length) {
                NSString *lsPath = PXDataContainerPathFromLaunchServices(bundleID) ?: @"";
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:102
                                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Data container not found (bundleID=%@ lsPath=%@)", bundleID, lsPath]}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }
        }

        if (!dataContainerPath.length) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:103
                                           userInfo:@{NSLocalizedDescriptionKey: @"Data container path missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSString *timestamp = [self _timestampString];
        NSString *backupDir = [[[self _backupRoot] stringByAppendingPathComponent:bundleID] stringByAppendingPathComponent:timestamp];
        NSString *debugBefore = [backupDir stringByAppendingPathComponent:@"debug_before_backup.txt"];
        NSString *debugAfter = [backupDir stringByAppendingPathComponent:@"debug_after_backup.txt"];
        NSString *debugKeychain = [backupDir stringByAppendingPathComponent:@"debug_keychain.txt"];
        NSString *groupsDir = [backupDir stringByAppendingPathComponent:@"groups"]; 
        NSString *prefsDir = [backupDir stringByAppendingPathComponent:@"preferences"]; 

        NSError *mkErr = nil;
        if (![fm createDirectoryAtPath:groupsDir withIntermediateDirectories:YES attributes:nil error:&mkErr]) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:104
                                           userInfo:@{NSLocalizedDescriptionKey: mkErr.localizedDescription ?: @"Failed to create backup directory"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }
        [fm createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:nil];

        // Restrict permissions best-effort
        [runner run:[NSString stringWithFormat:@"chmod 700 %@ 2>/dev/null || true", PXShellQuote(backupDir)]];
        [runner run:[NSString stringWithFormat:@"chmod 700 %@ 2>/dev/null || true", PXShellQuote(groupsDir)]];
        [runner run:[NSString stringWithFormat:@"chmod 700 %@ 2>/dev/null || true", PXShellQuote(prefsDir)]];

        // Debug snapshot: before backup
        {
            PXDebugHeader(debugBefore, @"Backup Start");
            NSDictionary *rp = PXResolvePathsForBundleID(bundleID);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"bundleID=%@", bundleID]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"profileId=%@", profileId ?: @""]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"timestamp=%@", timestamp]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"lsDataContainerPath=%@", rp[@"lsDataContainerPath"] ?: @""]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"lsContainerURLPath=%@", rp[@"lsContainerURLPath"] ?: @""]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"chosenDataContainerPath=%@", dataContainerPath ?: @""]);
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"chosenDataUUID=%@", dataUUID ?: @""]);
            PXDebugRun(runner, debugBefore, @"du data", [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]);
            PXDebugRun(runner, debugBefore, @"du library", [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library"]) ]);
            PXDebugRun(runner, debugBefore, @"ls root", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]);
            PXDebugRun(runner, debugBefore, @"ls library", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library"]) ]);
            PXDebugRun(runner, debugBefore, @"ls prefs", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library/Preferences"]) ]);
            PXDebugRun(runner, debugBefore, @"ls cookies", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library/Cookies"]) ]);
            PXDebugRun(runner, debugBefore, @"ls webkit", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library/WebKit"]) ]);

            // Snapshot-only (system-wide) paths for debugging (restore does NOT touch these by default)
            PXDebugHeader(debugBefore, @"System Snapshot (Debug Only)");
            PXDebugRun(runner, debugBefore, @"ls Accounts3", @"ls -lh /var/mobile/Library/Accounts/Accounts3.sqlite 2>/dev/null || true");
            PXDebugRun(runner, debugBefore, @"ls Cookies", @"ls -la /var/mobile/Library/Cookies 2>/dev/null || true");
            PXDebugRun(runner, debugBefore, @"ls WebKit WebsiteData", @"ls -la /var/mobile/Library/WebKit/WebsiteData 2>/dev/null || true");
        }

        // Initialize keychain debug file (even if keychain option is off)
        {
            PXDebugHeader(debugKeychain, @"Keychain Debug");
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"bundleID=%@", bundleID]);
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"profileId=%@", profileId ?: @""]);
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"backupDir=%@", backupDir]);
        }

        // Ensure target app is not running while archiving.
        [self _killRelatedProcessesForBundleID:bundleID];

        NSString *dataArchivePath = [backupDir stringByAppendingPathComponent:@"data.tar.gz"];
        CommandResult *tarRes = [self _tarCreate:tarPath fromDir:dataContainerPath toArchive:dataArchivePath];
        if (tarRes.exitCode != 0 || ![fm fileExistsAtPath:dataArchivePath]) {
            NSString *msg = tarRes.stderrString.length ? tarRes.stderrString : @"tar failed for data container";
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:105
                                           userInfo:@{NSLocalizedDescriptionKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSMutableArray<NSDictionary *> *groupManifests = [NSMutableArray array];
        NSArray<AppGroupContainerInfo *> *groupContainers = @[];
        NSArray<NSString *> *groupIDs = @[];

        if (options & PXBackupOptionIncludeAppGroups) {
            NSError *entErr = nil;
            AppEntitlementsReader *reader = [[AppEntitlementsReader alloc] init];
            groupIDs = [reader applicationGroupsForBundleID:bundleID error:&entErr];
            if (entErr) {
                [warnings addObject:[NSString stringWithFormat:@"Entitlements read failed: %@", entErr.localizedDescription]];
            }

            if (groupIDs.count) {
                AppGroupContainerResolver *resolver = [[AppGroupContainerResolver alloc] init];
                groupContainers = [resolver resolveGroupContainersForGroupIDs:groupIDs];
                if (!groupContainers.count) {
                    [warnings addObject:@"No App Group containers matched entitlements"];
                }
            }
        }

        // Debug snapshot: groups resolution
        {
            PXDebugHeader(debugBefore, @"App Groups Resolve");
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"groupIDs=%@", groupIDs ?: @[]]);
            NSMutableArray *paths = [NSMutableArray array];
            for (AppGroupContainerInfo *info in groupContainers) {
                [paths addObject:[NSString stringWithFormat:@"%@ => %@ (%@)", info.groupID ?: @"", info.path ?: @"", info.uuid ?: @""]];
                PXDebugRun(runner, debugBefore, [NSString stringWithFormat:@"du group %@", info.groupID ?: @""], [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote(info.path)]);
                PXDebugRun(runner, debugBefore, [NSString stringWithFormat:@"ls group %@", info.groupID ?: @""], [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(info.path)]);
            }
            PXDebugAppendLine(debugBefore, [NSString stringWithFormat:@"groupPaths=%@", paths]);
        }

        for (AppGroupContainerInfo *info in groupContainers) {
            NSString *archiveName = [NSString stringWithFormat:@"%@.tar.gz", PXSanitizeFilenameComponent(info.groupID)];
            NSString *archivePath = [groupsDir stringByAppendingPathComponent:archiveName];

            CommandResult *r = [self _tarCreate:tarPath fromDir:info.path toArchive:archivePath];
            if (r.exitCode != 0 || ![fm fileExistsAtPath:archivePath]) {
                [warnings addObject:[NSString stringWithFormat:@"Failed to archive group %@ (%@)", info.groupID, info.uuid]];
                continue;
            }

            [groupManifests addObject:@{
                @"groupID": info.groupID,
                @"uuid": info.uuid,
                @"archive": [@"groups" stringByAppendingPathComponent:archiveName]
            }];
        }

        // Profile redirected appdata (system apps like Safari may store most data here)
        NSString *profileAppDataPath = [self _profileAppDataPathForBundleID:bundleID];
        NSString *profileAppDataArchivePath = nil;
        if (profileAppDataPath.length) {
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:profileAppDataPath isDirectory:&isDir] && isDir) {
                profileAppDataArchivePath = [backupDir stringByAppendingPathComponent:@"profile_appdata.tar.gz"];
                CommandResult *r = [self _tarCreate:tarPath fromDir:profileAppDataPath toArchive:profileAppDataArchivePath];
                if (r.exitCode != 0 || ![fm fileExistsAtPath:profileAppDataArchivePath]) {
                    [warnings addObject:@"Failed to archive profile appdata; continuing" ];
                    profileAppDataArchivePath = nil;
                }
            }
        }

        // Global Library storage for Safari (history/bookmarks live under /var/mobile/Library/Safari)
        NSString *globalSafariPath = nil;
        NSString *globalSafariArchivePath = nil;
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            globalSafariPath = [self _globalSafariLibraryPath];
            if (globalSafariPath.length) {
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:globalSafariPath isDirectory:&isDir] && isDir) {
                    globalSafariArchivePath = [backupDir stringByAppendingPathComponent:@"global_safari.tar.gz"];
                    CommandResult *r = [self _tarCreate:tarPath fromDir:globalSafariPath toArchive:globalSafariArchivePath];
                    if (r.exitCode != 0 || ![fm fileExistsAtPath:globalSafariArchivePath]) {
                        [warnings addObject:@"Failed to archive global Safari library; continuing"];
                        globalSafariArchivePath = nil;
                    }
                }
            }
        }

        BOOL prefsIncluded = (options & PXBackupOptionIncludePreferences) != 0;
        NSString *prefSourcePath = [self _preferencesPlistPathForBundleID:bundleID];
        NSString *prefDestPath = [prefsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
        if (prefsIncluded) {
            if ([fm fileExistsAtPath:prefSourcePath]) {
                NSString *cpCmd = [NSString stringWithFormat:@"cp -f %@ %@ 2>/dev/null || true", PXShellQuote(prefSourcePath), PXShellQuote(prefDestPath)];
                [runner run:cpCmd];
                [runner run:[NSString stringWithFormat:@"chmod 600 %@ 2>/dev/null || true", PXShellQuote(prefDestPath)]];
            } else {
                [warnings addObject:@"Global preferences plist not found (OK for most apps); skipping"];
            }
        }

        // Keychain backup
        BOOL keychainIncluded = (options & PXBackupOptionIncludeKeychain) != 0;
        NSString *keychainBackupPath = nil;
        NSArray<NSString *> *selectedKeychainGroups = @[];
        if (keychainIncluded) {
            keychainBackupPath = [backupDir stringByAppendingPathComponent:@"keychain.plist"];
            // Default selection: ALL groups from entitlements if no saved preference.
            id saved = [[NSUserDefaults standardUserDefaults] objectForKey:PXBackupKeychainGroupsKey(bundleID)];
            if ([saved isKindOfClass:[NSArray class]] && [(NSArray *)saved count] > 0) {
                NSMutableArray<NSString *> *tmp = [NSMutableArray array];
                for (id v in (NSArray *)saved) {
                    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                        [tmp addObject:(NSString *)v];
                    }
                }
                selectedKeychainGroups = tmp;
            } else {
                NSError *entErr = nil;
                AppEntitlementsReader *reader = [[AppEntitlementsReader alloc] init];
                NSArray<NSString *> *entGroups = [reader keychainAccessGroupsForBundleID:bundleID error:&entErr];
                if (entGroups.count) {
                    selectedKeychainGroups = entGroups;
                    [[NSUserDefaults standardUserDefaults] setObject:entGroups forKey:PXBackupKeychainGroupsKey(bundleID)];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                } else if (entErr) {
                    [warnings addObject:[NSString stringWithFormat:@"Keychain groups read failed: %@", entErr.localizedDescription]];
                }
            }

            // Debug: list keychain items before backup
            {
                PXDebugHeader(debugKeychain, @"Keychain Before Backup");
                PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"selectedGroups=%@", selectedKeychainGroups ?: @[]]);
                NSString *scriptPath = [runner firstExistingPath:@[@"/Library/WeaponX/keychain_backup.sh",
                                                                  @"/var/jb/Library/WeaponX/keychain_backup.sh",
                                                                  @"/private/var/jb/Library/WeaponX/keychain_backup.sh"]];
                if (scriptPath.length && selectedKeychainGroups.count) {
                    NSString *csv = [selectedKeychainGroups componentsJoinedByString:@","];
                    PXDebugRun(runner, debugKeychain, @"list", [NSString stringWithFormat:@"%@ list %@ --groups %@", PXShellQuote(scriptPath), PXShellQuote(bundleID), PXShellQuote(csv)]);
                }
            }

            BOOL keychainSuccess = [self _backupKeychainForBundleID:bundleID
                                                            groups:selectedKeychainGroups
                                                            toFile:keychainBackupPath
                                                          warnings:warnings];
            if (!keychainSuccess) {
                keychainBackupPath = nil; // Mark as not included if failed
            } else {
                [runner run:[NSString stringWithFormat:@"chmod 600 %@ 2>/dev/null || true", PXShellQuote(keychainBackupPath)]];
                PXDebugHeader(debugKeychain, @"Keychain Backup Result");
                PXDebugAppendLine(debugKeychain, @"status=ok");
                PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"archive=%@", keychainBackupPath]);
                PXDebugRun(runner, debugKeychain, @"ls keychain.plist", [NSString stringWithFormat:@"ls -lh %@ 2>/dev/null || true", PXShellQuote(keychainBackupPath)]);
            }
        }

        UIDevice *device = [UIDevice currentDevice];
        NSString *iosVersion = device.systemVersion ?: @"";
        // profileId already computed above

        NSMutableArray *artifacts = [NSMutableArray array];
        NSDictionary *dataArtifact = PXArtifactInfo(dataArchivePath, @"data.tar.gz");
        if (dataArtifact) [artifacts addObject:dataArtifact];
        for (NSDictionary *g in groupManifests) {
            NSString *rel = g[@"archive"]; // groups/<name>.tar.gz
            if ([rel isKindOfClass:[NSString class]]) {
                NSString *abs = [backupDir stringByAppendingPathComponent:(NSString *)rel];
                NSDictionary *gi = PXArtifactInfo(abs, rel);
                if (gi) [artifacts addObject:gi];
            }
        }
        if (profileAppDataArchivePath) {
            NSDictionary *a = PXArtifactInfo(profileAppDataArchivePath, @"profile_appdata.tar.gz");
            if (a) [artifacts addObject:a];
        }
        if (globalSafariArchivePath) {
            NSDictionary *a = PXArtifactInfo(globalSafariArchivePath, @"global_safari.tar.gz");
            if (a) [artifacts addObject:a];
        }
        if (prefDestPath && [[NSFileManager defaultManager] fileExistsAtPath:prefDestPath]) {
            NSDictionary *a = PXArtifactInfo(prefDestPath, [NSString stringWithFormat:@"preferences/%@.plist", bundleID]);
            if (a) [artifacts addObject:a];
        }
        if (keychainBackupPath && [[NSFileManager defaultManager] fileExistsAtPath:keychainBackupPath]) {
            NSDictionary *a = PXArtifactInfo(keychainBackupPath, @"keychain.plist");
            if (a) [artifacts addObject:a];
        }

        NSDictionary *manifest = @{
            @"manifestVersion": @2,
            @"bundleID": bundleID,
            @"appName": appName ?: @"",
            @"timestamp": timestamp,
            @"iosVersion": iosVersion,
            @"profileId": profileId,
            @"data": @{
                @"uuid": dataUUID,
                @"archive": @"data.tar.gz",
                @"containerPath": dataContainerPath
            },
            @"applicationGroups": groupIDs ?: @[],
            @"appGroups": groupManifests,
            @"preferences": @{
                @"included": @(prefsIncluded),
                @"archive": [NSString stringWithFormat:@"preferences/%@.plist", bundleID]
            },
            @"keychain": @{
                @"included": @(keychainBackupPath != nil),
                @"archive": keychainBackupPath ? @"keychain.plist" : @"",
                @"groupsSelected": selectedKeychainGroups ?: @[]
            },
            @"profileAppData": @{
                @"included": @(profileAppDataArchivePath != nil),
                @"archive": profileAppDataArchivePath ? @"profile_appdata.tar.gz" : @"",
                @"path": profileAppDataPath ?: @""
            },
            @"globalSafari": @{
                @"included": @(globalSafariArchivePath != nil),
                @"archive": globalSafariArchivePath ? @"global_safari.tar.gz" : @"",
                @"path": globalSafariPath ?: @""
            },
            @"artifacts": artifacts,
            @"options": @{
                @"includeAppGroups": @((options & PXBackupOptionIncludeAppGroups) != 0),
                @"includePreferences": @(prefsIncluded),
                @"includeKeychain": @(keychainIncluded)
            }
        };

        // Debug snapshot: after backup artifacts
        {
            PXDebugHeader(debugAfter, @"Backup Artifacts");
            PXDebugAppendLine(debugAfter, [NSString stringWithFormat:@"backupDir=%@", backupDir]);
            PXDebugRun(runner, debugAfter, @"ls backupDir", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(backupDir)]);
            PXDebugRun(runner, debugAfter, @"ls groupsDir", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(groupsDir)]);
            PXDebugRun(runner, debugAfter, @"ls prefsDir", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(prefsDir)]);
            PXDebugRun(runner, debugAfter, @"ls data.tar.gz", [NSString stringWithFormat:@"ls -lh %@ 2>/dev/null || true", PXShellQuote(dataArchivePath)]);
            if (keychainBackupPath) {
                PXDebugRun(runner, debugAfter, @"ls keychain.plist", [NSString stringWithFormat:@"ls -lh %@ 2>/dev/null || true", PXShellQuote(keychainBackupPath)]);
            }
            PXDebugRun(runner, debugAfter, @"cat manifest.plist", [NSString stringWithFormat:@"ls -lh %@ 2>/dev/null || true", PXShellQuote([backupDir stringByAppendingPathComponent:@"manifest.plist"]) ]);
        }

        NSString *manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.plist"];
        if (![manifest writeToFile:manifestPath atomically:YES]) {
            [warnings addObject:@"Failed to write manifest"];
        } else {
            [runner run:[NSString stringWithFormat:@"chmod 600 %@ 2>/dev/null || true", PXShellQuote(manifestPath)]];
        }

        PXBackupResult *out = [[PXBackupResult alloc] init];
        out.backupDirectory = backupDir;
        out.manifestPath = manifestPath;
        out.warnings = warnings;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(out, nil);
            }
        });
    });
}

- (void)restoreBackupAtDirectory:(NSString *)backupDir
                        bundleID:(NSString *)bundleID
                         appName:(NSString *)appName
                     completion:(void (^)(PXRestoreResult *, NSError *))completion {
    if (!backupDir.length || !bundleID.length) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:PXBackupErrorDomain
                                                code:300
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing parameters"}]);
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSString *> *warnings = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        CommandRunner *runner = [CommandRunner shared];

        NSString *debugPre = [backupDir stringByAppendingPathComponent:@"debug_before_restore.txt"];
        NSString *debugPost = [backupDir stringByAppendingPathComponent:@"debug_after_restore.txt"];
        NSString *debugKeychain = [backupDir stringByAppendingPathComponent:@"debug_keychain.txt"];

        // Debug snapshot: restore start
        {
            PXDebugHeader(debugPre, @"Restore Start");
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"bundleID=%@", bundleID]);
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"appName=%@", appName ?: @""]);
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"backupDir=%@", backupDir]);
            NSDictionary *rp = PXResolvePathsForBundleID(bundleID);
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"lsDataContainerPath=%@", rp[@"lsDataContainerPath"] ?: @""]);
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"lsContainerURLPath=%@", rp[@"lsContainerURLPath"] ?: @""]);
            PXDebugRun(runner, debugPre, @"ls backupDir", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(backupDir)]);

            PXDebugHeader(debugPre, @"System Snapshot (Debug Only)");
            PXDebugRun(runner, debugPre, @"ls Accounts3", @"ls -lh /var/mobile/Library/Accounts/Accounts3.sqlite 2>/dev/null || true");
            PXDebugRun(runner, debugPre, @"ls Cookies", @"ls -la /var/mobile/Library/Cookies 2>/dev/null || true");
            PXDebugRun(runner, debugPre, @"ls WebKit WebsiteData", @"ls -la /var/mobile/Library/WebKit/WebsiteData 2>/dev/null || true");

            PXDebugHeader(debugKeychain, @"Keychain Debug");
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"bundleID=%@", bundleID]);
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"backupDir=%@", backupDir]);
        }

        NSString *tarPath = [runner firstExistingPath:@[
            @"/usr/bin/tar",
            @"/var/jb/usr/bin/tar",
            @"/private/preboot/jb/usr/bin/tar",
            @"/bin/tar"
        ]];
        if (!tarPath) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:301
                                           userInfo:@{NSLocalizedDescriptionKey: @"tar not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSString *manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.plist"];
        NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
        if (![manifest isKindOfClass:[NSDictionary class]]) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:302
                                           userInfo:@{NSLocalizedDescriptionKey: @"Manifest missing or invalid"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        // Kill app before restore
        [self _killRelatedProcessesForBundleID:bundleID];

        NSString *manifestProfileId = nil;
        if ([manifest[@"profileId"] isKindOfClass:[NSString class]]) {
            manifestProfileId = manifest[@"profileId"];
        }
        NSString *activeProfileId = [self _activeProfileId];
        if (manifestProfileId.length && activeProfileId.length && ![manifestProfileId isEqualToString:activeProfileId]) {
            [warnings addObject:[NSString stringWithFormat:@"Backup was created under profile %@ but current profile is %@", manifestProfileId, activeProfileId]];
        }

        // Data container lookup:
        // Prefer active container path (LaunchServices). Fall back to metadata scan.
        NSString *manifestDataUUID = nil;
        if ([manifest[@"data"] isKindOfClass:[NSDictionary class]] && [manifest[@"data"][@"uuid"] isKindOfClass:[NSString class]]) {
            manifestDataUUID = manifest[@"data"][@"uuid"];
        }
 
        NSString *dataUUID = nil;
        NSString *dataContainerPath = nil;

        // Prefer LaunchServices-reported container path (most reliable for the *active* container).
        {
            NSString *lsPath = PXDataContainerPathFromLaunchServices(bundleID);
            BOOL isDir = NO;
            if (lsPath.length && [fm fileExistsAtPath:lsPath isDirectory:&isDir] && isDir) {
                dataContainerPath = lsPath;
                dataUUID = lsPath.lastPathComponent;
            }
        }

        NSArray<NSString *> *bases = @[
            @"/var/mobile/Containers/Data/Application",
            @"/private/var/mobile/Containers/Data/Application",
            @"/containers/Data/Application",
            @"/private/var/containers/Data/Application"
        ];

        // Scan bases for a container with matching metadata.
        if (!dataContainerPath) {
            for (NSString *base in bases) {
                NSString *found = PXFindDataContainerUUIDByMetadata(fm, base, bundleID);
                if (found.length) {
                    dataUUID = found;
                    dataContainerPath = [base stringByAppendingPathComponent:found];
                    break;
                }
            }
        }

        // Fallback: use manifest containerPath/UUID if directory exists (useful after aggressive clears).
        if (!dataContainerPath) {
            NSString *p = nil;
            if ([manifest[@"data"] isKindOfClass:[NSDictionary class]] && [manifest[@"data"][@"containerPath"] isKindOfClass:[NSString class]]) {
                p = manifest[@"data"][@"containerPath"];
            }
            BOOL isDir = NO;
            if (p.length && [fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                dataContainerPath = p;
                dataUUID = p.lastPathComponent;
                [warnings addObject:@"Using manifest containerPath for restore (fallback)" ];
            }
        }
        if (!dataContainerPath && manifestDataUUID.length) {
            for (NSString *base in bases) {
                NSString *p = [base stringByAppendingPathComponent:manifestDataUUID];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                    dataContainerPath = p;
                    dataUUID = manifestDataUUID;
                    [warnings addObject:@"Using manifest UUID for restore (fallback)" ];
                    break;
                }
            }
        }

        if (!dataUUID.length || !dataContainerPath.length) {
            NSString *hint = @"Data container not found. Ensure the app is installed and launched at least once (to create its data container).";
            NSString *lsPath = PXDataContainerPathFromLaunchServices(bundleID) ?: @"";
            NSString *detail = [NSString stringWithFormat:@"%@ (bundleID=%@ lsPath=%@ manifestUUID=%@)", hint, bundleID, lsPath, manifestDataUUID ?: @""];
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:303
                                           userInfo:@{NSLocalizedDescriptionKey: detail}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        PXDebugHeader(debugPre, @"Chosen Container");
        PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"chosenDataContainerPath=%@", dataContainerPath ?: @""]);
        PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"chosenDataUUID=%@", dataUUID ?: @""]);
        PXDebugRun(runner, debugPre, @"du data", [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]);
        PXDebugRun(runner, debugPre, @"ls prefs", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library/Preferences"]) ]);

        // App Groups via entitlements (Option B)
        NSArray<AppGroupContainerInfo *> *groupContainers = @[];
        NSDictionary *options = manifest[@"options"];
        BOOL includeGroups = YES;
        if ([options isKindOfClass:[NSDictionary class]] && [options[@"includeAppGroups"] respondsToSelector:@selector(boolValue)]) {
            includeGroups = [options[@"includeAppGroups"] boolValue];
        }
        if (includeGroups) {
            NSError *entErr = nil;
            AppEntitlementsReader *reader = [[AppEntitlementsReader alloc] init];
            NSArray<NSString *> *groupIDs = [reader applicationGroupsForBundleID:bundleID error:&entErr];
            if (entErr) {
                [warnings addObject:[NSString stringWithFormat:@"Entitlements read failed: %@", entErr.localizedDescription]];
            }
            if (groupIDs.count) {
                AppGroupContainerResolver *resolver = [[AppGroupContainerResolver alloc] init];
                groupContainers = [resolver resolveGroupContainersForGroupIDs:groupIDs];
            }
        }

        // Integrity verify artifacts (best-effort)
        NSDictionary *artByName = nil;
        if ([manifest[@"artifacts"] isKindOfClass:[NSArray class]]) {
            NSMutableDictionary *m = [NSMutableDictionary dictionary];
            for (NSDictionary *a in (NSArray *)manifest[@"artifacts"]) {
                if (![a isKindOfClass:[NSDictionary class]]) continue;
                NSString *name = a[@"name"];
                if ([name isKindOfClass:[NSString class]] && name.length) {
                    m[name] = a;
                }
            }
            artByName = m;
        }

        // Validate data archive before wiping
        NSString *dataArchive = [backupDir stringByAppendingPathComponent:@"data.tar.gz"];
        if (![fm fileExistsAtPath:dataArchive]) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:305
                                           userInfo:@{NSLocalizedDescriptionKey: @"data.tar.gz missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }
        NSDictionary *dataArt = artByName ? artByName[@"data.tar.gz"] : nil;
        if ([dataArt isKindOfClass:[NSDictionary class]]) {
            NSNumber *expectedSize = dataArt[@"size"];
            NSString *expectedHash = dataArt[@"sha256"];
            NSDictionary *attrs = [fm attributesOfItemAtPath:dataArchive error:nil];
            NSNumber *size = attrs[NSFileSize];
            if (expectedSize && size && [expectedSize longLongValue] > 0 && [size longLongValue] != [expectedSize longLongValue]) {
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:314
                                               userInfo:@{NSLocalizedDescriptionKey: @"data.tar.gz size mismatch"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }
            if ([expectedHash isKindOfClass:[NSString class]] && expectedHash.length > 0) {
                NSString *actual = PXHexString(PXFileSHA256(dataArchive));
                if (actual.length && ![actual isEqualToString:expectedHash]) {
                    NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                       code:315
                                                   userInfo:@{NSLocalizedDescriptionKey: @"data.tar.gz sha256 mismatch"}];
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                    return;
                }
            }
        }

        // Two-phase restore for data container: extract to staging first.
        NSString *stagingRoot = [NSString stringWithFormat:@"/tmp/weaponx_restore_%d", getpid()];
        NSString *stagingData = [stagingRoot stringByAppendingPathComponent:@"data"]; 
        [fm removeItemAtPath:stagingRoot error:nil];
        [fm createDirectoryAtPath:stagingData withIntermediateDirectories:YES attributes:nil error:nil];

        CommandResult *stx = [self _tarExtract:tarPath archive:dataArchive toDir:stagingData];
        if (stx.exitCode != 0) {
            NSString *msg = stx.stderrString.length ? stx.stderrString : @"Failed to extract data archive to staging";
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:316
                                           userInfo:@{NSLocalizedDescriptionKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        // Wipe data container contents and clone from staging via tar pipe.
        [self _wipeDirectoryContents:dataContainerPath];
        NSString *cloneCmd = [NSString stringWithFormat:@"%@ --xattrs --acls -cf - -C %@ . | %@ --xattrs --acls -xf - -C %@",
                              PXShellQuote(tarPath),
                              PXShellQuote(stagingData),
                              PXShellQuote(tarPath),
                              PXShellQuote(dataContainerPath)];
        CommandResult *cloneRes = [runner runAndCapture:cloneCmd];
        if (cloneRes.exitCode != 0) {
            NSString *fallbackCmd = [NSString stringWithFormat:@"cp -a %@/. %@/ 2>/dev/null",
                                     PXShellQuote(stagingData),
                                     PXShellQuote(dataContainerPath)];
            CommandResult *cpRes = [runner runAndCapture:fallbackCmd];
            if (cpRes.exitCode != 0) {
                NSString *msg = cloneRes.stderrString.length ? cloneRes.stderrString : @"tar pipe clone failed";
                if (cpRes.stderrString.length) {
                    msg = [msg stringByAppendingFormat:@"; cp: %@", cpRes.stderrString];
                }
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:317
                                               userInfo:@{NSLocalizedDescriptionKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }
        }

        [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]];

        // Cleanup staging best-effort
        [fm removeItemAtPath:stagingRoot error:nil];

        // Data container restored.

        // Restore profile redirected appdata (if present)
        NSDictionary *profileAppData = manifest[@"profileAppData"];
        BOOL includeProfileAppData = NO;
        if ([profileAppData isKindOfClass:[NSDictionary class]] && [profileAppData[@"included"] respondsToSelector:@selector(boolValue)]) {
            includeProfileAppData = [profileAppData[@"included"] boolValue];
        }
        if (includeProfileAppData) {
            NSString *profileAppDataPath = [self _profileAppDataPathForBundleID:bundleID];
            NSString *archivePath = [backupDir stringByAppendingPathComponent:@"profile_appdata.tar.gz"];
            if (profileAppDataPath.length && [fm fileExistsAtPath:archivePath]) {
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:profileAppDataPath isDirectory:&isDir] && isDir) {
                    [self _wipeDirectoryContents:profileAppDataPath];
                    CommandResult *r = [self _tarExtract:tarPath archive:archivePath toDir:profileAppDataPath];
                    if (r.exitCode != 0) {
                        NSString *msg = r.stderrString.length ? r.stderrString : @"Failed to restore profile appdata";
                        NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                           code:307
                                                       userInfo:@{NSLocalizedDescriptionKey: msg}];
                        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                        return;
                    }
                    [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(profileAppDataPath)]];
                } else {
                    NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                       code:308
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Profile appdata directory missing"}];
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                    return;
                }
            } else {
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:309
                                               userInfo:@{NSLocalizedDescriptionKey: @"Profile appdata archive missing"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }
        }

        // Restore global Safari library (if present)
        NSDictionary *globalSafari = manifest[@"globalSafari"];
        BOOL includeGlobalSafari = NO;
        if ([globalSafari isKindOfClass:[NSDictionary class]] && [globalSafari[@"included"] respondsToSelector:@selector(boolValue)]) {
            includeGlobalSafari = [globalSafari[@"included"] boolValue];
        }
        if (includeGlobalSafari) {
            NSString *globalSafariPath = [self _globalSafariLibraryPath];
            NSString *archivePath = [backupDir stringByAppendingPathComponent:@"global_safari.tar.gz"];
            if (globalSafariPath.length && [fm fileExistsAtPath:archivePath]) {
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:globalSafariPath isDirectory:&isDir] && isDir) {
                    [self _wipeDirectoryContents:globalSafariPath];
                    CommandResult *r = [self _tarExtract:tarPath archive:archivePath toDir:globalSafariPath];
                    if (r.exitCode != 0) {
                        NSString *msg = r.stderrString.length ? r.stderrString : @"Failed to restore global Safari library";
                        NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                           code:311
                                                       userInfo:@{NSLocalizedDescriptionKey: msg}];
                        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                        return;
                    }
                    [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(globalSafariPath)]];
                } else {
                    NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                       code:312
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Global Safari directory missing"}];
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                    return;
                }
            } else {
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:313
                                               userInfo:@{NSLocalizedDescriptionKey: @"Global Safari archive missing"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }
        }

        // Wipe and restore each group
        for (AppGroupContainerInfo *info in groupContainers) {
            // Debug: group state before wipe
            PXDebugHeader(debugPre, [NSString stringWithFormat:@"Group Restore: %@", info.groupID ?: @""]);
            PXDebugAppendLine(debugPre, [NSString stringWithFormat:@"groupPath=%@", info.path ?: @""]);
            PXDebugRun(runner, debugPre, @"ls group (before)", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(info.path)]);
            [self _wipeDirectoryContents:info.path];
            PXDebugRun(runner, debugPre, @"ls group (after wipe)", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(info.path)]);

            NSString *archiveName = [NSString stringWithFormat:@"%@.tar.gz", PXSanitizeFilenameComponent(info.groupID)];
            NSString *archivePath = [[backupDir stringByAppendingPathComponent:@"groups"] stringByAppendingPathComponent:archiveName];
            if (![fm fileExistsAtPath:archivePath]) {
                [warnings addObject:[NSString stringWithFormat:@"Missing group archive for %@", info.groupID]];
                continue;
            }

            CommandResult *r = [self _tarExtract:tarPath archive:archivePath toDir:info.path];
            if (r.exitCode != 0) {
                NSString *msg = r.stderrString.length ? r.stderrString : [NSString stringWithFormat:@"Failed to extract group %@", info.groupID];
                NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                                   code:310
                                               userInfo:@{NSLocalizedDescriptionKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
                return;
            }

            [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(info.path)]];
            PXDebugRun(runner, debugPost, @"ls group (after extract)", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote(info.path)]);
        }

        // Preferences restore
        BOOL includePrefs = YES;
        NSDictionary *prefs = manifest[@"preferences"];
        if ([prefs isKindOfClass:[NSDictionary class]] && [prefs[@"included"] respondsToSelector:@selector(boolValue)]) {
            includePrefs = [prefs[@"included"] boolValue];
        }
        if (includePrefs) {
            NSString *prefBackup = [[backupDir stringByAppendingPathComponent:@"preferences"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
            NSString *prefDest = [self _preferencesPlistPathForBundleID:bundleID];
            if ([fm fileExistsAtPath:prefBackup]) {
                [runner run:[NSString stringWithFormat:@"cp -f %@ %@ 2>/dev/null || true", PXShellQuote(prefBackup), PXShellQuote(prefDest)]];
                [runner run:[NSString stringWithFormat:@"chown mobile:mobile %@ 2>/dev/null || true", PXShellQuote(prefDest)]];
                [runner run:[NSString stringWithFormat:@"chmod 644 %@ 2>/dev/null || true", PXShellQuote(prefDest)]];
                [runner run:@"killall -TERM cfprefsd 2>/dev/null || true"]; 
            } else {
                [warnings addObject:@"Preferences archive missing; skipping"];
            }
        }

        // Keychain restore (warning-only on failure)
        NSDictionary *keychainInfo = manifest[@"keychain"];
        BOOL includeKeychain = NO;
        if ([keychainInfo isKindOfClass:[NSDictionary class]] && [keychainInfo[@"included"] respondsToSelector:@selector(boolValue)]) {
            includeKeychain = [keychainInfo[@"included"] boolValue];
        }
        if (includeKeychain) {
            NSString *keychainBackupPath = [backupDir stringByAppendingPathComponent:@"keychain.plist"];
            NSArray<NSString *> *groups = @[];
            if ([keychainInfo isKindOfClass:[NSDictionary class]] && [keychainInfo[@"groupsSelected"] isKindOfClass:[NSArray class]]) {
                groups = keychainInfo[@"groupsSelected"];
            }
            BOOL ok = [self _restoreKeychainForBundleID:bundleID
                                                groups:groups
                                              fromFile:keychainBackupPath
                                             overwrite:YES
                                              warnings:warnings];
            if (!ok) {
                [warnings addObject:@"Keychain restore failed (continuing)" ];
            }

            // Debug keychain list after restore
            PXDebugHeader(debugKeychain, @"Keychain After Restore");
            PXDebugAppendLine(debugKeychain, [NSString stringWithFormat:@"groups=%@", groups ?: @[]]);
            NSString *scriptPath = [runner firstExistingPath:@[@"/Library/WeaponX/keychain_backup.sh",
                                                              @"/var/jb/Library/WeaponX/keychain_backup.sh",
                                                              @"/private/var/jb/Library/WeaponX/keychain_backup.sh"]];
            if (scriptPath.length && groups.count) {
                NSString *csv = [groups componentsJoinedByString:@","];
                PXDebugRun(runner, debugKeychain, @"list", [NSString stringWithFormat:@"%@ list %@ --groups %@", PXShellQuote(scriptPath), PXShellQuote(bundleID), PXShellQuote(csv)]);
            }
        }

        // Debug snapshot: after restore
        {
            PXDebugHeader(debugPost, @"Restore Done");
            NSDictionary *rp = PXResolvePathsForBundleID(bundleID);
            NSString *lsDataPath = rp[@"lsDataContainerPath"];
            PXDebugAppendLine(debugPost, [NSString stringWithFormat:@"lsDataContainerPath=%@", lsDataPath ?: @""]);
            PXDebugAppendLine(debugPost, [NSString stringWithFormat:@"chosenDataContainerPath=%@", dataContainerPath ?: @""]);
            PXDebugRun(runner, debugPost, @"du data", [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]);
            PXDebugRun(runner, debugPost, @"ls prefs", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([dataContainerPath stringByAppendingPathComponent:@"Library/Preferences"]) ]);
            NSString *prefDest = [self _preferencesPlistPathForBundleID:bundleID];
            PXDebugRun(runner, debugPost, @"ls global prefs", [NSString stringWithFormat:@"ls -lh %@ 2>/dev/null || true", PXShellQuote(prefDest)]);

            if ([lsDataPath isKindOfClass:[NSString class]] && lsDataPath.length && ![lsDataPath isEqualToString:dataContainerPath]) {
                PXDebugHeader(debugPost, @"WARNING: Active Container Differs");
                PXDebugRun(runner, debugPost, @"du lsDataContainerPath", [NSString stringWithFormat:@"du -sk %@ 2>/dev/null || true", PXShellQuote(lsDataPath)]);
                PXDebugRun(runner, debugPost, @"ls lsDataContainerPath/Library/Preferences", [NSString stringWithFormat:@"ls -la %@ 2>/dev/null || true", PXShellQuote([lsDataPath stringByAppendingPathComponent:@"Library/Preferences"]) ]);
            }
        }

        PXRestoreResult *out = [[PXRestoreResult alloc] init];
        out.warnings = warnings;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(out, nil);
            }
        });
    });
}

@end
