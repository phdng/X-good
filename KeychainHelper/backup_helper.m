/**
 * backup_helper - iOS Keychain Backup/Restore CLI Tool
 *
 * Usage:
 *   backup_helper --action backup --target <bundleID> --file <path>
 *   backup_helper --action restore --file <path> [--overwrite]
 *   backup_helper --action wipe --target <bundleID>
 *   backup_helper --action list --target <bundleID>
 *
 * This tool must be resigned with the target app's keychain-access-groups
 * entitlements before running. Use the keychain_backup.sh wrapper script.
 *
 * Exit codes:
 *   0 - Success
 *   1 - Invalid arguments
 *   2 - Operation failed
 *   3 - Access denied (missing entitlements)
 */

#import <Foundation/Foundation.h>
#import "KeychainBackupHelper.h"

typedef NS_ENUM(NSInteger, PXHelperAction) {
    PXHelperActionUnknown = 0,
    PXHelperActionBackup,
    PXHelperActionRestore,
    PXHelperActionWipe,
    PXHelperActionList,
};

static void printUsage(const char *progname) {
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  %s --action backup --file <path> [--groups <group1,group2,...>]\n", progname);
    fprintf(stderr, "  %s --action restore --file <path> [--overwrite]\n", progname);
    fprintf(stderr, "  %s --action wipe --groups <group1,group2,...>\n", progname);
    fprintf(stderr, "  %s --action list --groups <group1,group2,...>\n", progname);
    fprintf(stderr, "\nOptions:\n");
    fprintf(stderr, "  --action <action>   Action to perform: backup, restore, wipe, list\n");
    fprintf(stderr, "  --file <path>       Path to backup/restore file (plist format)\n");
    fprintf(stderr, "  --groups <groups>   Comma-separated list of keychain access groups\n");
    fprintf(stderr, "  --overwrite         For restore: delete existing items first\n");
    fprintf(stderr, "  --verbose           Print detailed progress information\n");
    fprintf(stderr, "  --help              Show this help message\n");
}

static PXHelperAction parseAction(NSString *actionStr) {
    if ([actionStr isEqualToString:@"backup"]) return PXHelperActionBackup;
    if ([actionStr isEqualToString:@"restore"]) return PXHelperActionRestore;
    if ([actionStr isEqualToString:@"wipe"]) return PXHelperActionWipe;
    if ([actionStr isEqualToString:@"list"]) return PXHelperActionList;
    return PXHelperActionUnknown;
}

static NSArray<NSString *> *parseGroups(NSString *groupsStr) {
    if (!groupsStr.length) return @[];
    NSArray *parts = [groupsStr componentsSeparatedByString:@","];
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) {
            [groups addObject:trimmed];
        }
    }
    return groups;
}

static void logVerbose(BOOL verbose, NSString *format, ...) {
    if (!verbose) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stdout, "[INFO] %s\n", [message UTF8String]);
}

static void logError(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stderr, "[ERROR] %s\n", [message UTF8String]);
}

