// JailbreakBypassHooks.x
// Phase 1: File/URL/InstalledApps/LoopbackPortScan/WriteCheck

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <dirent.h>
#import <stdarg.h>
#import <spawn.h>
#import <signal.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/types.h>
#import <sys/syscall.h>
#import <sys/mount.h>
#import <sys/statvfs.h>
#import <string.h>

// Some Theos SDKs for iOS don't ship <sys/ptrace.h>.
// PT_DENY_ATTACH is 31 on Darwin.
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif
#import <unistd.h>

#import <substrate.h>

// Optional logging macro if ProjectXLogging is present.
#ifndef PXLog
#define PXLog(...) NSLog(__VA_ARGS__)
#endif

@interface IdentifierManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)isApplicationEnabled:(NSString *)bundleID;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)installedApplications;
- (NSArray *)allApplications;
@end

static void *FindSymbol(const char *image, const char *symbol) {
    if (!symbol) return NULL;
    if (image) {
        void *handle = dlopen(image, RTLD_NOW);
        if (!handle) return dlsym(RTLD_DEFAULT, symbol);
        return dlsym(handle, symbol);
    }
    return dlsym(RTLD_DEFAULT, symbol);
}

static BOOL PXStrEqNoCase(const char *a, const char *b) {
    if (!a || !b) return NO;
    while (*a && *b) {
        char ca = *a;
        char cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb - 'A' + 'a');
        if (ca != cb) return NO;
        a++; b++;
    }
    return (*a == '\0' && *b == '\0');
}

static BOOL PXHasPrefix(const char *s, const char *prefix) {
    if (!s || !prefix) return NO;
    size_t n = strlen(prefix);
    return strncmp(s, prefix, n) == 0;
}

static BOOL PXHasPrefixNoCase(const char *s, const char *prefix) {
    if (!s || !prefix) return NO;
    while (*prefix) {
        char a = *s;
        char b = *prefix;
        if (!a) return NO;
        if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
        if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        if (a != b) return NO;
        s++; prefix++;
    }
    return YES;
}

static NSString *PXMainBundleID(void) {
    static NSString *bid = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bid = [[NSBundle mainBundle] bundleIdentifier];
    });
    return bid;
}

static BOOL PXJBIsCriticalProcess(void) {
    static BOOL computed = NO;
    static BOOL isCritical = NO;
    if (computed) return isCritical;
    computed = YES;
    NSString *p = [NSProcessInfo processInfo].processName;
    if ([p isEqualToString:@"launchd"] || [p isEqualToString:@"SpringBoard"] || [p isEqualToString:@"backboardd"]) {
        isCritical = YES;
    }
    return isCritical;
}

static volatile BOOL gJBEnabled = NO;
static volatile BOOL gJBStatfsEnabled = NO;
static volatile CFTimeInterval gJBLastCheck = 0;
static BOOL PXJBShouldBypassCached(void) {
    if (PXJBIsCriticalProcess()) return NO;
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gJBLastCheck < 1.0) {
        return gJBEnabled;
    }
    gJBLastCheck = now;

    @autoreleasepool {
        NSString *bundleID = PXMainBundleID();
        if (!bundleID.length) {
            gJBEnabled = NO;
            return gJBEnabled;
        }
        if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
            gJBEnabled = NO;
            return gJBEnabled;
        }
        if ([bundleID hasPrefix:@"com.apple."]) {
            gJBEnabled = NO;
            return gJBEnabled;
        }

        NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        BOOL enabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
        if (!enabled) {
            gJBEnabled = NO;
            gJBStatfsEnabled = NO;
            return gJBEnabled;
        }

        // Phase 2 extension toggle: mount/volume checks via statfs/statvfs.
        gJBStatfsEnabled = [securitySettings boolForKey:@"jbBypassStatfsEnabled"]; // default OFF

        Class mgrCls = NSClassFromString(@"IdentifierManager");
        if (!mgrCls || ![mgrCls respondsToSelector:@selector(sharedManager)]) {
            gJBEnabled = NO;
            return gJBEnabled;
        }
        IdentifierManager *mgr = [mgrCls performSelector:@selector(sharedManager)];
        if (!mgr || ![mgr respondsToSelector:@selector(isApplicationEnabled:)]) {
            gJBEnabled = NO;
            return gJBEnabled;
        }
        gJBEnabled = [mgr isApplicationEnabled:bundleID];
        return gJBEnabled;
    }
}

