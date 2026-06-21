#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *PXMobileLibraryPath(void);
FOUNDATION_EXPORT NSString *PXPreferencesPath(void);
FOUNDATION_EXPORT NSString *PXWeaponXBasePath(void);
FOUNDATION_EXPORT NSString *PXProfilesPath(void);
FOUNDATION_EXPORT NSString *PXCurrentProfileInfoPath(void);
FOUNDATION_EXPORT NSString *PXLegacyActiveProfileInfoPath(void);
FOUNDATION_EXPORT NSString *PXProjectXSettingsPath(void);
FOUNDATION_EXPORT NSString *PXGlobalScopePath(void);
FOUNDATION_EXPORT NSString *PXSecuritySettingsPath(void);
FOUNDATION_EXPORT void PXPostSettingsChangedNotification(void);
