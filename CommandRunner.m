#import "CommandRunner.h"

#import <spawn.h>
#import <sys/wait.h>
#import <sys/select.h>
#import <fcntl.h>
#import <errno.h>

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

    // Prevent deadlocks: drain stdout/stderr concurrently.
    // Without this, a chatty stderr can fill its pipe and block the child while we're still
    // reading stdout (or vice versa).
    int outFd = outPipe[0];
    int errFd = errPipe[0];

    (void)fcntl(outFd, F_SETFL, fcntl(outFd, F_GETFL) | O_NONBLOCK);
    (void)fcntl(errFd, F_SETFL, fcntl(errFd, F_GETFL) | O_NONBLOCK);

    NSMutableData *outData = [NSMutableData data];
    NSMutableData *errData = [NSMutableData data];
    char buffer[4096];

    BOOL outOpen = YES;
    BOOL errOpen = YES;
    while (outOpen || errOpen) {
        fd_set readfds;
        FD_ZERO(&readfds);
        int maxfd = -1;
        if (outOpen) {
            FD_SET(outFd, &readfds);
            if (outFd > maxfd) maxfd = outFd;
        }
        if (errOpen) {
            FD_SET(errFd, &readfds);
            if (errFd > maxfd) maxfd = errFd;
        }

        // 1s timeout to avoid hard hangs.
        struct timeval tv;
        tv.tv_sec = 1;
        tv.tv_usec = 0;

        int sel = select(maxfd + 1, &readfds, NULL, NULL, &tv);
        if (sel < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        if (sel == 0) {
            continue;
        }

        if (outOpen && FD_ISSET(outFd, &readfds)) {
            for (;;) {
                ssize_t n = read(outFd, buffer, sizeof(buffer));
                if (n > 0) {
                    [outData appendBytes:buffer length:(NSUInteger)n];
                    continue;
                }
                if (n == 0) {
                    close(outFd);
                    outOpen = NO;
                }
                // n < 0
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                    // drained for now
                } else if (n < 0 && errno != EINTR) {
                    close(outFd);
                    outOpen = NO;
                }
                break;
            }
        }

        if (errOpen && FD_ISSET(errFd, &readfds)) {
            for (;;) {
                ssize_t n = read(errFd, buffer, sizeof(buffer));
                if (n > 0) {
                    [errData appendBytes:buffer length:(NSUInteger)n];
                    continue;
                }
                if (n == 0) {
                    close(errFd);
                    errOpen = NO;
                }
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                } else if (n < 0 && errno != EINTR) {
                    close(errFd);
                    errOpen = NO;
                }
                break;
            }
        }
    }

    if (outOpen) {
        close(outFd);
    }
    if (errOpen) {
        close(errFd);
    }

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