static BOOL PXJBStatfsBypassEnabled(void) {
    return PXJBShouldBypassCached() && gJBStatfsEnabled;
}

// Path matching
static BOOL PXJBIsHiddenExactPath(const char *path) {
    if (!path) return NO;
    static const char *kExact[] = {
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Applications/Filza.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/Library/MobileSubstrate/DynamicLibraries",
        "/usr/lib/libsubstrate.dylib",
        "/usr/sbin/sshd",
        "/bin/bash",
        "/etc/apt",
        "/var/lib/apt",
        "/var/lib/cydia",
        "/private/jailbreak_test",
        "/private/var/jailbreak_test",
        NULL
    };
    for (int i = 0; kExact[i]; i++) {
        if (strcmp(path, kExact[i]) == 0) return YES;
    }
    return NO;
}

static BOOL PXJBIsHiddenPrefixPath(const char *path) {
    if (!path) return NO;
    static const char *kPrefixes[] = {
        "/var/jb",
        "/private/var/jb",
        "/private/preboot/jb",
        "/var/lib/apt",
        "/private/var/lib/apt",
        "/var/tmp/cydia",
        "/private/var/tmp/cydia",
        NULL
    };
    for (int i = 0; kPrefixes[i]; i++) {
        if (PXHasPrefix(path, kPrefixes[i])) return YES;
    }
    return NO;
}

static BOOL PXJBPathShouldHide(const char *path) {
    if (!path) return NO;
    if (path[0] != '/') return NO;
    // Quick exact/prefix checks.
    if (PXJBIsHiddenExactPath(path)) return YES;
    if (PXJBIsHiddenPrefixPath(path)) return YES;
    return NO;
}

static BOOL PXJBIsWriteAttempt(int flags) {
    if (flags & O_CREAT) return YES;
    if (flags & O_TRUNC) return YES;
    if ((flags & O_ACCMODE) == O_WRONLY) return YES;
    if ((flags & O_ACCMODE) == O_RDWR) return YES;
    return NO;
}

static BOOL PXJBIsSandboxAllowedWritePath(const char *path) {
    if (!path) return NO;
    // Allow normal sandbox container paths.
    if (PXHasPrefix(path, "/var/mobile/Containers/")) return YES;
    if (PXHasPrefix(path, "/private/var/mobile/Containers/")) return YES;
    if (PXHasPrefix(path, "/containers/Data/")) return YES;
    if (PXHasPrefix(path, "/private/var/containers/")) return YES;
    return NO;
}

static BOOL PXJBWriteCheckShouldBlock(const char *path, int flags) {
    if (!path) return NO;
    if (!PXJBIsWriteAttempt(flags)) return NO;
    // Only block classic jailbreak write-probe targets and obvious restricted prefixes.
    if (PXJBIsSandboxAllowedWritePath(path)) return NO;
    if (PXHasPrefix(path, "/private/jailbreak_test")) return YES;
    if (PXHasPrefix(path, "/private/var/jailbreak_test")) return YES;
    if (PXHasPrefix(path, "/var/tmp/cydia")) return YES;
    if (PXHasPrefix(path, "/private/var/tmp/cydia")) return YES;
    return NO;
}

// Loopback port scan blocking
static BOOL PXJBIsDeniedLoopbackPort(uint16_t port) {
    switch (port) {
        case 22:      // ssh
        case 44:      // historically used by some detectors
        case 27042:   // frida
        case 4444:
        case 5555:
            return YES;
        default:
            return NO;
    }
}

// --- C hooks ---
static int (*orig_stat)(const char *, struct stat *);
static int hook_stat(const char *path, struct stat *st) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat ? orig_stat(path, st) : -1;
}