static void logSuccess(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stdout, "[OK] %s\n", [message UTF8String]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Parse arguments.
        NSMutableDictionary *args = [NSMutableDictionary dictionary];
        
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            
            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printUsage(argv[0]);
                return 0;
            } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                args[@"verbose"] = @YES;
            } else if ([arg isEqualToString:@"--overwrite"]) {
                args[@"overwrite"] = @YES;
            } else if ([arg hasPrefix:@"--"] && i + 1 < argc) {
                NSString *key = [arg substringFromIndex:2];
                NSString *value = @(argv[++i]);
                args[key] = value;
            }
        }
        
        BOOL verbose = [args[@"verbose"] boolValue];
        
        // Validate action.
        NSString *actionStr = args[@"action"];
        if (!actionStr.length) {
            logError(@"Missing required --action argument");
            printUsage(argv[0]);
            return 1;
        }
        
        PXHelperAction action = parseAction(actionStr);
        if (action == PXHelperActionUnknown) {
            logError(@"Unknown action: %@", actionStr);
            printUsage(argv[0]);
            return 1;
        }
        
        NSString *filePath = args[@"file"];
        NSArray<NSString *> *groups = parseGroups(args[@"groups"]);
        BOOL overwrite = [args[@"overwrite"] boolValue];
        
        logVerbose(verbose, @"Action: %@", actionStr);
        logVerbose(verbose, @"File: %@", filePath ?: @"(none)");
        logVerbose(verbose, @"Groups: %@", [groups componentsJoinedByString:@", "] ?: @"(none)");
        
        NSError *error = nil;
        PXKeychainBackupResult *result = nil;
        
        switch (action) {
            case PXHelperActionBackup: {
                if (!filePath.length) {
                    logError(@"--file is required for backup");
                    return 1;
                }
                if (!groups.count) {
                    logError(@"--groups is required for backup");
                    return 1;
                }
                
                logVerbose(verbose, @"Starting keychain backup...");
                result = [KeychainBackupHelper backupKeychainToFile:filePath
                                                       accessGroups:groups
                                                        itemClasses:PXKeychainItemClassAll
                                                              error:&error];
                
                if (!result) {
                    logError(@"Backup failed: %@", error.localizedDescription);
                    return 2;
                }
                
                logSuccess(@"Backup complete: %lu items processed, %lu succeeded, %lu failed",
                          (unsigned long)result.itemsProcessed,
                          (unsigned long)result.itemsSucceeded,
                          (unsigned long)result.itemsFailed);
                
                for (NSString *warning in result.warnings) {
                    fprintf(stderr, "[WARN] %s\n", [warning UTF8String]);
                }
                break;
            }
                
            case PXHelperActionRestore: {
                if (!filePath.length) {
                    logError(@"--file is required for restore");
                    return 1;
                }
                
                logVerbose(verbose, @"Starting keychain restore (overwrite: %@)...",
                          overwrite ? @"YES" : @"NO");
                result = [KeychainBackupHelper restoreKeychainFromFile:filePath
                                                             overwrite:overwrite
                                                                 error:&error];
                
                if (!result) {
                    logError(@"Restore failed: %@", error.localizedDescription);
                    return 2;
                }
                
                logSuccess(@"Restore complete: %lu items processed, %lu succeeded, %lu failed",
                          (unsigned long)result.itemsProcessed,
                          (unsigned long)result.itemsSucceeded,
                          (unsigned long)result.itemsFailed);
                
                for (NSString *warning in result.warnings) {
                    fprintf(stderr, "[WARN] %s\n", [warning UTF8String]);
                }
                for (NSString *err in result.errors) {
                    fprintf(stderr, "[ERR] %s\n", [err UTF8String]);
                }
                break;
            }
                
            case PXHelperActionWipe: {
                if (!groups.count) {
                    logError(@"--groups is required for wipe");
                    return 1;
                }
                
                logVerbose(verbose, @"Starting keychain wipe...");
                result = [KeychainBackupHelper wipeKeychainForAccessGroups:groups
                                                               itemClasses:PXKeychainItemClassAll
                                                                     error:&error];
                
                if (!result) {
                    logError(@"Wipe failed: %@", error.localizedDescription);
                    return 2;
                }
                
                logSuccess(@"Wipe complete: %lu items deleted",
                          (unsigned long)result.itemsSucceeded);
                
                for (NSString *warning in result.warnings) {
                    fprintf(stderr, "[WARN] %s\n", [warning UTF8String]);
                }
                break;
            }
                
            case PXHelperActionList: {
                if (!groups.count) {
                    logError(@"--groups is required for list");
                    return 1;
                }

                logVerbose(verbose, @"Diagnosing keychain access...");
                if (verbose) {
                    NSArray<NSDictionary *> *diag = [KeychainBackupHelper diagnoseKeychainAccessForGroups:groups
                                                                                           itemClasses:PXKeychainItemClassAll];
                    for (NSDictionary *d in diag) {
                        fprintf(stdout, "[DIAG] group=%s class=%s status=%d (%s) count=%lu\n",
                                [[d[@"accessGroup"] description] UTF8String] ?: "",
                                [[d[@"class"] description] UTF8String] ?: "",
                                [d[@"status"] intValue],
                                [[d[@"statusDesc"] description] UTF8String] ?: "",
                                (unsigned long)[d[@"count"] unsignedIntegerValue]);
                    }
                }

                logVerbose(verbose, @"Listing keychain items...");
                NSArray<NSDictionary *> *items = [KeychainBackupHelper listKeychainItemsForAccessGroups:groups
                                                                                             itemClasses:PXKeychainItemClassAll];
                
                fprintf(stdout, "Found %lu keychain items:\n", (unsigned long)items.count);
                for (NSDictionary *item in items) {
                    fprintf(stdout, "  - [%s] %s/%s\n",
                           [item[@"class"] UTF8String] ?: "?",
                           [item[@"service"] UTF8String] ?: "",
                           [item[@"account"] UTF8String] ?: "");
                }
                break;
            }
                
            default:
                break;
        }
        
        return 0;
    }
}
