LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE_TAGS := optional
LOCAL_C_INCLUDES := \
system/core/init \
system/core/base/include \
external/selinux/libselinux/include
LOCAL_CPPFLAGS := -Wall -DANDROID_TARGET=\"$(TARGET_BOARD_PLATFORM)\"
LOCAL_SRC_FILES := init_j1minivelte.cpp
LOCAL_MODULE := libinit_j1minivelte

include $(BUILD_STATIC_LIBRARY)
