// MBBankMinimalInit.x
// Minimal, Foundation-free init for MB Bank (com.mbmobile).
// Goal: keep process stable during early init and only hide obvious jailbreak/injection indicators.

#import <substrate.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <dirent.h>

#include <mach-o/dyld.h>
#include <mach/mach.h>
#if __has_include(<mach/task_info.h>)
#include <mach/task_info.h>
#endif
#if __has_include(<mach/mach_vm.h>)
#include <mach/mach_vm.h>
#endif
#if __has_include(<mach-o/dyld_images.h>)
#include <mach-o/dyld_images.h>
#endif

#import <objc/runtime.h>

// Some Theos SDKs don't ship <link.h>
struct dl_phdr_info {
    uintptr_t dlpi_addr;
    const char *dlpi_name;
    const void *dlpi_phdr;
    unsigned short dlpi_phnum;
};

static inline bool PXIsMBBankProcess(void) {
    extern const char *__progname;
    return (__progname && strcmp(__progname, "MB Bank") == 0);
}

static bool PXCharEqNoCase(char a, char b) {
    if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
    if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
    return a == b;
}

static bool PXStrContainsNoCaseC(const char *haystack, const char *needle) {
    if (!haystack || !needle) return false;
    size_t nlen = strlen(needle);
    if (nlen == 0) return true;

    for (const char *h = haystack; *h; h++) {
        size_t i = 0;
        while (needle[i] && h[i] && PXCharEqNoCase(h[i], needle[i])) {
            i++;
        }
        if (i == nlen) return true;
    }
    return false;
}

static bool PXShouldHidePathOrImage(const char *s) {
    if (!s || !s[0]) return false;
    // Keep list broad enough for RASP, but avoid false positives by using path-ish needles.
    static const char *deny[] = {
        "/library/mobilesubstrate/",
        "/usr/lib/substrate/",
        "/library/caches/cy-",
        "substratebootstrap",
        "subtratebootstrap",
        "mobilesubstrate",
        "substitute",
        "ellekit",
        "libhooker",
        "rocketbootstrap",
        "frida",
        "cycript",
        "libmryipc",
        "0cr4shed",
        NULL
    };
    for (int i = 0; deny[i]; i++) {
        if (PXStrContainsNoCaseC(s, deny[i])) return true;
    }
    return false;
}

static bool PXIsRaspCaller(void *retAddr) {
    if (!retAddr) return false;
    Dl_info info;
    if (!dladdr(retAddr, &info) || !info.dli_fname) return false;
    const char *f = info.dli_fname;
    if (PXStrContainsNoCaseC(f, "/vguard.framework/")) return true;
    if (PXStrContainsNoCaseC(f, "/zdefend")) return true;
    if (PXStrContainsNoCaseC(f, "mbraspsdk")) return true;
    if (PXStrContainsNoCaseC(f, "vosintegrity")) return true;
    return false;
}

// --- Safe file logger (no Foundation) ---
static void PXWriteLine(const char *line) {
    if (!line) return;
    int fd = open("/tmp/projectx_mbbank_minimal.log", O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) return;
    (void)write(fd, line, strlen(line));
    (void)write(fd, "\n", 1);
    (void)close(fd);
}

static void PXWriteLineKV(const char *k, const char *v) {
    char buf[512];
    if (!k) k = "(null)";
    if (!v) v = "(null)";
    (void)snprintf(buf, sizeof(buf), "%s: %s", k, v);
    PXWriteLine(buf);
}

static int PXReadMode(void) {
    // 0: fs+objc+proc only (default)
    // 1: +dl_iterate_phdr
    // 2: +_dyld_* enumeration
    // 3: +dlopen/dlsym
    // 4: +anti-terminate
    const char *path = "/tmp/projectx_mbbank_mode";
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    char buf[32];
    ssize_t n = read(fd, buf, (sizeof(buf) - 1));
    close(fd);
    if (n <= 0) return 0;
    buf[n] = '\0';
    // Parse int
    int v = atoi(buf);
    // -3: hook task_info(TASK_DYLD_INFO) sanitize only
    // -2: install nothing (injection-only test)
    // -1: patch pthread_mach_thread_np only
    if (v < -3) v = -3;
    if (v > 4) v = 4;
    return v;
}

