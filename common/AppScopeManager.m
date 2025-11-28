#import "AppScopeManager.h"

@interface AppScopeManager()
@property (nonatomic, strong) NSMutableSet *scopedApps;

@end

@implementation AppScopeManager
+ (instancetype)sharedManager {
    static AppScopeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}
- (instancetype)init {
    self = [super init];
    NSMutableSet *apps =  [self loadPreferences];
    if(apps){
        _scopedApps = apps;
    }else{
        // 初始化scopedApps为空数组
        _scopedApps = [NSMutableSet set];
    }
    return self;
}
- (NSString *)preferencesFilePath{
    return @"/var/jb/var/mobile/Library/Preferences/ProjectXScopes.plist";
}

- (BOOL)isScope{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return NO;
    // 是自己直接返回 不是则判断是否选中
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        return NO;
    }
    // Check each scoped app's extension pattern
    if ([self.scopedApps containsObject:bundleID]) {
        // PXLog(@"[WeaponX] Bundle ID %@ matches extension pattern %@ from app %@", bundleID, extensionPattern, scopedBundleID);
        return YES;
    }
    return NO;
    // return [[IdentifierManager sharedManager] isScope];
}

- (NSMutableSet *)loadPreferences
{
    NSString *filePath = [self preferencesFilePath];
    // 检查plist文件是否存在
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        // 从plist文件读取数据（返回的是NSArray）
        NSArray *savedArray = [NSArray arrayWithContentsOfFile:filePath];
        if (savedArray && [savedArray isKindOfClass:[NSArray class]]) {
            // 将NSArray转换为NSMutableSet
            return [NSMutableSet setWithArray:savedArray];
        }
    }
    return nil;
}
- (void)savePreferences
{
    NSString *filePath = [self preferencesFilePath];
    
    // 将NSSet转换为NSArray并保存到plist文件

    NSArray *applicationsArray = [_scopedApps allObjects];
    BOOL success = [applicationsArray writeToFile:filePath atomically:YES];
    
    if (!success) {
        NSLog(@"Failed to save preferences to plist file: %@", filePath);
    }
}

@end