static int (*orig_stat64)(const char *, struct stat *);
static int hook_stat64(const char *path, struct stat *st) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat64 ? orig_stat64(path, st) : -1;
}

static int (*orig_lstat)(const char *, struct stat *);
static int hook_lstat(const char *path, struct stat *st) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat ? orig_lstat(path, st) : -1;
}

static int (*orig_lstat64)(const char *, struct stat *);
static int hook_lstat64(const char *path, struct stat *st) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat64 ? orig_lstat64(path, st) : -1;
}

static int (*orig_access)(const char *, int);
static int hook_access(const char *path, int amode) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access ? orig_access(path, amode) : -1;
}

static int (*orig_open)(const char *, int, ...);
static int hook_open(const char *path, int oflag, ...) {
    if (PXJBShouldBypassCached()) {
        if (PXJBPathShouldHide(path)) {
            errno = ENOENT;
            return -1;
        }
        if (PXJBWriteCheckShouldBlock(path, oflag)) {
            errno = EACCES;
            return -1;
        }
    }

    int mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    return orig_open ? orig_open(path, oflag, mode) : -1;
}

static int (*orig_openat)(int, const char *, int, ...);
static int hook_openat(int fd, const char *path, int oflag, ...) {
    if (PXJBShouldBypassCached()) {
        if (path && path[0] == '/' && PXJBPathShouldHide(path)) {
            errno = ENOENT;
            return -1;
        }
        if (path && path[0] == '/' && PXJBWriteCheckShouldBlock(path, oflag)) {
            errno = EACCES;
            return -1;
        }
    }

    int mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    return orig_openat ? orig_openat(fd, path, oflag, mode) : -1;
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *hook_fopen(const char *path, const char *mode) {
    if (PXJBShouldBypassCached()) {
        if (PXJBPathShouldHide(path)) {
            errno = ENOENT;
            return NULL;
        }
        if (path && mode) {
            // If mode implies write.
            if (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+')) {
                int flags = O_WRONLY | O_CREAT;
                if (PXJBWriteCheckShouldBlock(path, flags)) {
                    errno = EACCES;
                    return NULL;
                }
            }
        }
    }
    return orig_fopen ? orig_fopen(path, mode) : NULL;
}

static DIR *(*orig_opendir)(const char *);
static DIR *hook_opendir(const char *path) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return NULL;
    }
    return orig_opendir ? orig_opendir(path) : NULL;
}

static struct dirent *(*orig_readdir)(DIR *);
static struct dirent *hook_readdir(DIR *dirp) {
    if (!orig_readdir) return NULL;
    struct dirent *ent = orig_readdir(dirp);
    if (!PXJBShouldBypassCached()) return ent;

    // Hide common jailbreak app names if a directory listing is used.
    while (ent) {
        const char *n = ent->d_name;
        if (n) {
            if (PXStrEqNoCase(n, "Cydia.app") || PXStrEqNoCase(n, "Sileo.app") || PXStrEqNoCase(n, "Zebra.app") || PXStrEqNoCase(n, "Filza.app")) {
                ent = orig_readdir(dirp);
                continue;
            }
        }
        break;
    }
    return ent;
}

static ssize_t (*orig_readlink)(const char *, char *, size_t);
static ssize_t hook_readlink(const char *path, char *buf, size_t bufsiz) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_readlink ? orig_readlink(path, buf, bufsiz) : -1;
}

static char *(*orig_realpath)(const char *, char *);
static char *hook_realpath(const char *path, char *resolved) {
    if (PXJBShouldBypassCached() && PXJBPathShouldHide(path)) {
        errno = ENOENT;
        return NULL;
    }
    return orig_realpath ? orig_realpath(path, resolved) : NULL;
}

