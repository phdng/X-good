// JailbreakBypassHooks.x
// Phase 1: File/URL/InstalledApps/LoopbackPortScan/WriteCheck

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <dirent.h>
#import <stdarg.h>
#import <stdlib.h>
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
#import <sys/sysctl.h>
#if __has_include(<sys/user.h>)
#import <sys/user.h>
#endif
#import <string.h>
#import <pthread.h>
#import <dispatch/dispatch.h>
#import <mach/mach.h>
#import <stdint.h>

// Some iOS SDKs used by Theos don't ship <link.h>, but we only need the
// leading fields of dl_phdr_info to access dlpi_name for dl_iterate_phdr.
struct dl_phdr_info {
    uintptr_t dlpi_addr;
    const char *dlpi_name;
    const void *dlpi_phdr;
    unsigned short dlpi_phnum;
};

// Some Theos SDKs for iOS don't ship <sys/ptrace.h>.
// PT_DENY_ATTACH is 31 on Darwin.
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif
#import <unistd.h>
#import <limits.h>

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
static volatile BOOL gJBHideDylibsEnabled = NO;
static volatile BOOL gJBSyscallHookEnabled = NO;
static volatile BOOL gJBBlockDyldAddImageCallbacksEnabled = NO;
static volatile BOOL gJBHideTaskDyldInfoEnabled = NO;
static volatile BOOL gJBHideDlIteratePhdrEnabled = NO;
static volatile BOOL gJBBlockDlopenDlsymProbesEnabled = NO;
static volatile BOOL gJBSysctlProcSanitizeEnabled = NO;
static volatile BOOL gJBHideProcMapsEnabled = NO;
static volatile BOOL gJBHideObjcImagesEnabled = NO;
static volatile BOOL gJBHookSandboxCheckEnabled = NO;
static volatile BOOL gJBDebugLoggingEnabled = NO;
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

        // Phase 3 toggle: hide jailbreak-related dylibs from dyld enumeration.
        gJBHideDylibsEnabled = [securitySettings boolForKey:@"jbBypassHideDylibsEnabled"]; // default OFF

        // Phase 2 extension toggle: syscall() fallback (EXPERIMENTAL; default OFF)
        gJBSyscallHookEnabled = [securitySettings boolForKey:@"jbBypassHookSyscallFallbackEnabled"]; 

        // Phase 3 extension toggle: block suspicious dyld add_image callbacks (default OFF)
        gJBBlockDyldAddImageCallbacksEnabled = [securitySettings boolForKey:@"jbBypassBlockDyldAddImageCallbacksEnabled"]; 

        // Phase 3 extension toggle: hide TASK_DYLD_INFO via task_info (default OFF)
        gJBHideTaskDyldInfoEnabled = [securitySettings boolForKey:@"jbBypassHideTaskDyldInfoEnabled"]; 

        // Phase 3 extension toggle: hide dl_iterate_phdr image enumeration (default OFF)
        gJBHideDlIteratePhdrEnabled = [securitySettings boolForKey:@"jbBypassHideDlIteratePhdrEnabled"]; 

        // Phase 3 extension toggle: block dlopen/dlsym probing for jailbreak tooling (default OFF)
        gJBBlockDlopenDlsymProbesEnabled = [securitySettings boolForKey:@"jbBypassBlockDlopenDlsymProbesEnabled"]; 

        // Phase 3 extension toggle: sanitize sysctl/sysctlbyname proc/debug/bootargs (default OFF)
        gJBSysctlProcSanitizeEnabled = [securitySettings boolForKey:@"jbBypassSysctlProcSanitizeEnabled"]; 

        // Phase 3 extension toggle: hide libproc-based map filename queries (default OFF)
        gJBHideProcMapsEnabled = [securitySettings boolForKey:@"jbBypassHideProcMapsEnabled"]; 

        // Phase 3 extension toggle: hide ObjC runtime image list (default OFF)
        gJBHideObjcImagesEnabled = [securitySettings boolForKey:@"jbBypassHideObjcImagesEnabled"]; 

        // Phase 3 extension toggle: hook sandbox_check (default OFF)
        gJBHookSandboxCheckEnabled = [securitySettings boolForKey:@"jbBypassHookSandboxCheckEnabled"]; 

        // Debug: log blocked operations (default OFF)
        gJBDebugLoggingEnabled = [securitySettings boolForKey:@"jbBypassDebugLoggingEnabled"]; 

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

static BOOL PXJBHideDylibsEnabled(void) {
    return PXJBShouldBypassCached() && gJBHideDylibsEnabled;
}

// Forward declaration (defined later in dyld section).
static BOOL PXStrContainsNoCase(const char *haystack, const char *needle);

static BOOL PXJBBlockDyldAddImageCallbacksEnabled(void) {
    return PXJBShouldBypassCached() && gJBBlockDyldAddImageCallbacksEnabled;
}

static BOOL PXJBHideTaskDyldInfoEnabled(void) {
    return PXJBShouldBypassCached() && gJBHideTaskDyldInfoEnabled;
}

static BOOL PXJBHideDlIteratePhdrEnabled(void) {
    return PXJBShouldBypassCached() && gJBHideDlIteratePhdrEnabled;
}

static BOOL PXJBBlockDlopenDlsymProbesEnabled(void) {
    return PXJBShouldBypassCached() && gJBBlockDlopenDlsymProbesEnabled;
}

static BOOL PXJBSysctlProcSanitizeEnabled(void) {
    return PXJBShouldBypassCached() && gJBSysctlProcSanitizeEnabled;
}

static BOOL PXJBHideProcMapsEnabled(void) {
    return PXJBShouldBypassCached() && gJBHideProcMapsEnabled;
}

static BOOL PXJBHideObjcImagesEnabled(void) {
    return PXJBShouldBypassCached() && gJBHideObjcImagesEnabled;
}

static BOOL PXJBHookSandboxCheckEnabled(void) {
    return PXJBShouldBypassCached() && gJBHookSandboxCheckEnabled;
}

