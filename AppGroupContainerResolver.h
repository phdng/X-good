#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppGroupContainerInfo : NSObject
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, copy) NSString *path;
@end

@interface AppGroupContainerResolver : NSObject

// Maps application group identifiers to AppGroup container UUID/path using exact metadata matches.
- (NSArray<AppGroupContainerInfo *> *)resolveGroupContainersForGroupIDs:(NSArray<NSString *> *)groupIDs;

@end

NS_ASSUME_NONNULL_END