static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int hook_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (PXJBShouldBypassCached() && addr) {
        if (addr->sa_family == AF_INET && addrlen >= sizeof(struct sockaddr_in)) {
            const struct sockaddr_in *a = (const struct sockaddr_in *)addr;
            uint32_t ip = ntohl(a->sin_addr.s_addr);
            uint16_t port = ntohs(a->sin_port);
            if (ip == INADDR_LOOPBACK && PXJBIsDeniedLoopbackPort(port)) {
                errno = ECONNREFUSED;
                return -1;
            }
        } else if (addr->sa_family == AF_INET6 && addrlen >= sizeof(struct sockaddr_in6)) {
            const struct sockaddr_in6 *a6 = (const struct sockaddr_in6 *)addr;
            uint16_t port = ntohs(a6->sin6_port);
            static const struct in6_addr loop = IN6ADDR_LOOPBACK_INIT;
            if (memcmp(&a6->sin6_addr, &loop, sizeof(loop)) == 0 && PXJBIsDeniedLoopbackPort(port)) {
                errno = ECONNREFUSED;
                return -1;
            }
        }
    }
    return orig_connect ? orig_connect(sockfd, addr, addrlen) : -1;
}

static char *(*orig_getenv)(const char *);
static char *hook_getenv(const char *name) {
    if (PXJBShouldBypassCached() && name) {
        if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
            strcmp(name, "DYLD_LIBRARY_PATH") == 0 ||
            strcmp(name, "_MSSafeMode") == 0 ||
            strcmp(name, "JB_SANDBOX_EXTENSIONS") == 0 ||
            strcmp(name, "SHELL") == 0) {
            return NULL;
        }
    }
    return orig_getenv ? orig_getenv(name) : NULL;
}

// Phase 2: anti-debug / anti-exec probes
static int (*orig_ptrace)(int request, pid_t pid, void *addr, int data);
static int hook_ptrace(int request, pid_t pid, void *addr, int data) {
    if (PXJBShouldBypassCached()) {
        // PT_DENY_ATTACH == 31 on Darwin.
        if (request == PT_DENY_ATTACH || request == 31) {
            return 0;
        }
    }
    return orig_ptrace ? orig_ptrace(request, pid, addr, data) : -1;
}

static pid_t (*orig_fork)(void);
static pid_t hook_fork(void) {
    if (PXJBShouldBypassCached()) {
        errno = EPERM;
        return (pid_t)-1;
    }
    return orig_fork ? orig_fork() : (pid_t)-1;
}

static pid_t (*orig_vfork)(void);
static pid_t hook_vfork(void) {
    if (PXJBShouldBypassCached()) {
        errno = EPERM;
        return (pid_t)-1;
    }
    return orig_vfork ? orig_vfork() : (pid_t)-1;
}

// Hook syscall() as a fallback when apps bypass libc wrappers.
static long (*orig_syscall)(long number, ...);
static long hook_syscall(long number, ...) {
    if (!orig_syscall) {
        errno = ENOSYS;
        return -1;
    }

    // Pull up to 6 args as 64-bit values (covers common syscalls).
    uint64_t a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0;
    va_list ap;
    va_start(ap, number);
    a1 = (uint64_t)va_arg(ap, uint64_t);
    a2 = (uint64_t)va_arg(ap, uint64_t);
    a3 = (uint64_t)va_arg(ap, uint64_t);
    a4 = (uint64_t)va_arg(ap, uint64_t);
    a5 = (uint64_t)va_arg(ap, uint64_t);
    a6 = (uint64_t)va_arg(ap, uint64_t);
    va_end(ap);

    if (PXJBShouldBypassCached()) {
        const char *path = NULL;

        switch ((int)number) {
            case SYS_stat:
            case SYS_lstat:
            case SYS_access:
            case SYS_open:
            case SYS_stat64:
            case SYS_lstat64:
                path = (const char *)(uintptr_t)a1;
                if (PXJBPathShouldHide(path)) {
                    errno = ENOENT;
                    return -1;
                }
                if (((int)number) == SYS_open) {
                    int flags = (int)a2;
                    if (PXJBWriteCheckShouldBlock(path, flags)) {
                        errno = EACCES;
                        return -1;
                    }
                }
                break;

            case SYS_openat: {
                path = (const char *)(uintptr_t)a2;
                if (path && path[0] == '/' && PXJBPathShouldHide(path)) {
                    errno = ENOENT;
                    return -1;
                }
                int flags = (int)a3;
                if (path && path[0] == '/' && PXJBWriteCheckShouldBlock(path, flags)) {
                    errno = EACCES;
                    return -1;
                }
                break;
            }
            default:
                break;
        }
    }

    // Forward to original syscall with the same captured args. Extra args are ignored by callee.
    return orig_syscall(number, a1, a2, a3, a4, a5, a6);
}

