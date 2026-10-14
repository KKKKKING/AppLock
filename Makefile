TARGET := AppLock
BUILD_DIR := build
SDK ?= iphoneos
MIN_IOS ?= 14.0
ARCHS ?= arm64
CC := xcrun --sdk $(SDK) clang
SDK_PATH := $(shell xcrun --sdk $(SDK) --show-sdk-path)
OUTPUT := $(BUILD_DIR)/$(TARGET).dylib

.PHONY: all clean verify

all: $(OUTPUT)

$(OUTPUT): AppLock.m
	@mkdir -p $(BUILD_DIR)
	$(CC) -dynamiclib -fobjc-arc -fmodules \
		-isysroot "$(SDK_PATH)" \
		-miphoneos-version-min=$(MIN_IOS) \
		$(foreach arch,$(ARCHS),-arch $(arch)) \
		-framework Foundation -framework UIKit \
		-Wall -Wextra -Werror \
		-Wl,-install_name,@rpath/$(TARGET).dylib \
		-o $@ $<

verify: $(OUTPUT)
	file $(OUTPUT)
	xcrun otool -L $(OUTPUT)

clean:
	rm -rf $(BUILD_DIR)
