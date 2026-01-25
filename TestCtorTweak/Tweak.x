#import <Foundation/Foundation.h>

%ctor {
    NSLog(@"[TestCtorTweak] Constructor running!");
    [@"CTOR_RAN_LOGOS" writeToFile:@"/tmp/test_ctor_logos.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"CTOR_RAN_LOGOS" writeToFile:@"/var/mobile/test_ctor_logos.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
