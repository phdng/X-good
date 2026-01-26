#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, PXBackupOptions) {
    PXBackupOptionIncludeAppGroups   = 1 << 0,
    PXBackupOptionIncludePreferences = 1 << 1,
};

@interface PXBackupResult : NSObject
@property (nonatomic, copy) NSString *backupDirectory;
@property (nonatomic, copy) NSString *manifestPath;
@property (nonatomic, copy) NSArray<NSString *> *warnings;
@end

@interface PXRestoreResult : NSObject
@property (nonatomic, copy) NSArray<NSString *> *warnings;
@end

@interface AppDataBackupManager : NSObject

+ (instancetype)shared;

- (void)createBackupForBundleID:(NSString *)bundleID
                        appName:(nullable NSString *)appName
                        options:(PXBackupOptions)options
                     completion:(void (^)(PXBackupResult *_Nullable result, NSError *_Nullable error))completion;

- (NSArray<NSString *> *)listBackupDirectoriesForBundleID:(NSString *)bundleID;

- (NSDictionary *_Nullable)readManifestAtBackupDirectory:(NSString *)backupDir
                                                   error:(NSError **)error;

- (void)restoreBackupAtDirectory:(NSString *)backupDir
                         bundleID:(NSString *)bundleID
                          appName:(nullable NSString *)appName
                       completion:(void (^)(PXRestoreResult *_Nullable result, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
