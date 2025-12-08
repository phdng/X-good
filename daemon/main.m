#import <Foundation/Foundation.h>
#import <GCDWebServers/GCDWebsocketServer.h>
#import <GCDWebServers/GCDWebServerDataResponse.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        GCDWebServer *webServer = [[GCDWebServer alloc] init];

        // 伪装wda
        [webServer startWithPort:8100 bonjourName:nil];
    }
    return 0;
} 