export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobilePhone InCallService

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IOS26Phone
IOS26Phone_FILES = Tweak.x
IOS26Phone_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
IOS26Phone_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
