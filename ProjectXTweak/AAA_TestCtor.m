// Test using +load method instead of constructor
#import <Foundation/Foundation.h>
#include <string.h>

@interface AAA_TestLoader : NSObject
@end

@implementation AAA_TestLoader

+ (void)load {
    // Test-only file. Ensure it never runs in protected apps.
    extern const char *__progname;
    if (__progname && strcmp(__progname, "MB Bank") == 0) {
        return;
    }

    // Try multiple paths - /tmp might be blocked by sandbox
    [@"AAA_LOAD_METHOD_RAN" writeToFile:@"/var/mobile/Library/Logs/ProjectX/AAA_load_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"AAA_LOAD_METHOD_RAN" writeToFile:@"/tmp/AAA_load_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"AAA_LOAD_METHOD_RAN" writeToFile:@"/var/mobile/AAA_load_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // Avoid NSLog here: some protected apps crash during early init.
}

@end

// Constructor using __attribute__((constructor))
__attribute__((constructor))
static void AAA_TestCtor_init(void) {
    extern const char *__progname;
    if (__progname && strcmp(__progname, "MB Bank") == 0) {
        return;
    }
    [@"AAA_TEST_CTOR_RAN" writeToFile:@"/var/mobile/Library/Logs/ProjectX/AAA_ctor_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"AAA_TEST_CTOR_RAN" writeToFile:@"/tmp/AAA_ctor_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"AAA_TEST_CTOR_RAN" writeToFile:@"/var/mobile/AAA_ctor_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// FORCE: Manually register constructor in __mod_init_func section
// This is a workaround for linkers that don't properly handle __attribute__((constructor))
typedef void (*init_func_t)(void);
__attribute__((used, section("__DATA,__mod_init_func")))
static init_func_t AAA_init_ptr = &AAA_TestCtor_init;