// Block common jailbreak probe commands executed via system()/popen().
static BOOL PXJBCommandLooksLikeProbe(NSString *cmd) {
    if (![cmd isKindOfClass:[NSString class]] || cmd.length == 0) return NO;
    NSString *c = [[cmd lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!c.length) return NO;

    // Fast substring checks.
    NSArray<NSString *> *needles = @[
        @"cydia", @"sileo", @"zebra", @"filza", @"substrate", @"ellekit", @"libhooker",
        @"frida", @"27042", @"ssh", @"sshd", @"apt", @"dpkg", @"uicache", @"ldrestart", @"cycript", @"su"
    ];
    for (NSString *n in needles) {
        if ([c containsString:n]) return YES;
    }

    // Common patterns: test -f /Applications/Cydia.app, ls /var/jb, etc.
    if ([c containsString:@"/var/jb"] || [c containsString:@"/private/preboot/jb"] || [c containsString:@"/library/mobilesubstrate"]) {
        return YES;
    }
    return NO;
}

static int (*orig_system)(const char *);
static int hook_system(const char *command) {
    if (PXJBShouldBypassCached() && command) {
        NSString *cmd = [NSString stringWithUTF8String:command] ?: @"";
        if (PXJBCommandLooksLikeProbe(cmd)) {
            errno = EPERM;
            return -1;
        }
    }
    return orig_system ? orig_system(command) : -1;
}

static FILE *(*orig_popen)(const char *, const char *);
static FILE *hook_popen(const char *command, const char *type) {
    if (PXJBShouldBypassCached() && command) {
        NSString *cmd = [NSString stringWithUTF8String:command] ?: @"";
        if (PXJBCommandLooksLikeProbe(cmd)) {
            errno = EPERM;
            return NULL;
        }
    }
    return orig_popen ? orig_popen(command, type) : NULL;
}

// Phase 2 extension: mount/volume checks (statfs/statvfs)
static BOOL PXJBIsSensitiveMountPath(const char *path) {
    if (!path) return NO;
    // Most detectors check "/" and sometimes "/private" or "/var".
    if (strcmp(path, "/") == 0) return YES;
    if (strcmp(path, "/var") == 0) return YES;
    if (strcmp(path, "/private") == 0) return YES;
    if (strcmp(path, "/private/var") == 0) return YES;
    return NO;
}

static void PXJBNormalizeStatfs(struct statfs *buf) {
    if (!buf) return;
    // Ensure rootfs looks read-only (common non-JB expectation).
#ifdef MNT_RDONLY
    buf->f_flags |= MNT_RDONLY;
#endif
}

static void PXJBNormalizeStatvfs(struct statvfs *buf) {
    if (!buf) return;
#ifdef ST_RDONLY
    buf->f_flag |= ST_RDONLY;
#endif
}

static int (*orig_statfs)(const char *, struct statfs *);
static int hook_statfs(const char *path, struct statfs *buf) {
    int r = orig_statfs ? orig_statfs(path, buf) : -1;
    if (r == 0 && PXJBStatfsBypassEnabled() && PXJBIsSensitiveMountPath(path)) {
        PXJBNormalizeStatfs(buf);
    }
    return r;
}

static int (*orig_fstatfs)(int, struct statfs *);
static int hook_fstatfs(int fd, struct statfs *buf) {
    int r = orig_fstatfs ? orig_fstatfs(fd, buf) : -1;
    if (r == 0 && PXJBStatfsBypassEnabled()) {
        // We can't reliably map fd->path cheaply; normalize anyway (best-effort).
        PXJBNormalizeStatfs(buf);
    }
    return r;
}

static int (*orig_statvfs)(const char *, struct statvfs *);
static int hook_statvfs(const char *path, struct statvfs *buf) {
    int r = orig_statvfs ? orig_statvfs(path, buf) : -1;
    if (r == 0 && PXJBStatfsBypassEnabled() && PXJBIsSensitiveMountPath(path)) {
        PXJBNormalizeStatvfs(buf);
    }
    return r;
}

static int (*orig_fstatvfs)(int, struct statvfs *);
static int hook_fstatvfs(int fd, struct statvfs *buf) {
    int r = orig_fstatvfs ? orig_fstatvfs(fd, buf) : -1;
    if (r == 0 && PXJBStatfsBypassEnabled()) {
        PXJBNormalizeStatvfs(buf);
    }
    return r;
}

// --- ObjC hooks ---
%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) return NO;
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) {
            if (isDirectory) *isDirectory = NO;
            return NO;
        }
    }
    return %orig;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) return NO;
    }
    return %orig;
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) return NO;
    }
    return %orig;
}