static BOOL PXJBDebugLoggingEnabled(void) {
    return PXJBShouldBypassCached() && gJBDebugLoggingEnabled;
}

static void PXJBLogBlockedOncePerSecond(const char *what, const char *detail) {
    if (!PXJBDebugLoggingEnabled()) return;
    static CFTimeInterval last = 0;
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if ((now - last) < 1.0) return;
    last = now;
    if (!what) what = "(unknown)";
    if (!detail) detail = "";
    PXLog(@"[JailbreakBypass][debug] blocked %s %s", what, detail);
}

static BOOL PXJBSyscallBypassEnabled(void) {
    return PXJBShouldBypassCached() && gJBSyscallHookEnabled;
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
        "/usr/lib/substrate/SubstrateBootstrap.dylib",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/libmryipc.dylib",
        "/usr/lib/libFrida.dylib",
        "/usr/lib/libcycript.dylib",
        "/usr/lib/libjailbreak.dylib",
        "/Library/Frameworks/CydiaSubstrate.framework",
        "/Library/PreferenceBundles",
        "/Library/PreferenceLoader",
        "/usr/bin/ssh",
        "/usr/bin/scp",
        "/var/checkra1n.dmg",
        "/var/binpack",
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
        "/usr/lib/substrate/",
        "/Library/MobileSubstrate/",
        "/private/var/Library/MobileSubstrate/",
        "/private/var/mobile/Library/MobileSubstrate/",
        "/Library/Caches/cy-",
        "/private/var/Library/Caches/cy-",
        "/private/var/mobile/Library/Caches/cy-",
        "/Library/Frameworks/CydiaSubstrate.framework/",
        "/Library/PreferenceBundles/",
        "/Library/PreferenceLoader/",
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

static BOOL PXJBRelativePathLooksLikeProbe(const char *path) {
    if (!path) return NO;
    // Keep this list tight to avoid false positives.
    static const char *needles[] = {
        "mobilesubstrate",
        "cydia.app",
        "sileo.app",
        "zebra.app",
        "filza.app",
        "preferenceloader",
        "preferencebundles",
        "var/jb",
        "library/caches/cy-",
        "substrate",
        "ellekit",
        "libhooker",
        "frida",
        NULL
    };
    for (int i = 0; needles[i]; i++) {
        if (PXStrContainsNoCase(path, needles[i])) return YES;
    }
    return NO;
}

static BOOL PXJBNormalizeAbsolutePath(const char *inPath, char *out, size_t outsz) {
    if (!inPath || !out || outsz < 2) return NO;
    if (inPath[0] != '/') return NO;

    size_t w = 0;
    out[w++] = '/';

    const char *p = inPath;
    while (*p) {
        while (*p == '/') p++;
        if (!*p) break;
        const char *seg = p;
        while (*p && *p != '/') p++;
        size_t segLen = (size_t)(p - seg);
        if (segLen == 1 && seg[0] == '.') {
            continue;
        }
        if (segLen == 2 && seg[0] == '.' && seg[1] == '.') {
            // pop last segment
            if (w > 1) {
                // remove trailing slash if any
                if (out[w - 1] == '/' && w > 1) w--;
                while (w > 1 && out[w - 1] != '/') w--;
            }
            continue;
        }
        // append segment
        if (w > 1 && out[w - 1] != '/') {
            if (w + 1 >= outsz) return NO;
            out[w++] = '/';
        }
        if (w + segLen + 1 >= outsz) return NO;
        memcpy(out + w, seg, segLen);
        w += segLen;
        out[w] = '\0';
    }

    if (w == 0) {
        out[0] = '/';
        out[1] = '\0';
    } else {
        out[w] = '\0';
    }
    return YES;
}

static BOOL PXJBJoinCwdAndNormalize(const char *relPath, char *out, size_t outsz) {
    if (!relPath || !out || outsz < 2) return NO;
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) return NO;
    size_t cwdLen = strlen(cwd);
    size_t relLen = strlen(relPath);
    if (cwdLen == 0 || cwd[0] != '/') return NO;

    char tmp[PATH_MAX];
    size_t need = cwdLen + 1 + relLen + 1;
    if (need >= sizeof(tmp)) return NO;
    memcpy(tmp, cwd, cwdLen);
    tmp[cwdLen] = '/';
    memcpy(tmp + cwdLen + 1, relPath, relLen);
    tmp[cwdLen + 1 + relLen] = '\0';
    return PXJBNormalizeAbsolutePath(tmp, out, outsz);
}

static int hook_openat(int fd, const char *path, int oflag, ...) {
    if (PXJBShouldBypassCached()) {
        if (path) {
            if (path[0] == '/') {
                if (PXJBPathShouldHide(path)) {
                    PXJBLogBlockedOncePerSecond("openat", path);
                    errno = ENOENT;
                    return -1;
                }
                if (PXJBWriteCheckShouldBlock(path, oflag)) {
                    PXJBLogBlockedOncePerSecond("openat(write)", path);
                    errno = EACCES;
                    return -1;
                }
            } else {
#ifndef AT_FDCWD
#define AT_FDCWD (-2)
#endif
                if (fd == AT_FDCWD) {
                    char normalized[PATH_MAX];
                    if (PXJBJoinCwdAndNormalize(path, normalized, sizeof(normalized))) {
                        if (PXJBPathShouldHide(normalized)) {
                            PXJBLogBlockedOncePerSecond("openat", normalized);
                            errno = ENOENT;
                            return -1;
                        }
                        if (PXJBWriteCheckShouldBlock(normalized, oflag)) {
                            PXJBLogBlockedOncePerSecond("openat(write)", normalized);
                            errno = EACCES;
                            return -1;
                        }
                    } else if (PXJBRelativePathLooksLikeProbe(path)) {
                        PXJBLogBlockedOncePerSecond("openat(rel)", path);
                        errno = ENOENT;
                        return -1;
                    }
                } else {
                    // Don't try to resolve fd->path (avoid side effects). Only block obvious probes.
                    if (PXJBRelativePathLooksLikeProbe(path)) {
                        PXJBLogBlockedOncePerSecond("openat(relfd)", path);
                        errno = ENOENT;
                        return -1;
                    }
                }
            }
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
            strcmp(name, "DYLD_FRAMEWORK_PATH") == 0 ||
            strcmp(name, "DYLD_FALLBACK_LIBRARY_PATH") == 0 ||
            strcmp(name, "DYLD_FALLBACK_FRAMEWORK_PATH") == 0 ||
            strcmp(name, "DYLD_ROOT_PATH") == 0 ||
            strcmp(name, "DYLD_SHARED_CACHE_DIR") == 0 ||
            strcmp(name, "DYLD_PRINT_TO_FILE") == 0 ||
            strcmp(name, "DYLD_PRINT_LIBRARIES") == 0 ||
            strcmp(name, "DYLD_PRINT_APIS") == 0 ||
            strcmp(name, "DYLD_PRINT_OPTS") == 0 ||
            strcmp(name, "DYLD_PRINT_ENV") == 0 ||
            strcmp(name, "LD_PRELOAD") == 0 ||
            strcmp(name, "_MSSafeMode") == 0 ||
            strcmp(name, "JB_SANDBOX_EXTENSIONS") == 0 ||
            strcmp(name, "SHELL") == 0) {
            return NULL;
        }
    }
    return orig_getenv ? orig_getenv(name) : NULL;
}

