#import <UIKit/UIKit.h>

@interface KeychainGroupsViewController : UIViewController

- (instancetype)initWithBundleID:(NSString *)bundleID;

@property (nonatomic, copy) void (^onSave)(void);

@end
