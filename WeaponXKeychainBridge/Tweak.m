#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <signal.h>

static NSString *WXSafeBundle(NSString *bundleID) {
    if (!bundleID.length) return @"unknown";
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *out = [NSMutableString stringWithCapacity:bundleID.length];
    for (NSUInteger i = 0; i < bundleID.length; i++) {
        unichar c = [bundleID characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [out appendFormat:@"%C", c];
        } else {
            [out appendString:@"_"];
        }
    }
    return out;
}

static BOOL WXIsTmpPath(NSString *path) {
    return ([path isKindOfClass:[NSString class]] && [path hasPrefix:@"/tmp/"]);
}

static NSString *WXSecError(OSStatus status) {
    CFStringRef s = SecCopyErrorMessageString(status, NULL);
    if (s) {
        return (__bridge_transfer NSString *)s;
    }
    return [NSString stringWithFormat:@"OSStatus %d", (int)status];
}

static id WXEncodeValue(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSData class]]) {
        return @{
            @"_type": @"data",
            @"_base64": [(NSData *)v base64EncodedStringWithOptions:0]
        };
    }
    if ([v isKindOfClass:[NSDate class]]) {
        return @{
            @"_type": @"date",
            @"_timestamp": @([(NSDate *)v timeIntervalSince1970])
        };
    }
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSArray class]]) {
        return v;
    }
    return [[v description] copy];
}

static id WXDecodeValue(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)v;
        NSString *type = d[@"_type"];
        if ([type isEqualToString:@"data"]) {
            NSString *b64 = d[@"_base64"];
            if ([b64 isKindOfClass:[NSString class]]) {
                return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
            }
        } else if ([type isEqualToString:@"date"]) {
            NSNumber *ts = d[@"_timestamp"];
            if ([ts isKindOfClass:[NSNumber class]]) {
                return [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]];
            }
        }
    }
    return v;
}

static BOOL WXWritePlistAtomic(id plist, NSString *path) {
    if (!WXIsTmpPath(path)) return NO;
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                             format:NSPropertyListXMLFormat_v1_0
                                                            options:0
                                                              error:&err];
    if (!data.length || err) return NO;
    NSString *tmp = [path stringByAppendingString:@".tmp"]; 
    if (![data writeToFile:tmp atomically:YES]) return NO;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:path error:nil];
}