static void PXJBUnsetSuspiciousEnvIfNeeded(void) {
    if (!PXJBShouldBypassCached()) return;
    // Proactive cleanup so detectors reading env via non-getenv paths see a clean environment.
    // Low risk: only affects this process.
    const char *keys[] = {
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "DYLD_FALLBACK_LIBRARY_PATH",
        "DYLD_FALLBACK_FRAMEWORK_PATH",
        "DYLD_ROOT_PATH",
        "DYLD_SHARED_CACHE_DIR",
        "DYLD_PRINT_TO_FILE",
        "DYLD_PRINT_LIBRARIES",
        "DYLD_PRINT_APIS",
        "DYLD_PRINT_OPTS",
        "DYLD_PRINT_ENV",
        "LD_PRELOAD",
        "_MSSafeMode",
        "MSDebug",
        "JB_SANDBOX_EXTENSIONS",
        NULL
    };
    for (int i = 0; keys[i]; i++) {
        unsetenv(keys[i]);
    }
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

    if (!PXJBSyscallBypassEnabled()) {
        // Forward without inspecting. We still have to consume varargs to call the function pointer.
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
        return orig_syscall(number, a1, a2, a3, a4, a5, a6);
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

    if (PXJBSyscallBypassEnabled()) {
        const char *path = NULL;

        switch ((int)number) {
            case SYS_stat:
            case SYS_lstat:
            case SYS_access:
            case SYS_open:
            #ifdef SYS_stat64
            case SYS_stat64:
            #endif
            #ifdef SYS_lstat64
            case SYS_lstat64:
            #endif
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

    // Avoid overly broad substring checks that can break legitimate commands.
    // Only treat as a probe when we see explicit jailbreak tool paths/binaries.
    NSArray<NSString *> *pathNeedles = @[
        @"/applications/cydia.app",
        @"/applications/sileo.app",
        @"/applications/zebra.app",
        @"/applications/filza.app",
        @"/library/mobilesubstrate",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/var/lib/apt",
        @"/var/lib/cydia",
        @"/var/jb",
        @"/private/preboot/jb",
        @"frida-server",
        @"fridagadget",
        @"cycript",
        @"uicache",
        @"ldrestart"
    ];
    for (NSString *n in pathNeedles) {
        if ([c containsString:n]) return YES;
    }

    // Token checks for package managers (match whole tokens only).
    // This avoids false positives like "capture" containing "apt".
    NSCharacterSet *seps = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n;|&()<>\"'\\"];
    NSArray<NSString *> *tokens = [c componentsSeparatedByCharactersInSet:seps];
    for (NSString *t in tokens) {
        if (!t.length) continue;
        if ([t isEqualToString:@"apt"] || [t isEqualToString:@"apt-get"] || [t isEqualToString:@"dpkg"]) {
            return YES;
        }
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

static BOOL PXJBSpawnPathLooksLikeProbe(const char *path) {
    if (!path || !path[0]) return NO;
    if (path[0] == '/' && PXJBPathShouldHide(path)) return YES;
    // Also block common tool names when posix_spawnp is used.
    static const char *denyTokens[] = {
        "ssh",
        "scp",
        "sshd",
        "bash",
        "zsh",
        "sh",
        "uicache",
        "ldrestart",
        "frida-server",
        "cycript",
        "dpkg",
        "apt",
        "apt-get",
        NULL
    };
    const char *base = strrchr(path, '/');
    base = base ? (base + 1) : path;
    for (int i = 0; denyTokens[i]; i++) {
        if (PXStrEqNoCase(base, denyTokens[i])) return YES;
    }
    return NO;
}

static int (*orig_posix_spawn)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const argv[restrict], char *const envp[restrict]);
static int hook_posix_spawn(pid_t *restrict pid, const char *restrict path, const posix_spawn_file_actions_t *restrict file_actions, const posix_spawnattr_t *restrict attrp, char *const argv[restrict], char *const envp[restrict]) {
    if (PXJBShouldBypassCached() && path && PXJBSpawnPathLooksLikeProbe(path)) {
        PXJBLogBlockedOncePerSecond("posix_spawn", path);
        errno = ENOENT;
        return -1;
    }
    return orig_posix_spawn ? orig_posix_spawn(pid, path, file_actions, attrp, argv, envp) : -1;
}

static int (*orig_posix_spawnp)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const argv[restrict], char *const envp[restrict]);
static int hook_posix_spawnp(pid_t *restrict pid, const char *restrict file, const posix_spawn_file_actions_t *restrict file_actions, const posix_spawnattr_t *restrict attrp, char *const argv[restrict], char *const envp[restrict]) {
    if (PXJBShouldBypassCached() && file && PXJBSpawnPathLooksLikeProbe(file)) {
        PXJBLogBlockedOncePerSecond("posix_spawnp", file);
        errno = ENOENT;
        return -1;
    }
    return orig_posix_spawnp ? orig_posix_spawnp(pid, file, file_actions, attrp, argv, envp) : -1;
}

// Optional strong hook: sandbox_check
static int (*orig_sandbox_check)(pid_t pid, const char *operation, int type, ...);
static int hook_sandbox_check(pid_t pid, const char *operation, int type, ...) {
    if (!orig_sandbox_check) {
        errno = EPERM;
        return -1;
    }

    // We only support the common 1-string-argument patterns.
    const char *arg = NULL;
    va_list ap;
    va_start(ap, type);
    arg = va_arg(ap, const char *);
    va_end(ap);

    if (PXJBHookSandboxCheckEnabled() && operation && arg && arg[0] == '/') {
        // Only gate file-related operations (avoid breaking non-file sandbox queries).
        if (PXHasPrefix(operation, "file-") && PXJBPathShouldHide(arg)) {
            PXJBLogBlockedOncePerSecond("sandbox_check", arg);
            errno = EPERM;
            return -1;
        }
    }

    return orig_sandbox_check(pid, operation, type, arg);
}

// Phase 3: dylib hiding (dyld enumeration + dladdr)
static pthread_mutex_t gDyldLock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t *gVisibleToReal = NULL;
static uint32_t gVisibleCount = 0;
static uint32_t gRealCount = 0;
static CFTimeInterval gDyldLastBuild = 0;

// Declare originals before helpers to avoid implicit declarations.
static uint32_t (*orig__dyld_image_count)(void) = NULL;
static const char *(*orig__dyld_get_image_name)(uint32_t image_index) = NULL;
static const struct mach_header *(*orig__dyld_get_image_header)(uint32_t image_index) = NULL;
static intptr_t (*orig__dyld_get_image_vmaddr_slide)(uint32_t image_index) = NULL;

// Real function pointers captured before hooking, to avoid recursion issues.
static uint32_t (*real__dyld_image_count)(void) = NULL;
static const char *(*real__dyld_get_image_name)(uint32_t image_index) = NULL;
static const struct mach_header *(*real__dyld_get_image_header)(uint32_t image_index) = NULL;
static intptr_t (*real__dyld_get_image_vmaddr_slide)(uint32_t image_index) = NULL;

static uint32_t PXDyldRealImageCount(void) {
    if (real__dyld_image_count) return real__dyld_image_count();
    if (orig__dyld_image_count) return orig__dyld_image_count();
    return 0;
}

static const char *PXDyldRealImageName(uint32_t idx) {
    if (real__dyld_get_image_name) return real__dyld_get_image_name(idx);
    if (orig__dyld_get_image_name) return orig__dyld_get_image_name(idx);
    return NULL;
}

static const struct mach_header *PXDyldRealImageHeader(uint32_t idx) {
    if (real__dyld_get_image_header) return real__dyld_get_image_header(idx);
    if (orig__dyld_get_image_header) return orig__dyld_get_image_header(idx);
    return NULL;
}

static intptr_t PXDyldRealImageSlide(uint32_t idx) {
    if (real__dyld_get_image_vmaddr_slide) return real__dyld_get_image_vmaddr_slide(idx);
    if (orig__dyld_get_image_vmaddr_slide) return orig__dyld_get_image_vmaddr_slide(idx);
    return 0;
}

static BOOL PXStrContainsNoCase(const char *haystack, const char *needle) {
    if (!haystack || !needle) return NO;
    size_t nlen = strlen(needle);
    if (nlen == 0) return YES;

    for (const char *h = haystack; *h; h++) {
        const char *p = h;
        size_t i = 0;
        while (p[i] && i < nlen) {
            char a = p[i];
            char b = needle[i];
            if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
            if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
            if (a != b) break;
            i++;
        }
        if (i == nlen) return YES;
    }
    return NO;
}

static BOOL PXJBShouldHideImageName(const char *name) {
    if (!name) return NO;
    // Substrings frequently used by jailbreak tooling / injection.
    static const char *deny[] = {
        "mobilesubstrate",
        "substrateloader",
        "substratebootstrap",
        "libsubstrate",
        "ellekit",
        "libhooker",
        "rocketbootstrap",
        "frida",
        "fridagadget",
        "cycript",
        "tweakinject",
        "substitute",
        "libblackjack",
        NULL
    };
    for (int i = 0; deny[i]; i++) {
        if (PXStrContainsNoCase(name, deny[i])) return YES;
    }
    // Common rootless prefixes.
    if (PXStrContainsNoCase(name, "/var/jb")) return YES;
    if (PXStrContainsNoCase(name, "/private/preboot/jb")) return YES;
    // Common jailbreak cache-injected dylib pattern.
    if (PXStrContainsNoCase(name, "/library/caches/cy-")) return YES;
    // MobileSubstrate injection path.
    if (PXStrContainsNoCase(name, "/library/mobilesubstrate/")) return YES;
    // mryipc is commonly used by jailbreak ecosystem.
    if (PXStrContainsNoCase(name, "libmryipc")) return YES;
    if (PXStrContainsNoCase(name, "frida")) return YES;
    if (PXStrContainsNoCase(name, "cycript")) return YES;
    if (PXStrContainsNoCase(name, "libjailbreak")) return YES;
    if (PXStrContainsNoCase(name, "preferenceloader")) return YES;
    if (PXStrContainsNoCase(name, "preferencebundles")) return YES;
    return NO;
}

// Phase 3 strong option: hide libproc-based region filename queries
static int (*orig_proc_regionfilename)(int pid, uint64_t address, void *buffer, uint32_t buffersize);
static int hook_proc_regionfilename(int pid, uint64_t address, void *buffer, uint32_t buffersize) {
    if (!orig_proc_regionfilename) return 0;
    int r = orig_proc_regionfilename(pid, address, buffer, buffersize);
    if (r <= 0) return r;
    if (!PXJBHideProcMapsEnabled()) return r;
    if (pid != getpid()) return r;
    if (!buffer || buffersize == 0) return r;

    // Ensure NUL-termination for scanning.
    char *cbuf = (char *)buffer;
    cbuf[buffersize - 1] = '\0';
    if (PXJBShouldHideImageName(cbuf) || PXJBPathShouldHide(cbuf)) {
        cbuf[0] = '\0';
        return 0;
    }
    return r;
}

// Phase 3 strong option: hide ObjC runtime image list
static const char **(*orig_objc_copyImageNames)(unsigned int *outCount);
static const char **hook_objc_copyImageNames(unsigned int *outCount) {
    const char **list = orig_objc_copyImageNames ? orig_objc_copyImageNames(outCount) : NULL;
    if (!PXJBHideObjcImagesEnabled()) {
        return list;
    }
    if (!list || !outCount || *outCount == 0) {
        return list;
    }

    unsigned int inCount = *outCount;
    // Allocate a new list and free the original (caller will free what we return).
    const char **out = (const char **)calloc(inCount + 1, sizeof(char *));
    if (!out) {
        return list;
    }

    unsigned int j = 0;
    for (unsigned int i = 0; i < inCount; i++) {
        const char *nm = list[i];
        if (PXJBShouldHideImageName(nm)) continue;
        out[j++] = nm;
    }
    out[j] = NULL;
    *outCount = j;
    free((void *)list);
    return out;
}

static const char *(*orig_class_getImageName)(Class cls);
static const char *hook_class_getImageName(Class cls) {
    const char *nm = orig_class_getImageName ? orig_class_getImageName(cls) : NULL;
    if (!PXJBHideObjcImagesEnabled()) return nm;
    if (PXJBShouldHideImageName(nm)) return NULL;
    return nm;
}

static BOOL PXJBShouldBlockDlopenPath(const char *path) {
    if (!path || !path[0]) return NO;
    // Block direct probes for common injection/jailbreak libraries.
    static const char *deny[] = {
        "/usr/lib/substrate/",
        "substratebootstrap",
        "mobilesubstrate",
        "substrate",
        "ellekit",
        "libhooker",
        "rocketbootstrap",
        "substitute",
        "frida",
        "/library/caches/cy-",
        NULL
    };
    for (int i = 0; deny[i]; i++) {
        if (PXStrContainsNoCase(path, deny[i])) return YES;
    }
    return NO;
}

static BOOL PXJBShouldBlockDlsymName(const char *sym) {
    if (!sym || !sym[0]) return NO;
    // Only block extremely fingerprintable hooking symbols.
    static const char *deny[] = {
        "MSHookFunction",
        "MSHookMessageEx",
        "MSGetImageByName",
        "MSFindSymbol",
        "EKHook",
        "EKHookFunction",
        "LHHookFunction",
        "SubHookFunction",
        "fishhook_rebind_symbols",
        NULL
    };
    for (int i = 0; deny[i]; i++) {
        if (strcmp(sym, deny[i]) == 0) return YES;
    }
    return NO;
}

// Phase 3 strong option: hide dl_iterate_phdr enumeration
static int (*orig_dl_iterate_phdr)(int (*callback)(struct dl_phdr_info *info, size_t size, void *data), void *data);

typedef struct {
    int (*cb)(struct dl_phdr_info *info, size_t size, void *data);
    void *data;
} PXJBPhdrIterCtx;

static int px_dl_iterate_phdr_cb(struct dl_phdr_info *info, size_t size, void *data) {
    PXJBPhdrIterCtx *ctx = (PXJBPhdrIterCtx *)data;
    if (!ctx || !ctx->cb) return 0;

    if (PXJBHideDlIteratePhdrEnabled() && info) {
        const char *nm = info->dlpi_name;
        if (PXJBShouldHideImageName(nm)) {
            return 0; // skip
        }
    }
    return ctx->cb(info, size, ctx->data);
}

static int hook_dl_iterate_phdr(int (*callback)(struct dl_phdr_info *info, size_t size, void *data), void *data) {
    if (!orig_dl_iterate_phdr) return 0;
    if (!PXJBHideDlIteratePhdrEnabled() || !callback) {
        return orig_dl_iterate_phdr(callback, data);
    }

    PXJBPhdrIterCtx ctx;
    ctx.cb = callback;
    ctx.data = data;
    return orig_dl_iterate_phdr(px_dl_iterate_phdr_cb, &ctx);
}

// Phase 3 strong option: block dlopen/dlsym probes
static void *(*orig_dlopen)(const char *path, int mode);
static void *hook_dlopen(const char *path, int mode) {
    if (PXJBBlockDlopenDlsymProbesEnabled() && path) {
        if (PXJBShouldBlockDlopenPath(path)) {
            errno = ENOENT;
            return NULL;
        }
    }
    return orig_dlopen ? orig_dlopen(path, mode) : NULL;
}

static void *(*orig_dlsym)(void *handle, const char *symbol);
static void *hook_dlsym(void *handle, const char *symbol) {
    if (PXJBBlockDlopenDlsymProbesEnabled() && symbol) {
        if (PXJBShouldBlockDlsymName(symbol)) {
            return NULL;
        }
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : NULL;
}

// Phase 3 strong option: sysctl/sysctlbyname sanitization
static int (*orig_sysctl_jb)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int (*orig_sysctlbyname_jb)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

static void PXJBSanitizeBootArgs(void *oldp, size_t *oldlenp) {
    if (!oldp || !oldlenp || *oldlenp == 0) return;
    char *buf = (char *)oldp;
    size_t n = *oldlenp;
    // Ensure NUL-termination for scanning.
    buf[n - 1] = '\0';
    if (strstr(buf, "checkra1n") || strstr(buf, "cs_enforcement_disable") || strstr(buf, "amfid") || strstr(buf, "jailbreak")) {
        memset(buf, 0, n);
        // Keep it plausible.
        const char *clean = "root_device=md0";
        strncpy(buf, clean, n - 1);
    }
}

static void PXJBSanitizeKinfoProc(void *oldp, size_t *oldlenp) {
    if (!oldp || !oldlenp || *oldlenp == 0) return;
#if __has_include(<sys/user.h>)
    // Clear P_TRACED if present.
#ifndef P_TRACED
#define P_TRACED 0x00000800
#endif
    size_t len = *oldlenp;
    if (len < sizeof(struct kinfo_proc)) return;
    size_t count = len / sizeof(struct kinfo_proc);
    struct kinfo_proc *procs = (struct kinfo_proc *)oldp;
    for (size_t i = 0; i < count; i++) {
        procs[i].kp_proc.p_flag &= ~P_TRACED;
    }
#else
    (void)oldp; (void)oldlenp;
#endif
}

static int hook_sysctl_jb(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int r = orig_sysctl_jb ? orig_sysctl_jb(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (r != 0 || !PXJBSysctlProcSanitizeEnabled()) return r;
    if (!name || namelen < 2) return r;

    if (name[0] == CTL_KERN) {
#ifdef KERN_BOOTARGS
        if (name[1] == KERN_BOOTARGS) {
            PXJBSanitizeBootArgs(oldp, oldlenp);
        }
#endif
        if (name[1] == KERN_PROC) {
            PXJBSanitizeKinfoProc(oldp, oldlenp);
        }
    }
    return r;
}

static int hook_sysctlbyname_jb(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int r = orig_sysctlbyname_jb ? orig_sysctlbyname_jb(name, oldp, oldlenp, newp, newlen) : -1;
    if (r != 0 || !PXJBSysctlProcSanitizeEnabled()) return r;
    if (!name) return r;
    if (strcmp(name, "kern.bootargs") == 0) {
        PXJBSanitizeBootArgs(oldp, oldlenp);
    } else if (strcmp(name, "kern.proc.pid") == 0 || strcmp(name, "kern.proc") == 0) {
        PXJBSanitizeKinfoProc(oldp, oldlenp);
    }
    return r;
}

static void PXDyldRebuildVisibleMapLocked(void) {
    uint32_t count = PXDyldRealImageCount();
    if (count == 0) {
        gRealCount = 0;
        gVisibleCount = 0;
        return;
    }

    if (gVisibleToReal) {
        free(gVisibleToReal);
        gVisibleToReal = NULL;
    }

    gVisibleToReal = (uint32_t *)calloc(count, sizeof(uint32_t));
    if (!gVisibleToReal) {
        gRealCount = count;
        gVisibleCount = count;
        return;
    }

    uint32_t visible = 0;
    for (uint32_t i = 0; i < count; i++) {
        const char *nm = PXDyldRealImageName(i);
        if (PXJBShouldHideImageName(nm)) {
            continue;
        }
        gVisibleToReal[visible++] = i;
    }
    gRealCount = count;
    gVisibleCount = visible;
    gDyldLastBuild = CFAbsoluteTimeGetCurrent();
}

static void PXDyldEnsureVisibleMap(void) {
    if (!PXJBHideDylibsEnabled()) return;

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    // Rebuild at most once per second, or when dyld image count changes.
    uint32_t countNow = PXDyldRealImageCount();

    pthread_mutex_lock(&gDyldLock);
    BOOL needs = (gVisibleToReal == NULL) || (gRealCount != countNow) || ((now - gDyldLastBuild) > 1.0);
    if (needs) {
        PXDyldRebuildVisibleMapLocked();
    }
    pthread_mutex_unlock(&gDyldLock);
}

static uint32_t hook__dyld_image_count(void) {
    uint32_t count = orig__dyld_image_count ? orig__dyld_image_count() : 0;
    if (!PXJBHideDylibsEnabled()) return count;
    PXDyldEnsureVisibleMap();
    pthread_mutex_lock(&gDyldLock);
    uint32_t out = gVisibleToReal ? gVisibleCount : count;
    pthread_mutex_unlock(&gDyldLock);
    return out;
}

static const char *hook__dyld_get_image_name(uint32_t image_index) {
    if (!PXJBHideDylibsEnabled()) {
        return orig__dyld_get_image_name ? orig__dyld_get_image_name(image_index) : NULL;
    }
    PXDyldEnsureVisibleMap();

    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || image_index >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return NULL;
    }
    uint32_t realIndex = gVisibleToReal[image_index];
    pthread_mutex_unlock(&gDyldLock);

    return orig__dyld_get_image_name ? orig__dyld_get_image_name(realIndex) : NULL;
}

static const struct mach_header *hook__dyld_get_image_header(uint32_t image_index) {
    if (!PXJBHideDylibsEnabled()) {
        return orig__dyld_get_image_header ? orig__dyld_get_image_header(image_index) : NULL;
    }
    PXDyldEnsureVisibleMap();

    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || image_index >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return NULL;
    }
    uint32_t realIndex = gVisibleToReal[image_index];
    pthread_mutex_unlock(&gDyldLock);

    return orig__dyld_get_image_header ? orig__dyld_get_image_header(realIndex) : NULL;
}

static intptr_t hook__dyld_get_image_vmaddr_slide(uint32_t image_index) {
    if (!PXJBHideDylibsEnabled()) {
        return orig__dyld_get_image_vmaddr_slide ? orig__dyld_get_image_vmaddr_slide(image_index) : 0;
    }
    PXDyldEnsureVisibleMap();

    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || image_index >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return 0;
    }
    uint32_t realIndex = gVisibleToReal[image_index];
    pthread_mutex_unlock(&gDyldLock);

    return orig__dyld_get_image_vmaddr_slide ? orig__dyld_get_image_vmaddr_slide(realIndex) : 0;
}

static int (*orig_dladdr)(const void *addr, Dl_info *info);
static int hook_dladdr(const void *addr, Dl_info *info) {
    int r = orig_dladdr ? orig_dladdr(addr, info) : 0;
    if (r == 0 || !info) return r;
    if (!PXJBHideDylibsEnabled()) return r;
    if (info->dli_fname && PXJBShouldHideImageName(info->dli_fname)) {
        // Fail lookup so callers can't attribute symbols to jailbreak dylibs.
        return 0;
    }
    return r;
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

%hook NSProcessInfo

- (NSDictionary<NSString *, NSString *> *)environment {
    NSDictionary *env = %orig;
    if (!PXJBShouldBypassCached()) return env;
    if (![env isKindOfClass:[NSDictionary class]] || env.count == 0) return env;

    NSMutableDictionary *out = [env mutableCopy];
    NSArray<NSString *> *deny = @[
        @"DYLD_INSERT_LIBRARIES",
        @"DYLD_LIBRARY_PATH",
        @"DYLD_FRAMEWORK_PATH",
        @"DYLD_FALLBACK_LIBRARY_PATH",
        @"DYLD_FALLBACK_FRAMEWORK_PATH",
        @"DYLD_ROOT_PATH",
        @"DYLD_SHARED_CACHE_DIR",
        @"DYLD_PRINT_TO_FILE",
        @"DYLD_PRINT_LIBRARIES",
        @"DYLD_PRINT_APIS",
        @"DYLD_PRINT_OPTS",
        @"DYLD_PRINT_ENV",
        @"LD_PRELOAD",
        @"_MSSafeMode",
        @"MSDebug",
        @"JB_SANDBOX_EXTENSIONS",
        @"SHELL"
    ];
    [out removeObjectsForKeys:deny];
    return [out copy];
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
                [scheme isEqualToString:@"filza"] ||
                [scheme isEqualToString:@"undecimus"] ||
                [scheme isEqualToString:@"checkra1n"] ||
                [scheme isEqualToString:@"odyssey"] ||
                [scheme isEqualToString:@"taurine"] ||
                [scheme isEqualToString:@"electra"]) {
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

        // Install-time toggles (take effect after app relaunch).
        NSUserDefaults *ss = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        BOOL wantSyscallHook = [ss boolForKey:@"jbBypassHookSyscallFallbackEnabled"]; // experimental
        BOOL wantDyldHide = [ss boolForKey:@"jbBypassHideDylibsEnabled"]; // experimental
        BOOL wantBlockAddImage = [ss boolForKey:@"jbBypassBlockDyldAddImageCallbacksEnabled"]; // experimental
        BOOL wantHideTaskDyldInfo = [ss boolForKey:@"jbBypassHideTaskDyldInfoEnabled"]; // experimental
        BOOL wantHideDlIteratePhdr = [ss boolForKey:@"jbBypassHideDlIteratePhdrEnabled"]; // experimental
        BOOL wantBlockDlopenDlsym = [ss boolForKey:@"jbBypassBlockDlopenDlsymProbesEnabled"]; // experimental
        BOOL wantSysctlSanitize = [ss boolForKey:@"jbBypassSysctlProcSanitizeEnabled"]; // experimental
        BOOL wantHideProcMaps = [ss boolForKey:@"jbBypassHideProcMapsEnabled"]; // experimental
        BOOL wantHideObjcImages = [ss boolForKey:@"jbBypassHideObjcImagesEnabled"]; // experimental
        BOOL wantSandboxCheck = [ss boolForKey:@"jbBypassHookSandboxCheckEnabled"]; // experimental
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

            if (wantSyscallHook) {
                sym = FindSymbol(NULL, "syscall");
                if (sym) MSHookFunction(sym, (void *)hook_syscall, (void **)&orig_syscall);
            }

            sym = FindSymbol(NULL, "system");
            if (sym) MSHookFunction(sym, (void *)hook_system, (void **)&orig_system);

            sym = FindSymbol(NULL, "popen");
            if (sym) MSHookFunction(sym, (void *)hook_popen, (void **)&orig_popen);

            // Block probe spawns (safe default; gate inside hook).
            sym = FindSymbol(NULL, "posix_spawn");
            if (sym) MSHookFunction(sym, (void *)hook_posix_spawn, (void **)&orig_posix_spawn);

            sym = FindSymbol(NULL, "posix_spawnp");
            if (sym) MSHookFunction(sym, (void *)hook_posix_spawnp, (void **)&orig_posix_spawnp);

            // Optional: sandbox_check hook (default OFF)
            if (wantSandboxCheck) {
                sym = FindSymbol(NULL, "sandbox_check");
                if (sym) MSHookFunction(sym, (void *)hook_sandbox_check, (void **)&orig_sandbox_check);
            }

            // Phase 2 extension (toggle: jbBypassStatfsEnabled)
            sym = FindSymbol(NULL, "statfs");
            if (sym) MSHookFunction(sym, (void *)hook_statfs, (void **)&orig_statfs);

            sym = FindSymbol(NULL, "fstatfs");
            if (sym) MSHookFunction(sym, (void *)hook_fstatfs, (void **)&orig_fstatfs);

            sym = FindSymbol(NULL, "statvfs");
            if (sym) MSHookFunction(sym, (void *)hook_statvfs, (void **)&orig_statvfs);

            sym = FindSymbol(NULL, "fstatvfs");
            if (sym) MSHookFunction(sym, (void *)hook_fstatvfs, (void **)&orig_fstatvfs);

            // Phase 3 (toggle: jbBypassHideDylibsEnabled). Install only when explicitly enabled.
            if (wantDyldHide) {
                sym = FindSymbol(NULL, "_dyld_image_count");
                if (sym) {
                    if (!real__dyld_image_count) {
                        real__dyld_image_count = (uint32_t (*)(void))sym;
                    }
                    MSHookFunction(sym, (void *)hook__dyld_image_count, (void **)&orig__dyld_image_count);
                }

                sym = FindSymbol(NULL, "_dyld_get_image_name");
                if (sym) {
                    if (!real__dyld_get_image_name) {
                        real__dyld_get_image_name = (const char *(*)(uint32_t))sym;
                    }
                    MSHookFunction(sym, (void *)hook__dyld_get_image_name, (void **)&orig__dyld_get_image_name);
                }

                sym = FindSymbol(NULL, "_dyld_get_image_header");
                if (sym) {
                    if (!real__dyld_get_image_header) {
                        real__dyld_get_image_header = (const struct mach_header *(*)(uint32_t))sym;
                    }
                    MSHookFunction(sym, (void *)hook__dyld_get_image_header, (void **)&orig__dyld_get_image_header);
                }

                sym = FindSymbol(NULL, "_dyld_get_image_vmaddr_slide");
                if (sym) {
                    if (!real__dyld_get_image_vmaddr_slide) {
                        real__dyld_get_image_vmaddr_slide = (intptr_t (*)(uint32_t))sym;
                    }
                    MSHookFunction(sym, (void *)hook__dyld_get_image_vmaddr_slide, (void **)&orig__dyld_get_image_vmaddr_slide);
                }

                sym = FindSymbol(NULL, "dladdr");
                if (sym) MSHookFunction(sym, (void *)hook_dladdr, (void **)&orig_dladdr);
            }

            // Phase 3 extension: block suspicious add_image callback registrations.
            if (wantBlockAddImage) {
                // _dyld_register_func_for_add_image is in libdyld/dyld; dlsym RTLD_DEFAULT works.
                sym = FindSymbol(NULL, "_dyld_register_func_for_add_image");
                if (sym) {
                    // See hook implementation below (near dyld helpers).
                    extern void PXJBInstallDyldAddImageBlocker(void *sym);
                    PXJBInstallDyldAddImageBlocker(sym);
                }
            }

            // Phase 3 extension: hide TASK_DYLD_INFO via task_info.
            if (wantHideTaskDyldInfo) {
                sym = FindSymbol(NULL, "task_info");
                if (sym) {
                    extern void PXJBInstallTaskInfoHook(void *sym);
                    PXJBInstallTaskInfoHook(sym);
                }
            }

            // Phase 3 extension: hide dl_iterate_phdr enumeration.
            if (wantHideDlIteratePhdr) {
                sym = FindSymbol(NULL, "dl_iterate_phdr");
                if (sym) {
                    MSHookFunction(sym, (void *)hook_dl_iterate_phdr, (void **)&orig_dl_iterate_phdr);
                }
            }

            // Phase 4: block dlopen/dlsym probes.
            if (wantBlockDlopenDlsym) {
                sym = FindSymbol(NULL, "dlopen");
                if (sym) MSHookFunction(sym, (void *)hook_dlopen, (void **)&orig_dlopen);
                sym = FindSymbol(NULL, "dlsym");
                if (sym) MSHookFunction(sym, (void *)hook_dlsym, (void **)&orig_dlsym);
            }

            // Phase 5: sysctl/sysctlbyname sanitize.
            if (wantSysctlSanitize) {
                sym = FindSymbol(NULL, "sysctl");
                if (sym) MSHookFunction(sym, (void *)hook_sysctl_jb, (void **)&orig_sysctl_jb);
                sym = FindSymbol(NULL, "sysctlbyname");
                if (sym) MSHookFunction(sym, (void *)hook_sysctlbyname_jb, (void **)&orig_sysctlbyname_jb);
            }

            // Phase 6: hide proc map filenames (libproc).
            if (wantHideProcMaps) {
                sym = FindSymbol(NULL, "proc_regionfilename");
                if (sym) {
                    MSHookFunction(sym, (void *)hook_proc_regionfilename, (void **)&orig_proc_regionfilename);
                }
            }

            // Phase 7: hide ObjC runtime image list.
            if (wantHideObjcImages) {
                sym = FindSymbol(NULL, "objc_copyImageNames");
                if (sym) {
                    MSHookFunction(sym, (void *)hook_objc_copyImageNames, (void **)&orig_objc_copyImageNames);
                }
                sym = FindSymbol(NULL, "class_getImageName");
                if (sym) {
                    MSHookFunction(sym, (void *)hook_class_getImageName, (void **)&orig_class_getImageName);
                }
            }

            dlclose(libSystem);
        }

        %init;

        // Proactive env cleanup (safe) for scoped apps.
        PXJBUnsetSuspiciousEnvIfNeeded();
        dispatch_async(dispatch_get_main_queue(), ^{
            PXJBUnsetSuspiciousEnvIfNeeded();
        });
        PXLog(@"[JailbreakBypass] Phase 1 hooks initialized");
    }
}

