#import <Foundation/Foundation.h>

%ctor {
    NSLog(@"[TestCtorTweak] Constructor running!");
    [@"CTOR_RAN" writeToFile:@"/tmp/test_ctor.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"CTOR_RAN" writeToFile:@"/var/mobile/test_ctor.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
