INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TestCtorTweak

TestCtorTweak_FILES = Tweak.x
TestCtorTweak_CFLAGS = -fobjc-arc
# Force use of ld_classic linker (macOS 14+ uses new ld that may not handle constructors properly)
TestCtorTweak_LDFLAGS = -Wl,-ld_classic

include $(THEOS_MAKE_PATH)/tweak.mk