// Patch for protected apps that crash inside dyld stubs for pthread_mach_thread_np.
static mach_port_t (*orig_pthread_mach_thread_np)(pthread_t thread);
static mach_port_t hook_pthread_mach_thread_np(pthread_t thread) {
    (void)thread;
    // Avoid calling the original: in the failing case, the stub itself traps.
    return mach_thread_self();
}

// --- dyld_all_image_infos sanitization via task_info(TASK_DYLD_INFO) ---
static kern_return_t (*orig_task_info)(task_t, task_flavor_t, task_info_t, mach_msg_type_number_t *);
static const struct dyld_all_image_infos *(*orig__dyld_get_all_image_infos)(void);

static const struct dyld_all_image_infos *gSanitizedInfos = NULL;
static struct dyld_image_info *gSanitizedImages = NULL;
static uint32_t gSanitizedCount = 0;
static const struct dyld_image_info *gLastSrcArray = NULL;
static uint32_t gLastSrcCount = 0;

static bool PXShouldHideSubstrateCyOnly(const char *path) {
    if (!path || !path[0]) return false;
    // Keep narrow to substrate/cy as requested.
    if (PXStrContainsNoCaseC(path, "/usr/lib/substrate/")) return true;
    if (PXStrContainsNoCaseC(path, "/library/caches/cy-")) return true;
    if (PXStrContainsNoCaseC(path, "substrateinserter")) return true;
    if (PXStrContainsNoCaseC(path, "substratebootstrap")) return true;
    if (PXStrContainsNoCaseC(path, "substrateloader")) return true;
    if (PXStrContainsNoCaseC(path, "libsubstrate")) return true;
    // Some caches embed the cy- token without full path.
    if (PXStrContainsNoCaseC(path, "cy-")) return true;
    return false;
}

static const struct dyld_all_image_infos *PXBuildSanitizedInfos(const struct dyld_all_image_infos *src) {
    if (!src) return NULL;
    const struct dyld_image_info *arr = src->infoArray;
    uint32_t cnt = (uint32_t)src->infoArrayCount;
    if (!arr || cnt == 0) return src;

    if (gSanitizedInfos && gSanitizedImages && gLastSrcArray == arr && gLastSrcCount == cnt) {
        return gSanitizedInfos;
    }

    // Free previous cache.
    if (gSanitizedInfos) {
        free((void *)gSanitizedInfos);
        gSanitizedInfos = NULL;
    }
    if (gSanitizedImages) {
        free(gSanitizedImages);
        gSanitizedImages = NULL;
    }
    gSanitizedCount = 0;

    struct dyld_image_info *filtered = (struct dyld_image_info *)calloc(cnt, sizeof(struct dyld_image_info));
    if (!filtered) return src;

    uint32_t j = 0;
    for (uint32_t i = 0; i < cnt; i++) {
        const char *p = (const char *)arr[i].imageFilePath;
        if (PXShouldHideSubstrateCyOnly(p)) continue;
        filtered[j++] = arr[i];
    }

    struct dyld_all_image_infos *copy = (struct dyld_all_image_infos *)malloc(sizeof(struct dyld_all_image_infos));
    if (!copy) {
        free(filtered);
        return src;
    }
    memcpy(copy, src, sizeof(struct dyld_all_image_infos));
    copy->infoArray = filtered;
    copy->infoArrayCount = j;

    gSanitizedInfos = copy;
    gSanitizedImages = filtered;
    gSanitizedCount = j;
    gLastSrcArray = arr;
    gLastSrcCount = cnt;

    return gSanitizedInfos;
}

static kern_return_t hook_task_info(task_t target_task, task_flavor_t flavor, task_info_t task_info_out, mach_msg_type_number_t *task_info_outCnt) {
    if (!orig_task_info) return KERN_INVALID_ARGUMENT;
    kern_return_t kr = orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);
    if (kr != KERN_SUCCESS) return kr;

    if (target_task != mach_task_self()) return kr;
#ifdef TASK_DYLD_INFO
    if (flavor != TASK_DYLD_INFO) return kr;
#else
    return kr;
