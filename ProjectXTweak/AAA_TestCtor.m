// Test using +load method instead of constructor
#import <Foundation/Foundation.h>

@interface AAA_TestLoader : NSObject
@end

@implementation AAA_TestLoader

+ (void)load {
    // +load is called automatically when the class is loaded
    [@"AAA_LOAD_METHOD_RAN" writeToFile:@"/tmp/AAA_load_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[WeaponX-DEBUG] +load method executed!");
}

@end

// Also try constructor
__attribute__((constructor))
static void AAA_TestCtor_init(void) {
    [@"AAA_TEST_CTOR_RAN" writeToFile:@"/tmp/AAA_ctor_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
