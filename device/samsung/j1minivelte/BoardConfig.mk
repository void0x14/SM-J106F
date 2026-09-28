#
# Copyright (C) 2018 The LineageOS Project
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
#

# Inherit from samsung sharkls-common
-include device/samsung/sharkls-common/BoardConfigCommon.mk

# Kernel
TARGET_KERNEL_CONFIG := j1minivelte_defconfig
TARGET_KERNEL_SOURCE := kernel/samsung/j1minivelte

# Init
TARGET_INIT_VENDOR_LIB := libinit_j1minivelte
TARGET_RECOVERY_DEVICE_MODULES := libinit_j1minivelte

# Display: sharkls-common'in J3 2016 (j320fn) prop'unu ez.
# system_prop_file bir listedir (build/make/core/Makefile:314 foreach) ve
# satirlar build.prop'a bu sirayla yazilir. Init ro.* icin write-once oldugu
# icin ILK satir kazanir -> cihaza ozel dosya once gelmeli.
TARGET_SYSTEM_PROP := device/samsung/j1minivelte/system.prop \
                      device/samsung/sharkls-common/system.prop
