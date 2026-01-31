#import "AppGroupContainerResolver.h"

@implementation AppGroupContainerInfo
@end

@implementation AppGroupContainerResolver

- (NSArray<AppGroupContainerInfo *> *)resolveGroupContainersForGroupIDs:(NSArray<NSString *> *)groupIDs {
    if (!groupIDs.count) {
        return @[];
    }

    NSSet<NSString *> *wanted = [NSSet setWithArray:groupIDs];
    NSMutableArray<AppGroupContainerInfo *> *results = [NSMutableArray array];

    // Prefer canonical rootful paths to avoid duplicate results (/var is typically a symlink to /private/var).
    NSArray<NSString *> *baseDirs = @[
        @"/private/var/mobile/Containers/Shared/AppGroup",
        @"/containers/Shared/AppGroup"
    ];

    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *base in baseDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:base isDirectory:&isDir] || !isDir) {
            continue;
        }

        NSArray<NSString *> *uuids = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *uuid in uuids) {
            if ([uuid hasPrefix:@"."]) {
                continue;
            }

            NSString *containerPath = [base stringByAppendingPathComponent:uuid];
            NSString *metadataPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
            if (![metadata isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            id ident = metadata[@"MCMMetadataIdentifier"];
            if ([ident isKindOfClass:[NSString class]]) {
                NSString *gid = (NSString *)ident;
                if ([wanted containsObject:gid]) {
                    NSString *key = [NSString stringWithFormat:@"%@|%@", uuid, gid];
                    if ([seen containsObject:key]) {
                        continue;
                    }
                    [seen addObject:key];
                    AppGroupContainerInfo *info = [[AppGroupContainerInfo alloc] init];
                    info.groupID = gid;
                    info.uuid = uuid;
                    info.path = containerPath;
                    [results addObject:info];
                }
            } else if ([ident isKindOfClass:[NSArray class]]) {
                for (id g in (NSArray *)ident) {
                    if ([g isKindOfClass:[NSString class]] && [wanted containsObject:(NSString *)g]) {
                        NSString *gid = (NSString *)g;
                        NSString *key = [NSString stringWithFormat:@"%@|%@", uuid, gid];
                        if ([seen containsObject:key]) {
                            break;
                        }
                        [seen addObject:key];
                        AppGroupContainerInfo *info = [[AppGroupContainerInfo alloc] init];
                        info.groupID = gid;
                        info.uuid = uuid;
                        info.path = containerPath;
                        [results addObject:info];
                        break;
                    }
                }
            }
        }
    }

    return results;
}

@end