#endif

    if (!task_info_out || !task_info_outCnt) return kr;
    if (*task_info_outCnt < TASK_DYLD_INFO_COUNT) return kr;

    task_dyld_info_data_t *dyldInfo = (task_dyld_info_data_t *)task_info_out;
    const struct dyld_all_image_infos *src = (const struct dyld_all_image_infos *)(uintptr_t)dyldInfo->all_image_info_addr;
    const struct dyld_all_image_infos *san = PXBuildSanitizedInfos(src);
    if (san) {
        // Log caller + before/after counts (best-effort).
        void *ret = __builtin_return_address(0);
        Dl_info di;
        const char *caller = NULL;
        if (dladdr(ret, &di) && di.dli_fname) caller = di.dli_fname;
        char buf[512];
        uint32_t before = src ? (uint32_t)src->infoArrayCount : 0;
        uint32_t after = (uint32_t)san->infoArrayCount;
        (void)snprintf(buf, sizeof(buf), "TASK_DYLD_INFO caller=%s before=%u after=%u", caller ? caller : "(null)", before, after);
        PXWriteLine(buf);

        dyldInfo->all_image_info_addr = (mach_vm_address_t)(uintptr_t)san;
        // Keep size unchanged to reduce suspicion.
    }
    return kr;
}

static const struct dyld_all_image_infos *hook__dyld_get_all_image_infos(void) {
    const struct dyld_all_image_infos *src = orig__dyld_get_all_image_infos ? orig__dyld_get_all_image_infos() : NULL;
    const struct dyld_all_image_infos *san = PXBuildSanitizedInfos(src);
    return san ? san : src;
}

// --- libc file probes ---
static int (*orig_stat)(const char *, struct stat *);
static int hook_stat(const char *path, struct stat *st) {
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat ? orig_stat(path, st) : -1;
}

static int (*orig_lstat)(const char *, struct stat *);
static int hook_lstat(const char *path, struct stat *st) {
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat ? orig_lstat(path, st) : -1;
}

static int (*orig_access)(const char *, int);
static int hook_access(const char *path, int mode) {
    (void)mode;
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access ? orig_access(path, mode) : -1;
}

static int (*orig_open)(const char *, int, ...);
static int hook_open(const char *path, int flags, ...) {
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return -1;
    }
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return orig_open ? orig_open(path, flags, mode) : -1;
    }
    return orig_open ? orig_open(path, flags) : -1;
}

static int (*orig_openat)(int, const char *, int, ...);
static int hook_openat(int fd, const char *path, int flags, ...) {
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return -1;
    }
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return orig_openat ? orig_openat(fd, path, flags, mode) : -1;
    }
    return orig_openat ? orig_openat(fd, path, flags) : -1;
}

static DIR *(*orig_opendir)(const char *);
static DIR *hook_opendir(const char *path) {
    if (PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return NULL;
    }
    return orig_opendir ? orig_opendir(path) : NULL;
}

// --- dyld enumeration ---
static uint32_t (*orig__dyld_image_count)(void);
static const char *(*orig__dyld_get_image_name)(uint32_t);
static const struct mach_header *(*orig__dyld_get_image_header)(uint32_t);
static intptr_t (*orig__dyld_get_image_vmaddr_slide)(uint32_t);

static pthread_mutex_t gDyldLock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t *gVisibleToReal = NULL;
static uint32_t gVisibleCount = 0;
static uint32_t gRealCount = 0;

static void PXDyldRebuild(void) {
    if (!orig__dyld_image_count || !orig__dyld_get_image_name) return;
    uint32_t real = orig__dyld_image_count();
    if (gVisibleToReal && gRealCount == real) return;

    pthread_mutex_lock(&gDyldLock);
    if (gVisibleToReal) {
        free(gVisibleToReal);
        gVisibleToReal = NULL;
    }
    gRealCount = real;
    gVisibleToReal = (uint32_t *)calloc(real ? real : 1, sizeof(uint32_t));
    if (!gVisibleToReal) {
        gVisibleCount = real;
        pthread_mutex_unlock(&gDyldLock);
        return;
    }
    uint32_t v = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *nm = orig__dyld_get_image_name(i);
        if (PXShouldHidePathOrImage(nm)) continue;
        gVisibleToReal[v++] = i;
    }
    gVisibleCount = v;
    pthread_mutex_unlock(&gDyldLock);
}

static uint32_t hook__dyld_image_count(void) {
    PXDyldRebuild();
    pthread_mutex_lock(&gDyldLock);
    uint32_t c = gVisibleToReal ? gVisibleCount : (orig__dyld_image_count ? orig__dyld_image_count() : 0);
    pthread_mutex_unlock(&gDyldLock);
    return c;
}

