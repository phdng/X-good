// Simplest possible constructor test - no dependencies
#import <Foundation/Foundation.h>

%ctor {
    // Write flag file immediately - no other code
    [@"AAA_TEST_CTOR_RAN" writeToFile:@"/tmp/AAA_ctor_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
