LOCAL_PATH := $(call my-dir)

# vendor/lib/hw/bluetooth.default.so DT_NEEDED ile bu adi istiyor ve dosya
# stok blob setinde yok. Ayni adla derleyip vendor/lib'e kuruyoruz; boylece
# bluetooth.default.so'ya hic dokunmak gerekmiyor.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := edmnativehelper_shim.c
LOCAL_MODULE := libedmnativehelper
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_SHARED_LIBRARY)