static void WXAppendLog(NSString *logPath, NSString *line) {
    if (!WXIsTmpPath(logPath) || !line.length) return;
    NSString *out = [line stringByAppendingString:@"\n"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [out writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static CFTypeRef WXSecClassFromName(NSString *name) {
    if ([name isEqualToString:@"GenericPassword"]) return kSecClassGenericPassword;
    if ([name isEqualToString:@"InternetPassword"]) return kSecClassInternetPassword;
    return NULL;
}

static NSArray<NSDictionary *> *WXExportItems(NSArray<NSString *> *groups, NSString *logPath, NSError **outErr) {
    NSMutableArray<NSDictionary *> *itemsOut = [NSMutableArray array];
    NSArray<NSString *> *classNames = @[ @"GenericPassword", @"InternetPassword" ];

    for (NSString *group in groups) {
        if (![group isKindOfClass:[NSString class]] || !group.length) continue;
        for (NSString *className in classNames) {
            CFTypeRef secClass = WXSecClassFromName(className);
            if (!secClass) continue;

            NSMutableDictionary *query = [@{
                (__bridge id)kSecClass: (__bridge id)secClass,
                (__bridge id)kSecAttrAccessGroup: group,
                (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                (__bridge id)kSecReturnAttributes: @YES,
                (__bridge id)kSecReturnData: @YES,
                (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
            } mutableCopy];
            if (@available(iOS 9.0, *)) {
                query[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
            }

            CFTypeRef cfRes = NULL;
            OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &cfRes);
            if (st == errSecItemNotFound) {
                continue;
            }
            if (st != errSecSuccess) {
                WXAppendLog(logPath, [NSString stringWithFormat:@"export group=%@ class=%@ error=%@", group, className, WXSecError(st)]);
                if (outErr) {
                    *outErr = [NSError errorWithDomain:@"com.hydra.weaponx.keychainbridge" code:(NSInteger)st userInfo:@{NSLocalizedDescriptionKey: WXSecError(st)}];
                }
                continue;
            }

            id res = (__bridge_transfer id)cfRes;
            NSArray *arr = nil;
            if ([res isKindOfClass:[NSArray class]]) {
                arr = (NSArray *)res;
            } else if ([res isKindOfClass:[NSDictionary class]]) {
                arr = @[res];
            }
            for (NSDictionary *item in arr) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSMutableDictionary *exportItem = [NSMutableDictionary dictionary];
                exportItem[@"_class"] = className;
                for (id k in item) {
                    if (![k isKindOfClass:[NSString class]]) continue;
                    id v = item[k];
                    id ev = WXEncodeValue(v);
                    if (ev) {
                        exportItem[(NSString *)k] = ev;
                    }
                }
                [itemsOut addObject:exportItem];
            }
        }
    }

    return itemsOut;
}

static NSSet<NSString *> *WXExcludedRestoreKeys(void) {
    static NSSet *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[
            (__bridge NSString *)kSecAttrAccessControl,
            (__bridge NSString *)kSecAttrCreationDate,
            (__bridge NSString *)kSecAttrModificationDate,
            (__bridge NSString *)kSecAttrPersistentReference,
            (__bridge NSString *)kSecValuePersistentRef,
            @"tomb",
            @"sha1",
            @"UUID",
        ]];
    });
    return s;
}

static void WXWipe(NSArray<NSString *> *groups, NSString *logPath) {
    NSArray<NSString *> *classNames = @[ @"GenericPassword", @"InternetPassword" ];
    for (NSString *group in groups) {
        if (![group isKindOfClass:[NSString class]] || !group.length) continue;
        for (NSString *className in classNames) {
            CFTypeRef secClass = WXSecClassFromName(className);
            if (!secClass) continue;
            NSMutableDictionary *q = [@{
                (__bridge id)kSecClass: (__bridge id)secClass,
                (__bridge id)kSecAttrAccessGroup: group,
                (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
            } mutableCopy];
            if (@available(iOS 9.0, *)) {
                q[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
            }
            OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
            if (st != errSecSuccess && st != errSecItemNotFound) {
                WXAppendLog(logPath, [NSString stringWithFormat:@"wipe group=%@ class=%@ error=%@", group, className, WXSecError(st)]);
            }
        }
    }
}

static NSDictionary *WXRestoreFromImport(NSDictionary *importPlist, NSArray<NSString *> *allowedGroups, BOOL overwrite, NSString *logPath) {
    NSArray *items = [importPlist isKindOfClass:[NSDictionary class]] ? importPlist[@"items"] : nil;
    if (![items isKindOfClass:[NSArray class]]) {
        return @{ @"ok": @NO, @"error": @"invalid import format (missing items)" };
    }

    if (overwrite) {
        WXWipe(allowedGroups, logPath);
    }

    NSSet *excluded = WXExcludedRestoreKeys();
    NSUInteger processed = 0, succeeded = 0, failed = 0;
    NSMutableArray *errors = [NSMutableArray array];

    NSSet *allowedSet = [NSSet setWithArray:allowedGroups ?: @[]];

    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        processed++;

        NSString *className = item[@"_class"];
        CFTypeRef secClass = WXSecClassFromName(className);
        if (!secClass) {
            failed++;
            [errors addObject:@"missing/invalid _class"]; 
            continue;
        }

        NSMutableDictionary *add = [NSMutableDictionary dictionary];
        add[(__bridge id)kSecClass] = (__bridge id)secClass;

        // Decode fields
        for (NSString *k in item) {
            if (![k isKindOfClass:[NSString class]]) continue;
            if ([k hasPrefix:@"_"]) continue;
            if ([excluded containsObject:k]) continue;
            id rv = WXDecodeValue(item[k]);
            if (rv) add[k] = rv;
        }

        NSString *grp = add[(__bridge NSString *)kSecAttrAccessGroup];
        if (grp.length && ![allowedSet containsObject:grp]) {
            failed++;
            [errors addObject:[NSString stringWithFormat:@"item access group not allowed: %@", grp]];
            continue;
        }

        if (@available(iOS 9.0, *)) {
            add[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
        }

        OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        if (st == errSecSuccess) {
            succeeded++;
            continue;
        }
        if (st == errSecDuplicateItem) {
            // Delete then add (simple + reliable).
            NSMutableDictionary *del = [add mutableCopy];
            [del removeObjectForKey:(__bridge id)kSecValueData];
            [del removeObjectForKey:(__bridge id)kSecReturnData];
            [del removeObjectForKey:(__bridge id)kSecReturnAttributes];
            [del removeObjectForKey:(__bridge id)kSecMatchLimit];
            SecItemDelete((__bridge CFDictionaryRef)del);
            OSStatus st2 = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
            if (st2 == errSecSuccess) {
                succeeded++;
                continue;
            }
            st = st2;
        }

        failed++;
        NSString *acct = add[(__bridge NSString *)kSecAttrAccount] ?: @"";
        NSString *svc = add[(__bridge NSString *)kSecAttrService] ?: @"";
        NSString *e = [NSString stringWithFormat:@"add failed class=%@ acct=%@ svc=%@: %@", className ?: @"", acct, svc, WXSecError(st)];
        [errors addObject:e];
        WXAppendLog(logPath, e);
    }

    return @{ @"ok": @YES,
              @"processed": @(processed),
              @"succeeded": @(succeeded),
              @"failed": @(failed),
              @"errors": errors };
}

static void WXProcessRequestForCurrentApp(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (!bundleID.length) return;
        NSString *safe = WXSafeBundle(bundleID);
        NSString *reqPath = [NSString stringWithFormat:@"/tmp/weaponx_keychain_request_%@.plist", safe];

        NSDictionary *req = [NSDictionary dictionaryWithContentsOfFile:reqPath];
        if (![req isKindOfClass:[NSDictionary class]]) return;

        NSString *action = req[@"action"];
        NSString *nonce = req[@"nonce"];
        NSString *reqBundle = req[@"bundleID"];
        NSArray *groups = req[@"groups"];
        NSString *respPath = req[@"respPath"];
        NSString *logPath = req[@"logPath"];

        if (![reqBundle isKindOfClass:[NSString class]] || ![reqBundle isEqualToString:bundleID]) return;
        if (![nonce isKindOfClass:[NSString class]] || !nonce.length) return;
        if (![groups isKindOfClass:[NSArray class]]) groups = @[];
        if (![action isKindOfClass:[NSString class]]) action = @"";

        if (!WXIsTmpPath(respPath)) respPath = [NSString stringWithFormat:@"/tmp/weaponx_keychain_response_%@.plist", safe];
        if (!WXIsTmpPath(logPath)) logPath = [NSString stringWithFormat:@"/tmp/weaponx_keychain_bridge_%@.log", safe];

        // Hard guard: only allow /tmp destinations.
        if (!WXIsTmpPath(respPath) || !WXIsTmpPath(logPath)) {
            return;
        }

        WXAppendLog(logPath, [NSString stringWithFormat:@"req action=%@ bundle=%@ nonce=%@", action, bundleID, nonce]);

        NSMutableDictionary *resp = [NSMutableDictionary dictionary];
        resp[@"bundleID"] = bundleID;
        resp[@"action"] = action;
        resp[@"nonce"] = nonce;
        resp[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);

        BOOL ok = NO;

        if ([action isEqualToString:@"backup"]) {
            NSString *outPath = req[@"outPath"];
            if (!WXIsTmpPath(outPath)) outPath = [NSString stringWithFormat:@"/tmp/weaponx_keychain_export_%@.plist", safe];
            if (!WXIsTmpPath(outPath)) {
                resp[@"ok"] = @NO;
                resp[@"error"] = @"outPath must be under /tmp";
            } else {
                NSError *exportErr = nil;
                NSArray<NSDictionary *> *items = WXExportItems((NSArray *)groups, logPath, &exportErr);
                NSDictionary *exportPlist = @{
                    @"version": @1,
                    @"bundleID": bundleID,
                    @"created": @([[NSDate date] timeIntervalSince1970]),
                    @"accessGroups": groups ?: @[],
                    @"items": items ?: @[],
                };
                BOOL wrote = WXWritePlistAtomic(exportPlist, outPath);
                ok = (wrote && !exportErr);
                resp[@"ok"] = @(ok);
                resp[@"items"] = @([(NSArray *)items count]);
                resp[@"outPath"] = outPath;
                if (exportErr) resp[@"error"] = exportErr.localizedDescription ?: @"";
                WXAppendLog(logPath, [NSString stringWithFormat:@"backup items=%lu wrote=%d out=%@", (unsigned long)[(NSArray *)items count], wrote, outPath]);
            }
        } else if ([action isEqualToString:@"restore"]) {
            NSString *inPath = req[@"inPath"];
            NSNumber *overwriteNum = req[@"overwrite"];
            BOOL overwrite = [overwriteNum respondsToSelector:@selector(boolValue)] ? [overwriteNum boolValue] : YES;
            if (!WXIsTmpPath(inPath)) {
                resp[@"ok"] = @NO;
                resp[@"error"] = @"inPath must be under /tmp";
            } else {
                NSDictionary *importPlist = [NSDictionary dictionaryWithContentsOfFile:inPath];
                NSDictionary *r = WXRestoreFromImport(importPlist, (NSArray *)groups, overwrite, logPath);
                [resp addEntriesFromDictionary:r];
                ok = [r[@"ok"] respondsToSelector:@selector(boolValue)] ? [r[@"ok"] boolValue] : NO;
                WXAppendLog(logPath, [NSString stringWithFormat:@"restore ok=%d", ok]);
            }
        } else {
            resp[@"ok"] = @NO;
            resp[@"error"] = @"unknown action";
        }

        WXWritePlistAtomic(resp, respPath);
        WXAppendLog(logPath, [NSString stringWithFormat:@"wrote response=%@", respPath]);

        // Remove request after processing.
        [[NSFileManager defaultManager] removeItemAtPath:reqPath error:nil];

        NSNumber *bridgeOnly = req[@"bridgeOnly"];
        BOOL shouldStop = [bridgeOnly respondsToSelector:@selector(boolValue)] ? [bridgeOnly boolValue] : YES;
        if (shouldStop) {
            raise(SIGSTOP);
        }
    }
}

static void WXNotifyCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    WXProcessRequestForCurrentApp();
}

__attribute__((constructor)) static void WXKeychainBridgeInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (!bundleID.length) return;
        NSString *safe = WXSafeBundle(bundleID);

        NSString *notifyName = [NSString stringWithFormat:@"com.hydra.weaponx.keychain.req.%@", safe];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        WXNotifyCallback,
                                        (__bridge CFStringRef)notifyName,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // Process immediately if a request already exists.
        WXProcessRequestForCurrentApp();
    }
}
