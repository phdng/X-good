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

# CRITICAL: Force ObjC runtime to properly initialize +load methods
# -lobjc ensures libobjc is linked, -ObjC forces all ObjC symbols to be loaded
ProjectXTweak_LDFLAGS = -lobjc -Wl,-ObjC

include $(THEOS_MAKE_PATH)/tweak.mk