- (BOOL)isExecutableFileAtPath:(NSString *)path {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) return NO;
    }
    return %orig;
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    if (PXJBShouldBypassCached() && [path isKindOfClass:[NSString class]]) {
        const char *p = [path fileSystemRepresentation];
        if (PXJBPathShouldHide(p)) {
            if (error) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
            }
            return nil;
        }
    }
    return %orig;
}

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSArray<NSString *> *orig = %orig;
    if (!PXJBShouldBypassCached()) return orig;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) return orig;

    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:orig.count];
    for (NSString *item in orig) {
        if (![item isKindOfClass:[NSString class]]) continue;
        if ([item caseInsensitiveCompare:@"Cydia.app"] == NSOrderedSame) continue;
        if ([item caseInsensitiveCompare:@"Sileo.app"] == NSOrderedSame) continue;
        if ([item caseInsensitiveCompare:@"Zebra.app"] == NSOrderedSame) continue;
        if ([item caseInsensitiveCompare:@"Filza.app"] == NSOrderedSame) continue;
        [out addObject:item];
    }
    return out;
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
    NSString *dest = %orig;
    if (!PXJBShouldBypassCached()) return dest;
    if (![dest isKindOfClass:[NSString class]] || dest.length == 0) return dest;
    const char *p = [dest fileSystemRepresentation];
    if (PXJBPathShouldHide(p)) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
        }
        return nil;
    }
    return dest;
}

%end

%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    if (PXJBShouldBypassCached() && [url isKindOfClass:[NSURL class]]) {
        NSString *scheme = [[url scheme] lowercaseString];
        if (scheme.length) {
            if ([scheme isEqualToString:@"cydia"] ||
                [scheme isEqualToString:@"sileo"] ||
                [scheme isEqualToString:@"zbra"] ||
                [scheme isEqualToString:@"filza"]) {
                return NO;
            }
        }
    }
    return %orig;
}

%end

%hook LSApplicationWorkspace

- (NSArray *)allInstalledApplications {
    NSArray *apps = %orig;
    if (!PXJBShouldBypassCached()) return apps;
    if (![apps isKindOfClass:[NSArray class]] || apps.count == 0) return apps;

    static NSSet<NSString *> *deny = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        deny = [NSSet setWithArray:@[
            @"com.saurik.Cydia",
            @"org.coolstar.SileoStore",
            @"com.opa334.Sileo",
            @"xyz.willy.Zebra",
            @"com.tigisoftware.Filza",
        ]];
    });

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:apps.count];
    for (id proxy in apps) {
        NSString *bid = nil;
        if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
            bid = [proxy performSelector:@selector(bundleIdentifier)];
        }
        if ([bid isKindOfClass:[NSString class]] && [deny containsObject:bid]) {
            continue;
        }
        [out addObject:proxy];
    }
    return out;
}

- (NSArray *)installedApplications {
    return [self allInstalledApplications];
}

- (NSArray *)allApplications {
    return [self allInstalledApplications];
}

%end

