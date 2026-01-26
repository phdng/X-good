#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CommandResult : NSObject
@property (nonatomic, assign) int exitCode;
@property (nonatomic, copy) NSString *stdoutString;
@property (nonatomic, copy) NSString *stderrString;
@end

@interface CommandRunner : NSObject
+ (instancetype)shared;

// Runs a command using /bin/sh -c.
// stdout/stderr capture depends on method used.
- (CommandResult *)run:(NSString *)command;
- (CommandResult *)runAndCapture:(NSString *)command;

- (nullable NSString *)firstExistingPath:(NSArray<NSString *> *)paths;

@end

NS_ASSUME_NONNULL_END
