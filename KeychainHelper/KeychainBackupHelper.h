#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for keychain backup operations.
extern NSString * const PXKeychainBackupErrorDomain;

/// Error codes for keychain backup operations.
typedef NS_ENUM(NSInteger, PXKeychainBackupErrorCode) {
    PXKeychainBackupErrorUnknown = 0,
    PXKeychainBackupErrorInvalidArguments = 1,
    PXKeychainBackupErrorNoAccessGroups = 2,
    PXKeychainBackupErrorSecurityFramework = 3,
    PXKeychainBackupErrorFileIO = 4,
    PXKeychainBackupErrorInvalidBackupFile = 5,
};

/// Keychain item classes to backup/restore.
typedef NS_OPTIONS(NSUInteger, PXKeychainItemClass) {
    PXKeychainItemClassGenericPassword  = 1 << 0,
    PXKeychainItemClassInternetPassword = 1 << 1,
    PXKeychainItemClassCertificate      = 1 << 2,
    PXKeychainItemClassKey              = 1 << 3,
    PXKeychainItemClassIdentity         = 1 << 4,
    PXKeychainItemClassAll              = 0xFFFF,
};

/// Result of a keychain backup operation.
@interface PXKeychainBackupResult : NSObject
@property (nonatomic, assign) NSUInteger itemsProcessed;
@property (nonatomic, assign) NSUInteger itemsSucceeded;
@property (nonatomic, assign) NSUInteger itemsFailed;
@property (nonatomic, copy) NSArray<NSString *> *warnings;
@property (nonatomic, copy) NSArray<NSString *> *errors;
@end

/// Helper class for keychain backup, restore, and wipe operations.
/// Uses SecItem APIs (SecItemCopyMatching, SecItemAdd, SecItemDelete).
@interface KeychainBackupHelper : NSObject

/// Backup all keychain items matching the specified access groups to a plist file.
/// @param filePath The path to save the backup plist file.
/// @param groups Array of keychain access group identifiers.
/// @param itemClasses Bitmask of keychain item classes to backup.
/// @param error On failure, contains the error information.
/// @return Result object with statistics, or nil on critical failure.
+ (PXKeychainBackupResult *_Nullable)backupKeychainToFile:(NSString *)filePath
                                             accessGroups:(NSArray<NSString *> *)groups
                                              itemClasses:(PXKeychainItemClass)itemClasses
                                                    error:(NSError **)error;

/// Restore keychain items from a backup plist file.
/// @param filePath The path to the backup plist file.
/// @param overwrite If YES, delete existing items before restore.
/// @param error On failure, contains the error information.
/// @return Result object with statistics, or nil on critical failure.
+ (PXKeychainBackupResult *_Nullable)restoreKeychainFromFile:(NSString *)filePath
                                                   overwrite:(BOOL)overwrite
                                                       error:(NSError **)error;

/// Delete all keychain items matching the specified access groups.
/// @param groups Array of keychain access group identifiers.
/// @param itemClasses Bitmask of keychain item classes to delete.
/// @param error On failure, contains the error information.
/// @return Result object with statistics, or nil on critical failure.
+ (PXKeychainBackupResult *_Nullable)wipeKeychainForAccessGroups:(NSArray<NSString *> *)groups
                                                     itemClasses:(PXKeychainItemClass)itemClasses
                                                           error:(NSError **)error;

/// List all keychain items matching the specified access groups (for debugging).
/// @param groups Array of keychain access group identifiers.
/// @param itemClasses Bitmask of keychain item classes to list.
/// @return Array of dictionaries describing each item.
+ (NSArray<NSDictionary *> *)listKeychainItemsForAccessGroups:(NSArray<NSString *> *)groups
                                                  itemClasses:(PXKeychainItemClass)itemClasses;

@end

NS_ASSUME_NONNULL_END
