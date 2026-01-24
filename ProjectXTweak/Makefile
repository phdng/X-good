INSTALL_TARGET_PROCESSES = SpringBoard


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProjectXTweak

# Tweak files
# ProjectXTweak_FILES =  $(wildcard *.x) $(wildcard *.m)
ProjectXTweak_FILES =  $(wildcard *.x) $(wildcard *.m) ${wildcard ../common/*.m}

ProjectXTweak_CFLAGS = -fobjc-arc -Wno-error=unused-variable -Wno-error=unused-function -I../common  -I../include -D USES_LIBUNDIRECT=1 -D SUPPORT_IPAD=1 -D ENABLE_STATE_RESTORATION=1
ProjectXTweak_FRAMEWORKS = UIKit Foundation AdSupport UserNotifications IOKit Security CoreLocation CoreFoundation Network CoreTelephony SystemConfiguration WebKit SafariServices   
ProjectXTweak_PRIVATE_FRAMEWORKS = MobileCoreServices AppSupport SpringBoardServices 
ProjectXTweak_LIBRARIES = MobileGestalt

# CRITICAL: Prevent constructor stripping - ensures __mod_init_func section is kept
ProjectXTweak_LDFLAGS = -Wl,-all_load

include $(THEOS_MAKE_PATH)/tweak.mk
