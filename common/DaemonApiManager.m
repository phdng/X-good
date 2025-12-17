#import "DaemonApiManager.h"
#import "HttpRequest.h"

@implementation DaemonApiManager
+ (instancetype)sharedManager {
    static DaemonApiManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSMutableSet *)getScopeApps {
    // 创建一个 NSMutableSet，用于存储返回的数据
    __block NSMutableSet *scopeApps = [NSMutableSet set];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(@"loadScopePreferences",^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    NSArray *dataArray = (NSArray *)data;
                    
                    // 将数组中的元素添加到 NSMutableSet
                    for (id app in dataArray) {
                        if (app) {
                            [scopeApps addObject:app];
                        }
                    }
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return scopeApps;
}

- (void) saveScopeApps:(NSMutableSet *)apps{
    daemonPOST(@"saveScopePreferences", [apps allObjects], ^(id response, NSError *error) {
        // 处理响应
    });
}
@end