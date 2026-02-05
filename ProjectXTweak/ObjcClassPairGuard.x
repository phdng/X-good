// ObjcClassPairGuard.x
// Prevent crashes when third-party swizzlers incorrectly register a NULL class.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>

static Class (*orig_objc_allocateClassPair)(Class superclass, const char *name, size_t extraBytes);
static void (*orig_objc_registerClassPair)(Class cls);

static inline BOOL PXShouldGuardClassPairName(const char *name) {
    if (!name) return NO;
    // Firebase Performance / GoogleUtilities commonly prefix their runtime-generated classes.
    if (strncmp(name, "FPR", 3) == 0) return YES;
    if (strncmp(name, "GUL", 3) == 0) return YES;
    if (strncmp(name, "FIR", 3) == 0) return YES;
    return NO;
}

static Class hooked_objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes) {
    Class cls = orig_objc_allocateClassPair(superclass, name, extraBytes);
    if (cls) return cls;

    // If allocation failed due to an existing class with the same name, return it.
    // This specifically avoids downstream code calling objc_registerClassPair(NULL).
    if (PXShouldGuardClassPairName(name)) {
        Class existing = objc_getClass(name);
        if (existing) return existing;
    }
    return cls;
}

static void hooked_objc_registerClassPair(Class cls) {
    // Guard against buggy callers that pass NULL (observed in some swizzlers).
    if (!cls) return;
    orig_objc_registerClassPair(cls);
}

%ctor {
    @autoreleasepool {
        void *allocatePtr = dlsym(RTLD_DEFAULT, "objc_allocateClassPair");
        void *registerPtr = dlsym(RTLD_DEFAULT, "objc_registerClassPair");
        if (allocatePtr) {
            MSHookFunction(allocatePtr, (void *)hooked_objc_allocateClassPair, (void **)&orig_objc_allocateClassPair);
        }
        if (registerPtr) {
            MSHookFunction(registerPtr, (void *)hooked_objc_registerClassPair, (void **)&orig_objc_registerClassPair);
        }
    }
}
