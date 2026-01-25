INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TestCtorTweak

TestCtorTweak_FILES = Tweak.x
TestCtorTweak_CFLAGS = -fobjc-arc
# Try different linker flags to fix __mod_init_func issue on Xcode 15
# -ld64 was the beta flag, -ld_classic is current
TestCtorTweak_LDFLAGS = -Xlinker -ld64

include $(THEOS_MAKE_PATH)/tweak.mk
