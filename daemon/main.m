#import <Foundation/Foundation.h>
#import "WebServerManager.h"


int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 启动 Web 服务器
        [WebServerManager startWebServer];
        
        // 获取当前 RunLoop
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        // 添加一个永远不触发的定时器（技巧性保持 RunLoop 运行）
        NSTimer *keepAliveTimer = [NSTimer timerWithTimeInterval:DBL_MAX
                                                         repeats:YES
                                                           block:^(NSTimer * _Nonnull timer) {
            // 什么都不做，只是为了保持 RunLoop
        }];
        [runLoop addTimer:keepAliveTimer forMode:NSDefaultRunLoopMode];
        
        // 保持 RunLoop 运行直到程序终止
        [runLoop run];
    }
    return 0;
}