static const char *hook__dyld_get_image_name(uint32_t idx) {
    PXDyldRebuild();
    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || idx >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return NULL;
    }
    uint32_t real = gVisibleToReal[idx];
    pthread_mutex_unlock(&gDyldLock);
    return orig__dyld_get_image_name ? orig__dyld_get_image_name(real) : NULL;
}

static const struct mach_header *hook__dyld_get_image_header(uint32_t idx) {
    PXDyldRebuild();
    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || idx >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return NULL;
    }
    uint32_t real = gVisibleToReal[idx];
    pthread_mutex_unlock(&gDyldLock);
    return orig__dyld_get_image_header ? orig__dyld_get_image_header(real) : NULL;
}

static intptr_t hook__dyld_get_image_vmaddr_slide(uint32_t idx) {
    PXDyldRebuild();
    pthread_mutex_lock(&gDyldLock);
    if (!gVisibleToReal || idx >= gVisibleCount) {
        pthread_mutex_unlock(&gDyldLock);
        return 0;
    }
    uint32_t real = gVisibleToReal[idx];
    pthread_mutex_unlock(&gDyldLock);
    return orig__dyld_get_image_vmaddr_slide ? orig__dyld_get_image_vmaddr_slide(real) : 0;
}

// dl_iterate_phdr
static int (*orig_dl_iterate_phdr)(int (*callback)(struct dl_phdr_info *info, size_t size, void *data), void *data);
typedef struct {
    int (*cb)(struct dl_phdr_info *info, size_t size, void *data);
    void *data;
} PXPhdrCtx;

static int PXPhdrWrapper(struct dl_phdr_info *info, size_t size, void *data) {
    PXPhdrCtx *ctx = (PXPhdrCtx *)data;
    if (!ctx || !ctx->cb) return 0;
    if (info && PXShouldHidePathOrImage(info->dlpi_name)) {
        return 0;
    }
    return ctx->cb(info, size, ctx->data);
}

static int hook_dl_iterate_phdr(int (*callback)(struct dl_phdr_info *info, size_t size, void *data), void *data) {
    if (!orig_dl_iterate_phdr || !callback) return 0;
    PXPhdrCtx ctx;
    ctx.cb = callback;
    ctx.data = data;
    return orig_dl_iterate_phdr(PXPhdrWrapper, &ctx);
}

