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
#include <string.h>

static Class (*orig_objc_allocateClassPair)(Class superclass, const char *name, size_t extraBytes);
static void (*orig_objc_registerClassPair)(Class cls);

static inline BOOL PXHasFirebasePrefix(const char *name) {
    if (!name) return NO;
    if (strncmp(name, "FPR", 3) == 0) return YES;
    if (strncmp(name, "GUL", 3) == 0) return YES;
    if (strncmp(name, "FIR", 3) == 0) return YES;
    return NO;
}

static BOOL PXIsSubclassOfClass(Class cls, Class expectedSuperclass) {
    if (!cls || !expectedSuperclass) return NO;
    Class cur = cls;
    while (cur) {
        if (cur == expectedSuperclass) return YES;
        cur = class_getSuperclass(cur);
    }
    return NO;
}

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
    // For Firebase/GUL dynamic subclasses, prefer allocating a unique name so swizzlers get a
    // fresh class (avoids mutating an existing class created by another swizzler attempt).
    if (name && name[0] != '\0' && PXHasFirebasePrefix(name)) {
        char buf[320];
        (void)snprintf(buf, sizeof(buf), "allocateClassPair returned NULL for name=%s super=%s", name, superclass ? class_getName(superclass) : "(null)");
        PXGuardTrace(buf);
        syslog(LOG_NOTICE, "[ProjectX] %s", buf);

        static unsigned long counter = 0;
        char altName[256];
        (void)snprintf(altName, sizeof(altName), "%s__px%lu", name, ++counter);
        Class alt = orig_objc_allocateClassPair(superclass, altName, extraBytes);
        if (alt) {
            char buf2[384];
            (void)snprintf(buf2, sizeof(buf2), "name collision for %s; allocated %s instead", name, altName);
            PXGuardTrace(buf2);
            syslog(LOG_NOTICE, "[ProjectX] %s", buf2);
            return alt;
        }

        // Last resort: return existing class if compatible.
        Class existing = objc_getClass(name);
        if (existing && (!superclass || PXIsSubclassOfClass(existing, superclass))) {
            PXGuardTrace("falling back to existing class after alt allocation failed");
            syslog(LOG_NOTICE, "[ProjectX] falling back to existing class for %s", name);
            return existing;
        }
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

    // Guard against double-registering an already-registered class (can cause runtime instability).
    const char *name = class_getName(cls);
    if (name && name[0] != '\0' && PXHasFirebasePrefix(name)) {
        Class already = objc_getClass(name);
        if (already == cls) {
            // Already registered.
            return;
        }
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
