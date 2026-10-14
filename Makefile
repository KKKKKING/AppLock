ARCHS := arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := TrollFools

APPLOCK_BUILD_DIR := $(CURDIR)/build
APPLOCK_DYLIB := $(APPLOCK_BUILD_DIR)/AppLock.dylib
APPLOCK_CC := xcrun --sdk iphoneos clang
APPLOCK_SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME = TrollFools
TrollFools_XCODE_SCHEME = TrollFools

include $(THEOS_MAKE_PATH)/xcodeproj.mk

before-all:: $(APPLOCK_DYLIB)

$(APPLOCK_DYLIB): AppLock.m
	@mkdir -p $(APPLOCK_BUILD_DIR)
	$(APPLOCK_CC) -dynamiclib -fobjc-arc -fmodules \
		-isysroot "$(APPLOCK_SDK)" \
		-miphoneos-version-min=14.0 -arch arm64 \
		-framework Foundation -framework UIKit \
		-Wall -Wextra -Werror \
		-Wl,-install_name,@rpath/AppLock.dylib \
		-o $@ $<

before-package::
	$(ECHO_NOTHING)cp $(APPLOCK_DYLIB) $(THEOS_STAGING_DIR)/Applications/TrollFools.app/AppLock.dylib$(ECHO_END)
	$(ECHO_NOTHING)ldid -STrollFools/TrollFools.entitlements $(THEOS_STAGING_DIR)/Applications/TrollFools.app$(ECHO_END)

export THEOS_PACKAGE_INSTALL_PREFIX
export THEOS_STAGING_DIR
after-package::
	devkit/tipa.sh