%ctor {
    @autoreleasepool {
        // Install C hooks unconditionally; gate inside hooks for scoped apps.
        if (PXJBIsCriticalProcess()) return;
        void *libSystem = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libSystem) {
            void *sym = NULL;

            sym = FindSymbol(NULL, "stat");
            if (sym) MSHookFunction(sym, (void *)hook_stat, (void **)&orig_stat);

            sym = FindSymbol(NULL, "stat64");
            if (sym) MSHookFunction(sym, (void *)hook_stat64, (void **)&orig_stat64);

            sym = FindSymbol(NULL, "lstat");
            if (sym) MSHookFunction(sym, (void *)hook_lstat, (void **)&orig_lstat);

            sym = FindSymbol(NULL, "lstat64");
            if (sym) MSHookFunction(sym, (void *)hook_lstat64, (void **)&orig_lstat64);

            sym = FindSymbol(NULL, "access");
            if (sym) MSHookFunction(sym, (void *)hook_access, (void **)&orig_access);

            sym = FindSymbol(NULL, "open");
            if (sym) MSHookFunction(sym, (void *)hook_open, (void **)&orig_open);

            sym = FindSymbol(NULL, "openat");
            if (sym) MSHookFunction(sym, (void *)hook_openat, (void **)&orig_openat);

            sym = FindSymbol(NULL, "fopen");
            if (sym) MSHookFunction(sym, (void *)hook_fopen, (void **)&orig_fopen);

            sym = FindSymbol(NULL, "opendir");
            if (sym) MSHookFunction(sym, (void *)hook_opendir, (void **)&orig_opendir);

            sym = FindSymbol(NULL, "readdir");
            if (sym) MSHookFunction(sym, (void *)hook_readdir, (void **)&orig_readdir);

            sym = FindSymbol(NULL, "readlink");
            if (sym) MSHookFunction(sym, (void *)hook_readlink, (void **)&orig_readlink);

            sym = FindSymbol(NULL, "realpath");
            if (sym) MSHookFunction(sym, (void *)hook_realpath, (void **)&orig_realpath);

            sym = FindSymbol(NULL, "connect");
            if (sym) MSHookFunction(sym, (void *)hook_connect, (void **)&orig_connect);

            sym = FindSymbol(NULL, "getenv");
            if (sym) MSHookFunction(sym, (void *)hook_getenv, (void **)&orig_getenv);

            // Phase 2
            sym = FindSymbol(NULL, "ptrace");
            if (sym) MSHookFunction(sym, (void *)hook_ptrace, (void **)&orig_ptrace);

            sym = FindSymbol(NULL, "fork");
            if (sym) MSHookFunction(sym, (void *)hook_fork, (void **)&orig_fork);

            sym = FindSymbol(NULL, "vfork");
            if (sym) MSHookFunction(sym, (void *)hook_vfork, (void **)&orig_vfork);

            sym = FindSymbol(NULL, "syscall");
            if (sym) MSHookFunction(sym, (void *)hook_syscall, (void **)&orig_syscall);

            sym = FindSymbol(NULL, "system");
            if (sym) MSHookFunction(sym, (void *)hook_system, (void **)&orig_system);

            sym = FindSymbol(NULL, "popen");
            if (sym) MSHookFunction(sym, (void *)hook_popen, (void **)&orig_popen);

            // Phase 2 extension (toggle: jbBypassStatfsEnabled)
            sym = FindSymbol(NULL, "statfs");
            if (sym) MSHookFunction(sym, (void *)hook_statfs, (void **)&orig_statfs);

            sym = FindSymbol(NULL, "fstatfs");
            if (sym) MSHookFunction(sym, (void *)hook_fstatfs, (void **)&orig_fstatfs);

            sym = FindSymbol(NULL, "statvfs");
            if (sym) MSHookFunction(sym, (void *)hook_statvfs, (void **)&orig_statvfs);

            sym = FindSymbol(NULL, "fstatvfs");
            if (sym) MSHookFunction(sym, (void *)hook_fstatvfs, (void **)&orig_fstatvfs);

            dlclose(libSystem);
        }

        %init;
        PXLog(@"[JailbreakBypass] Phase 1 hooks initialized");
    }
}
