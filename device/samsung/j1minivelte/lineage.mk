# Copyright (C) 2016 The CyanogenMod Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Inherit from those products. Most specific first.
#
# WITH_SU burada, ilk inherit'ten ONCE verilmeli.
# vendor/lineage/config/common.mk:238 `ifeq ($(WITH_SU),true)` ile su paketini
# PRODUCT_PACKAGES'e ekler. Ama inherit-product zinciri product_config.mk
# icinden gec import edilir ve BoardConfig.mk ondan SONRA okunur
# (build/make/core/envsetup.mk:208 product_config, :234 board config).
# BoardConfig'te verilirse common.mk testi calistiginda deger henuz bostur ve
# su hic paketlenmez. Olculdu: get_build_var WITH_SU=true der ama
# PRODUCT_PACKAGES'te su yoktur, ninja'da su hedefi yoktur.
# NOT: bunu inherit'lerin altina tasima — sessizce bozulur.
WITH_SU := true

$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common CM stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit device configuration
$(call inherit-product, device/samsung/j1minivelte/j1minivelte.mk)

## Device identifier. This must come after all inclusions
PRODUCT_DEVICE := j1minivelte
PRODUCT_RELEASE_NAME := j1minivelte
PRODUCT_NAME := lineage_j1minivelte
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-J106F
PRODUCT_MANUFACTURER := samsung

PRODUCT_GMS_CLIENTID_BASE := android-samsung

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=j1miniveltejv \
    PRIVATE_BUILD_DESC="j1miniveltejv-user 6.0.1 MMB29Q J106FJVU0ARH1 release-keys"

BUILD_FINGERPRINT := samsung/j1miniveltejv/j1minivelte:6.0.1/MMB29Q/J106FJVU0ARH1:user/release-keys