// ObjC runtime images
static const char **(*orig_objc_copyImageNames)(unsigned int *outCount);
static const char **hook_objc_copyImageNames(unsigned int *outCount) {
    const char **list = orig_objc_copyImageNames ? orig_objc_copyImageNames(outCount) : NULL;
    if (!list || !outCount || *outCount == 0) return list;
    unsigned int inCount = *outCount;
    const char **out = (const char **)calloc(inCount + 1, sizeof(char *));
    if (!out) return list;
    unsigned int j = 0;
    for (unsigned int i = 0; i < inCount; i++) {
        const char *nm = list[i];
        if (PXShouldHidePathOrImage(nm)) continue;
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
    if (PXShouldHidePathOrImage(nm)) return NULL;
    return nm;
}

// libproc region filename
static int (*orig_proc_regionfilename)(int pid, uint64_t address, void *buffer, uint32_t buffersize);
static int hook_proc_regionfilename(int pid, uint64_t address, void *buffer, uint32_t buffersize) {
    if (!orig_proc_regionfilename) return 0;
    int r = orig_proc_regionfilename(pid, address, buffer, buffersize);
    if (r <= 0 || !buffer || buffersize == 0) return r;
    char *cbuf = (char *)buffer;
    cbuf[buffersize - 1] = '\0';
    if (PXShouldHidePathOrImage(cbuf)) {
        cbuf[0] = '\0';
        return 0;
    }
    return r;
}

// dlopen/dlsym probes
static void *(*orig_dlopen)(const char *, int);
static void *hook_dlopen(const char *path, int mode) {
    if (path && PXShouldHidePathOrImage(path)) {
        errno = ENOENT;
        return NULL;
    }
    return orig_dlopen ? orig_dlopen(path, mode) : NULL;
}

static void *(*orig_dlsym)(void *, const char *);
static void *hook_dlsym(void *handle, const char *symbol) {
    (void)handle;
    if (symbol) {
        // Fingerprintable hooking symbols
        static const char *deny[] = {
            "MSHookFunction",
            "MSHookMessageEx",
            "EKHook",
            "LHHookFunction",
            NULL
        };
        for (int i = 0; deny[i]; i++) {
            if (strcmp(symbol, deny[i]) == 0) {
                return NULL;
            }
        }
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : NULL;
}

// Anti-terminate (block only when caller is RASP)
static void (*orig_abort)(void);
static void hook_abort(void) {
    void *ret = __builtin_return_address(0);
    if (PXIsRaspCaller(ret)) {
        return;
    }
    if (orig_abort) orig_abort();
}

static int (*orig_raise)(int);
static int hook_raise(int sig) {
    if ((sig == SIGABRT || sig == SIGTERM) && PXIsRaspCaller(__builtin_return_address(0))) {
        return 0;
    }
    return orig_raise ? orig_raise(sig) : -1;
}

static int (*orig_pthread_kill)(pthread_t, int);
static int hook_pthread_kill(pthread_t t, int sig) {
    if (sig == SIGABRT && PXIsRaspCaller(__builtin_return_address(0))) {
        return 0;
    }
    return orig_pthread_kill ? orig_pthread_kill(t, sig) : -1;
}

static void (*orig_exit)(int);
static void hook_exit(int status) {
    if (status != 0 && PXIsRaspCaller(__builtin_return_address(0))) {
        return;
    }
    if (orig_exit) orig_exit(status);
}

static void (*orig__exit)(int);
static void hook__exit(int status) {
    if (status != 0 && PXIsRaspCaller(__builtin_return_address(0))) {
        return;
    }
    if (orig__exit) orig__exit(status);
}

__attribute__((constructor(101)))
static void PXInstallMBBankMinimal(void) {
    if (!PXIsMBBankProcess()) return;

    PXWriteLine("[ProjectX] MBBankMinimalInit v3 begin");
    int mode = PXReadMode();
    char modeBuf[32];
    (void)snprintf(modeBuf, sizeof(modeBuf), "%d", mode);
    PXWriteLineKV("mode", modeBuf);

    if (mode == -2) {
        PXWriteLine("mode -2: no hooks installed");
        PXWriteLine("[ProjectX] MBBankMinimalInit v3 installed");
        return;
    }

    // Install hooks via RTLD_DEFAULT (symbols are in process images)
    void *sym = NULL;

    // Optional: sanitize TASK_DYLD_INFO very early. This is the main bypass for die-on-injection.
    if (mode == -3 || mode >= 0) {
        PXWriteLine("install task_info(TASK_DYLD_INFO) sanitizer");
        sym = dlsym(RTLD_DEFAULT, "task_info");
        if (sym) {
            MSHookFunction(sym, (void *)hook_task_info, (void **)&orig_task_info);
        } else {
            PXWriteLine("task_info symbol not found");
        }

        sym = dlsym(RTLD_DEFAULT, "_dyld_get_all_image_infos");
        if (sym) {
            MSHookFunction(sym, (void *)hook__dyld_get_all_image_infos, (void **)&orig__dyld_get_all_image_infos);
            PXWriteLine("hooked _dyld_get_all_image_infos");
        }
    }

    if (mode == -3) {
        PXWriteLine("mode -3: task_info sanitizer only");
        PXWriteLine("[ProjectX] MBBankMinimalInit v3 installed");
        return;
    }

    if (mode == -1) {
        PXWriteLine("mode -1: patch pthread_mach_thread_np only");
        sym = dlsym(RTLD_DEFAULT, "pthread_mach_thread_np");
        if (sym) {
            MSHookFunction(sym, (void *)hook_pthread_mach_thread_np, (void **)&orig_pthread_mach_thread_np);
            PXWriteLine("installed pthread_mach_thread_np patch");
        } else {
            PXWriteLine("pthread_mach_thread_np symbol not found");
        }
        PXWriteLine("[ProjectX] MBBankMinimalInit v3 installed");
        return;
    }

    PXWriteLine("install stat");
    sym = dlsym(RTLD_DEFAULT, "stat");
    if (sym) MSHookFunction(sym, (void *)hook_stat, (void **)&orig_stat);
    PXWriteLine("install lstat");
    sym = dlsym(RTLD_DEFAULT, "lstat");
    if (sym) MSHookFunction(sym, (void *)hook_lstat, (void **)&orig_lstat);
    PXWriteLine("install access");
    sym = dlsym(RTLD_DEFAULT, "access");
    if (sym) MSHookFunction(sym, (void *)hook_access, (void **)&orig_access);
    PXWriteLine("install open");
    sym = dlsym(RTLD_DEFAULT, "open");
    if (sym) MSHookFunction(sym, (void *)hook_open, (void **)&orig_open);
    PXWriteLine("install openat");
    sym = dlsym(RTLD_DEFAULT, "openat");
    if (sym) MSHookFunction(sym, (void *)hook_openat, (void **)&orig_openat);
    PXWriteLine("install opendir");
    sym = dlsym(RTLD_DEFAULT, "opendir");
    if (sym) MSHookFunction(sym, (void *)hook_opendir, (void **)&orig_opendir);

    if (mode >= 1) {
        PXWriteLine("install dl_iterate_phdr");
        sym = dlsym(RTLD_DEFAULT, "dl_iterate_phdr");
        if (sym) MSHookFunction(sym, (void *)hook_dl_iterate_phdr, (void **)&orig_dl_iterate_phdr);
    } else {
        PXWriteLine("skip dl_iterate_phdr");
    }

    if (mode >= 2) {
        PXWriteLine("install _dyld_* hooks");
        sym = dlsym(RTLD_DEFAULT, "_dyld_image_count");
        if (sym) MSHookFunction(sym, (void *)hook__dyld_image_count, (void **)&orig__dyld_image_count);
        sym = dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
        if (sym) MSHookFunction(sym, (void *)hook__dyld_get_image_name, (void **)&orig__dyld_get_image_name);
        sym = dlsym(RTLD_DEFAULT, "_dyld_get_image_header");
        if (sym) MSHookFunction(sym, (void *)hook__dyld_get_image_header, (void **)&orig__dyld_get_image_header);
        sym = dlsym(RTLD_DEFAULT, "_dyld_get_image_vmaddr_slide");
        if (sym) MSHookFunction(sym, (void *)hook__dyld_get_image_vmaddr_slide, (void **)&orig__dyld_get_image_vmaddr_slide);
    } else {
        PXWriteLine("skip _dyld_* hooks");
    }

    // ObjC runtime images
    PXWriteLine("install objc_copyImageNames");
    sym = dlsym(RTLD_DEFAULT, "objc_copyImageNames");
    if (sym) MSHookFunction(sym, (void *)hook_objc_copyImageNames, (void **)&orig_objc_copyImageNames);
    PXWriteLine("install class_getImageName");
    sym = dlsym(RTLD_DEFAULT, "class_getImageName");
    if (sym) MSHookFunction(sym, (void *)hook_class_getImageName, (void **)&orig_class_getImageName);

    // libproc
    PXWriteLine("install proc_regionfilename");
    sym = dlsym(RTLD_DEFAULT, "proc_regionfilename");
    if (sym) MSHookFunction(sym, (void *)hook_proc_regionfilename, (void **)&orig_proc_regionfilename);

    if (mode >= 3) {
        PXWriteLine("install dlopen/dlsym");
        sym = dlsym(RTLD_DEFAULT, "dlopen");
        if (sym) MSHookFunction(sym, (void *)hook_dlopen, (void **)&orig_dlopen);
        sym = dlsym(RTLD_DEFAULT, "dlsym");
        if (sym) MSHookFunction(sym, (void *)hook_dlsym, (void **)&orig_dlsym);
    } else {
        PXWriteLine("skip dlopen/dlsym");
    }

    if (mode >= 4) {
        PXWriteLine("install anti-terminate");
        sym = dlsym(RTLD_DEFAULT, "abort");
        if (sym) MSHookFunction(sym, (void *)hook_abort, (void **)&orig_abort);
        sym = dlsym(RTLD_DEFAULT, "raise");
        if (sym) MSHookFunction(sym, (void *)hook_raise, (void **)&orig_raise);
        sym = dlsym(RTLD_DEFAULT, "pthread_kill");
        if (sym) MSHookFunction(sym, (void *)hook_pthread_kill, (void **)&orig_pthread_kill);
        sym = dlsym(RTLD_DEFAULT, "exit");
        if (sym) MSHookFunction(sym, (void *)hook_exit, (void **)&orig_exit);
        sym = dlsym(RTLD_DEFAULT, "_exit");
        if (sym) MSHookFunction(sym, (void *)hook__exit, (void **)&orig__exit);
    } else {
        PXWriteLine("skip anti-terminate");
    }

    PXWriteLine("[ProjectX] MBBankMinimalInit v3 installed");
}
