// ObjcClassPairGuard.x
// Prevent crashes when third-party swizzlers incorrectly register a NULL class.

#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <syslog.h>

static Class (*orig_objc_allocateClassPair)(Class superclass, const char *name, size_t extraBytes);
static void (*orig_objc_registerClassPair)(Class cls);

static const char *PXGuardLogPath(void) {
    // In sandboxed apps, TMPDIR points to the app container tmp.
    // Prefer that so we always have write permission.
    const char *tmp = getenv("TMPDIR");
    if (tmp && tmp[0] != '\0') return tmp;
    return "/tmp/";
}

static void PXGuardTrace(const char *line) {
    if (!line) return;

    char path[512];
    (void)snprintf(path, sizeof(path), "%s%s", PXGuardLogPath(), "projectx_objc_classpair_guard.log");

    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) return;
    (void)write(fd, line, (size_t)strlen(line));
    (void)write(fd, "\n", 1);
    (void)close(fd);
}

static Class hooked_objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes) {
    Class cls = orig_objc_allocateClassPair(superclass, name, extraBytes);
    if (cls) return cls;

    // Most common failure case: name already exists.
    // Returning the existing class avoids downstream callers passing NULL to objc_registerClassPair.
    if (name && name[0] != '\0') {
        char buf[256];
        (void)snprintf(buf, sizeof(buf), "allocateClassPair returned NULL for name=%s", name);
        PXGuardTrace(buf);
        syslog(LOG_NOTICE, "[ProjectX] %s", buf);
        Class existing = objc_getClass(name);
        if (existing) return existing;
    }

    return cls;
}

static void hooked_objc_registerClassPair(Class cls) {
    // Guard against buggy callers that pass NULL.
    if (!cls) {
        PXGuardTrace("registerClassPair called with NULL (ignored)");
        syslog(LOG_NOTICE, "[ProjectX] objc_registerClassPair(NULL) ignored");
        return;
    }
    orig_objc_registerClassPair(cls);
}

__attribute__((constructor(101)))
static void PXInstallObjcClassPairGuards(void) {
    // Prefer resolving from libobjc explicitly to avoid edge cases with RTLD_DEFAULT.
    void *libobjc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW);
    void *allocatePtr = NULL;
    void *registerPtr = NULL;

    if (libobjc) {
        allocatePtr = dlsym(libobjc, "objc_allocateClassPair");
        registerPtr = dlsym(libobjc, "objc_registerClassPair");
    }
    if (!allocatePtr) allocatePtr = dlsym(RTLD_DEFAULT, "objc_allocateClassPair");
    if (!registerPtr) registerPtr = dlsym(RTLD_DEFAULT, "objc_registerClassPair");

    if (allocatePtr) {
        MSHookFunction(allocatePtr, (void *)hooked_objc_allocateClassPair, (void **)&orig_objc_allocateClassPair);
    }
    if (registerPtr) {
        MSHookFunction(registerPtr, (void *)hooked_objc_registerClassPair, (void **)&orig_objc_registerClassPair);
    }

    if (allocatePtr || registerPtr) {
        PXGuardTrace("ObjcClassPairGuard installed");
        syslog(LOG_NOTICE, "[ProjectX] ObjcClassPairGuard installed (allocate=%p register=%p)", allocatePtr, registerPtr);
    } else {
        PXGuardTrace("ObjcClassPairGuard failed to resolve symbols");
        syslog(LOG_NOTICE, "[ProjectX] ObjcClassPairGuard failed to resolve symbols");
    }
}
