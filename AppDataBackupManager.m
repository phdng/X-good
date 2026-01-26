#import "AppDataBackupManager.h"

#import <UIKit/UIKit.h>

#import "AppDataCleaner.h"
#import "FreezeManager.h"

#import "AppEntitlementsReader.h"
#import "AppGroupContainerResolver.h"
#import "CommandRunner.h"

static NSString * const PXBackupErrorDomain = @"com.hydra.projectx.backup";

@implementation PXBackupResult
@end

@implementation PXRestoreResult
@end

@implementation AppDataBackupManager

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

- (NSString *)_preferencesPlistPathForBundleID:(NSString *)bundleID {
    NSString *prefsDir = [self _preferencesDirectory];
    return [prefsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
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

        AppDataCleaner *cleaner = [AppDataCleaner sharedManager];
        NSString *dataUUID = [cleaner findDataContainerUUIDForBundleID:bundleID];
        if (!dataUUID.length) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:102
                                           userInfo:@{NSLocalizedDescriptionKey: @"Data container not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSString *dataContainerPath = nil;
        for (NSString *base in @[@"/var/mobile/Containers/Data/Application", @"/containers/Data/Application"]) {
            NSString *p = [base stringByAppendingPathComponent:dataUUID];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                dataContainerPath = p;
                break;
            }
        }
        if (!dataContainerPath) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:103
                                           userInfo:@{NSLocalizedDescriptionKey: @"Data container path missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSString *timestamp = [self _timestampString];
        NSString *backupDir = [[[self _backupRoot] stringByAppendingPathComponent:bundleID] stringByAppendingPathComponent:timestamp];
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

        NSString *dataArchivePath = [backupDir stringByAppendingPathComponent:@"data.tar.gz"];
        NSString *dataTarCmd = [NSString stringWithFormat:@"%@ -czf %@ --exclude '.com.apple*' -C %@ .",
                                PXShellQuote(tarPath),
                                PXShellQuote(dataArchivePath),
                                PXShellQuote(dataContainerPath)];
        CommandResult *tarRes = [runner runAndCapture:dataTarCmd];
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

        for (AppGroupContainerInfo *info in groupContainers) {
            NSString *archiveName = [NSString stringWithFormat:@"%@.tar.gz", PXSanitizeFilenameComponent(info.groupID)];
            NSString *archivePath = [groupsDir stringByAppendingPathComponent:archiveName];

            NSString *cmd = [NSString stringWithFormat:@"%@ -czf %@ --exclude '.com.apple*' -C %@ .",
                             PXShellQuote(tarPath),
                             PXShellQuote(archivePath),
                             PXShellQuote(info.path)];
            CommandResult *r = [runner runAndCapture:cmd];
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

        UIDevice *device = [UIDevice currentDevice];
        NSString *iosVersion = device.systemVersion ?: @"";
        NSString *profileId = [self _activeProfileId] ?: @"";

        NSDictionary *manifest = @{
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
            @"options": @{
                @"includeAppGroups": @((options & PXBackupOptionIncludeAppGroups) != 0),
                @"includePreferences": @(prefsIncluded)
            }
        };

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
        [[FreezeManager sharedManager] killApplication:bundleID];

        AppDataCleaner *cleaner = [AppDataCleaner sharedManager];
        NSString *dataUUID = [cleaner findDataContainerUUIDForBundleID:bundleID];
        if (!dataUUID.length) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:303
                                           userInfo:@{NSLocalizedDescriptionKey: @"Data container not found"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSString *dataContainerPath = nil;
        for (NSString *base in @[@"/var/mobile/Containers/Data/Application", @"/containers/Data/Application"]) {
            NSString *p = [base stringByAppendingPathComponent:dataUUID];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                dataContainerPath = p;
                break;
            }
        }
        if (!dataContainerPath) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:304
                                           userInfo:@{NSLocalizedDescriptionKey: @"Data container path missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

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

        // Wipe data container
        [cleaner completelyWipeContainer:dataContainerPath];

        // Extract data archive
        NSString *dataArchive = [backupDir stringByAppendingPathComponent:@"data.tar.gz"];
        if (![fm fileExistsAtPath:dataArchive]) {
            NSError *err = [NSError errorWithDomain:PXBackupErrorDomain
                                               code:305
                                           userInfo:@{NSLocalizedDescriptionKey: @"data.tar.gz missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }
        NSString *dataExtractCmd = [NSString stringWithFormat:@"%@ -xzf %@ -C %@",
                                    PXShellQuote(tarPath),
                                    PXShellQuote(dataArchive),
                                    PXShellQuote(dataContainerPath)];
        CommandResult *dx = [runner runAndCapture:dataExtractCmd];
        if (dx.exitCode != 0) {
            [warnings addObject:@"Failed to extract data archive"];
        }

        [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(dataContainerPath)]];

        // Wipe and restore each group
        for (AppGroupContainerInfo *info in groupContainers) {
            [cleaner completelyWipeContainer:info.path];

            NSString *archiveName = [NSString stringWithFormat:@"%@.tar.gz", PXSanitizeFilenameComponent(info.groupID)];
            NSString *archivePath = [[backupDir stringByAppendingPathComponent:@"groups"] stringByAppendingPathComponent:archiveName];
            if (![fm fileExistsAtPath:archivePath]) {
                [warnings addObject:[NSString stringWithFormat:@"Missing group archive for %@", info.groupID]];
                continue;
            }

            NSString *cmd = [NSString stringWithFormat:@"%@ -xzf %@ -C %@",
                             PXShellQuote(tarPath),
                             PXShellQuote(archivePath),
                             PXShellQuote(info.path)];
            CommandResult *r = [runner runAndCapture:cmd];
            if (r.exitCode != 0) {
                [warnings addObject:[NSString stringWithFormat:@"Failed to extract group %@", info.groupID]];
            }

            [runner run:[NSString stringWithFormat:@"chown -R mobile:mobile %@ 2>/dev/null || true", PXShellQuote(info.path)]];
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
