#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString *PXKBSecError(OSStatus status) {
    CFStringRef s = SecCopyErrorMessageString(status, NULL);
    NSString *out = s ? (__bridge_transfer NSString *)s : [NSString stringWithFormat:@"OSStatus %d", (int)status];
    return out;
}

static NSString *PXKBRequestPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"weaponx_keychain_request.plist"];
}

static NSString *PXKBResponsePath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"weaponx_keychain_response.plist"];
}

static NSDictionary *PXKBReadPlist(NSString *path) {
    if (!path.length) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

static BOOL PXKBWritePlist(id plist, NSString *path) {
    if (!path.length || !plist) return NO;
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

static CFTypeRef PXSecItemClassFromName(NSString *name) {
    if ([name isEqualToString:@"GenericPassword"]) return kSecClassGenericPassword;
    if ([name isEqualToString:@"InternetPassword"]) return kSecClassInternetPassword;
    if ([name isEqualToString:@"Certificate"]) return kSecClassCertificate;
    if ([name isEqualToString:@"Key"]) return kSecClassKey;
    if ([name isEqualToString:@"Identity"]) return kSecClassIdentity;
    return NULL;
}

static NSArray<NSDictionary *> *PXKBExportItems(NSArray<NSString *> *groups, NSError **outErr) {
    NSMutableArray<NSDictionary *> *itemsOut = [NSMutableArray array];
    NSArray<NSString *> *classNames = @[ @"GenericPassword", @"InternetPassword", @"Certificate", @"Key", @"Identity" ];

    for (NSString *group in groups) {
        if (![group isKindOfClass:[NSString class]] || !group.length) continue;
        for (NSString *className in classNames) {
            CFTypeRef secClass = PXSecItemClassFromName(className);
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
            OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &cfRes);
            if (status == errSecItemNotFound) {
                continue;
            }
            if (status != errSecSuccess) {
                if (outErr) {
                    *outErr = [NSError errorWithDomain:@"com.hydra.projectx.keychainbridge"
                                                  code:(NSInteger)status
                                              userInfo:@{NSLocalizedDescriptionKey: PXKBSecError(status)}];
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
            if (!arr.count) continue;

            for (NSDictionary *item in arr) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;

                NSMutableDictionary *exportItem = [NSMutableDictionary dictionary];
                exportItem[@"_class"] = className;
                exportItem[@"_secClass"] = (__bridge id)secClass;

                for (id k in item) {
                    if (![k isKindOfClass:[NSString class]]) continue;
                    id v = item[k];
                    if ([v isKindOfClass:[NSData class]]) {
                        exportItem[k] = @{
                            @"_type": @"data",
                            @"_base64": [(NSData *)v base64EncodedStringWithOptions:0]
                        };
                    } else if ([v isKindOfClass:[NSDate class]]) {
                        exportItem[k] = @{
                            @"_type": @"date",
                            @"_timestamp": @([(NSDate *)v timeIntervalSince1970])
                        };
                    } else if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) {
                        exportItem[k] = v;
                    }
                }

                [itemsOut addObject:exportItem];
            }
        }
    }

    return itemsOut;
}

static NSDictionary *PXKBNormalizeValue(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)v;
    }
    return nil;
}

static id PXKBRestoreValue(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)v;
        NSString *type = d[@"_type"];
        if ([type isEqualToString:@"data"]) {
            NSString *b64 = d[@"_base64"];
            if ([b64 isKindOfClass:[NSString class]]) {
                return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
            }
        }
        if ([type isEqualToString:@"date"]) {
            NSNumber *ts = d[@"_timestamp"];
            if ([ts isKindOfClass:[NSNumber class]]) {
                return [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]];
            }
        }
    }
    return v;
}

static NSSet<NSString *> *PXKBExcludedRestoreAttributes(void) {
    static NSSet *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [NSSet setWithObjects:
             (__bridge NSString *)kSecAttrAccessControl,
             (__bridge NSString *)kSecAttrCreationDate,
             (__bridge NSString *)kSecAttrModificationDate,
             (__bridge NSString *)kSecAttrPersistentReference,
             (__bridge NSString *)kSecValuePersistentRef,
             @"tomb",
             @"UUID",
             @"sha1",
             nil];
    });
    return s;
}

