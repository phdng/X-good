#import "CommandRunner.h"

#import <spawn.h>
#import <sys/wait.h>

@implementation CommandResult
@end

@implementation CommandRunner

+ (instancetype)shared {
    static CommandRunner *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (CommandResult *)run:(NSString *)command {
    CommandResult *result = [[CommandResult alloc] init];
    result.stdoutString = @"";
    result.stderrString = @"";

    pid_t pid;
    const char *argv[] = {"/bin/sh", "-c", [command UTF8String], NULL};
    int spawnStatus = posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL);
    if (spawnStatus != 0) {
        result.exitCode = spawnStatus;
        return result;
    }

    int waitStatus = 0;
    waitpid(pid, &waitStatus, 0);
    if (WIFEXITED(waitStatus)) {
        result.exitCode = WEXITSTATUS(waitStatus);
    } else {
        result.exitCode = -1;
    }

    return result;
}

- (CommandResult *)runAndCapture:(NSString *)command {
    CommandResult *result = [[CommandResult alloc] init];
    result.stdoutString = @"";
    result.stderrString = @"";

    int outPipe[2];
    int errPipe[2];
    if (pipe(outPipe) != 0) {
        result.exitCode = -1;
        result.stderrString = @"pipe(out) failed";
        return result;
    }
    if (pipe(errPipe) != 0) {
        close(outPipe[0]);
        close(outPipe[1]);
        result.exitCode = -1;
        result.stderrString = @"pipe(err) failed";
        return result;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    posix_spawn_file_actions_addclose(&actions, errPipe[1]);

    pid_t pid;
    const char *argv[] = {"/bin/sh", "-c", [command UTF8String], NULL};
    int spawnStatus = posix_spawn(&pid, argv[0], &actions, NULL, (char *const *)argv, NULL);
    posix_spawn_file_actions_destroy(&actions);

    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnStatus != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        result.exitCode = spawnStatus;
        return result;
    }

    NSMutableData *outData = [NSMutableData data];
    NSMutableData *errData = [NSMutableData data];

    char buffer[4096];
    ssize_t n = 0;
    while ((n = read(outPipe[0], buffer, sizeof(buffer))) > 0) {
        [outData appendBytes:buffer length:(NSUInteger)n];
    }
    while ((n = read(errPipe[0], buffer, sizeof(buffer))) > 0) {
        [errData appendBytes:buffer length:(NSUInteger)n];
    }

    close(outPipe[0]);
    close(errPipe[0]);

    int waitStatus = 0;
    waitpid(pid, &waitStatus, 0);
    if (WIFEXITED(waitStatus)) {
        result.exitCode = WEXITSTATUS(waitStatus);
    } else {
        result.exitCode = -1;
    }

    NSString *stdoutString = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
    NSString *stderrString = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
    result.stdoutString = stdoutString ?: @"";
    result.stderrString = stderrString ?: @"";
    return result;
}

- (NSString *)firstExistingPath:(NSArray<NSString *> *)paths {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }
    return nil;
}

@end