// --- Optional strong hooks (installed only when toggle is enabled at launch) ---
static void (*orig__dyld_register_func_for_add_image)(void (*func)(const struct mach_header *, intptr_t));
static void hook__dyld_register_func_for_add_image(void (*func)(const struct mach_header *, intptr_t)) {
    if (!orig__dyld_register_func_for_add_image) return;
    if (!PXJBBlockDyldAddImageCallbacksEnabled() || !func) {
        orig__dyld_register_func_for_add_image(func);
        return;
    }
    Dl_info info;
    if (dladdr((const void *)func, &info) && info.dli_fname) {
        if (PXJBShouldHideImageName(info.dli_fname)) {
            return;
        }
    }
    orig__dyld_register_func_for_add_image(func);
}

void PXJBInstallDyldAddImageBlocker(void *sym) {
    if (!sym) return;
    MSHookFunction(sym, (void *)hook__dyld_register_func_for_add_image, (void **)&orig__dyld_register_func_for_add_image);
}

static kern_return_t (*orig_task_info)(task_t, task_flavor_t, task_info_t, mach_msg_type_number_t *);
static kern_return_t hook_task_info(task_t target_task, task_flavor_t flavor, task_info_t task_info_out, mach_msg_type_number_t *task_info_outCnt) {
    if (!orig_task_info) return KERN_INVALID_ARGUMENT;
    if (!PXJBHideTaskDyldInfoEnabled()) {
        return orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);
    }
    if (target_task != mach_task_self()) {
        return orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);
    }
#ifdef TASK_DYLD_INFO
    if (flavor == TASK_DYLD_INFO) {
        if (task_info_outCnt) *task_info_outCnt = 0;
        return KERN_INVALID_ARGUMENT;
    }
#endif
    return orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);
}

void PXJBInstallTaskInfoHook(void *sym) {
    if (!sym) return;
    MSHookFunction(sym, (void *)hook_task_info, (void **)&orig_task_info);
}