static BOOL PXKBWipeGroups(NSArray<NSString *> *groups) {
    NSArray<NSString *> *classNames = @[ @"GenericPassword", @"InternetPassword", @"Certificate", @"Key", @"Identity" ];
    for (NSString *group in groups) {
        if (![group isKindOfClass:[NSString class]] || !group.length) continue;
        for (NSString *className in classNames) {
            CFTypeRef secClass = PXSecItemClassFromName(className);
            if (!secClass) continue;
            NSMutableDictionary *q = [@{
                (__bridge id)kSecClass: (__bridge id)secClass,
                (__bridge id)kSecAttrAccessGroup: group,
            } mutableCopy];
            if (@available(iOS 9.0, *)) {
                q[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
            }
            SecItemDelete((__bridge CFDictionaryRef)q);
        }
    }
    return YES;
}

static NSDictionary *PXKBImportItemsFromPlist(NSDictionary *backup, BOOL overwrite) {
    if (![backup isKindOfClass:[NSDictionary class]]) {
        return @{ @"ok": @NO, @"error": @"invalid backup plist" };
    }
    NSArray *items = backup[@"items"];
    if (![items isKindOfClass:[NSArray class]]) {
        return @{ @"ok": @NO, @"error": @"missing items" };
    }
    NSArray *groups = backup[@"accessGroups"];
    if (overwrite && [groups isKindOfClass:[NSArray class]]) {
        PXKBWipeGroups((NSArray *)groups);
    }

    NSUInteger processed = 0, ok = 0, failed = 0;
    NSMutableArray *errors = [NSMutableArray array];
    NSSet *excluded = PXKBExcludedRestoreAttributes();

    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        processed++;
        id secClass = item[@"_secClass"];
        if (!secClass) {
            NSString *cn = item[@"_class"];
            CFTypeRef c = PXSecItemClassFromName(cn);
            if (c) secClass = (__bridge id)c;
        }
        if (!secClass) {
            failed++;
            [errors addObject:@"missing secClass"]; 
            continue;
        }
        NSMutableDictionary *add = [NSMutableDictionary dictionary];
        add[(__bridge id)kSecClass] = secClass;
        for (NSString *k in item) {
            if (![k isKindOfClass:[NSString class]]) continue;
            if ([k hasPrefix:@"_"]) continue;
            if ([excluded containsObject:k]) continue;
            id v = item[k];
            id rv = PXKBRestoreValue(v);
            if (!rv) continue;
            add[k] = rv;
        }
        if (@available(iOS 9.0, *)) {
            add[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
        }
        OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        if (st == errSecSuccess) {
            ok++;
        } else {
            failed++;
            NSString *acct = add[(__bridge id)kSecAttrAccount] ?: @"";
            NSString *svc = add[(__bridge id)kSecAttrService] ?: @"";
            NSString *grp = add[(__bridge id)kSecAttrAccessGroup] ?: @"";
            [errors addObject:[NSString stringWithFormat:@"add failed acct=%@ svc=%@ group=%@: %@", acct, svc, grp, PXKBSecError(st)]];
        }
    }

    return @{ @"ok": @YES,
              @"processed": @(processed),
              @"succeeded": @(ok),
              @"failed": @(failed),
              @"errors": errors };
}

static void PXKBProcessRequestOnce(void) {
    NSString *reqPath = PXKBRequestPath();
    NSDictionary *req = PXKBReadPlist(reqPath);
    if (![req isKindOfClass:[NSDictionary class]]) return;

    NSString *action = req[@"action"];
    NSString *bundleID = req[@"bundleID"];
    NSString *curBundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (bundleID.length && ![bundleID isEqualToString:curBundle]) {
        return;
    }

    NSArray *groups = req[@"groups"];
    if (![groups isKindOfClass:[NSArray class]]) {
        groups = @[];
    }

    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
    resp[@"bundleID"] = curBundle;
    resp[@"action"] = action ?: @"";
    resp[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);

    if ([action isEqualToString:@"backup"]) {
        NSString *outName = req[@"outFileName"];
        if (![outName isKindOfClass:[NSString class]] || !outName.length) {
            outName = @"weaponx_keychain_export.plist";
        }
        NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:outName];
        NSError *exportErr = nil;
        NSArray *items = PXKBExportItems((NSArray *)groups, &exportErr);
        NSDictionary *backup = @{
            @"version": @1,
            @"created": @([[NSDate date] timeIntervalSince1970]),
            @"accessGroups": groups,
            @"items": items ?: @[],
        };
        BOOL ok = PXKBWritePlist(backup, outPath);
        resp[@"ok"] = @(ok);
        resp[@"items"] = @([(NSArray *)items count]);
        resp[@"outPath"] = outPath;
        if (exportErr) resp[@"error"] = exportErr.localizedDescription ?: @"export failed";
    } else if ([action isEqualToString:@"restore"]) {
        NSString *inPath = req[@"inPath"];
        NSNumber *overwrite = req[@"overwrite"];
        NSDictionary *backup = [NSDictionary dictionaryWithContentsOfFile:inPath ?: @""];
        NSDictionary *r = PXKBImportItemsFromPlist(backup, overwrite ? [overwrite boolValue] : YES);
        [resp addEntriesFromDictionary:r];
    } else if ([action isEqualToString:@"list"]) {
        NSError *exportErr = nil;
        NSArray *items = PXKBExportItems((NSArray *)groups, &exportErr);
        resp[@"ok"] = @YES;
        resp[@"items"] = @([(NSArray *)items count]);
        if (exportErr) resp[@"error"] = exportErr.localizedDescription ?: @"";
    } else {
        resp[@"ok"] = @NO;
        resp[@"error"] = @"unknown action";
    }

    PXKBWritePlist(resp, PXKBResponsePath());
    [[NSFileManager defaultManager] removeItemAtPath:reqPath error:nil];
}

__attribute__((constructor)) static void PXKBInit(void) {
    @autoreleasepool {
        // Poll briefly for a request after launch.
        dispatch_async(dispatch_get_main_queue(), ^{
            __block int ticks = 0;
            dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(t, ^{
                ticks++;
                PXKBProcessRequestOnce();
                // Stop after ~10s.
                if (ticks > 40) {
                    dispatch_source_cancel(t);
                }
            });
            dispatch_resume(t);
        });
    }
}
