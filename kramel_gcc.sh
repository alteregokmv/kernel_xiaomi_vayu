#!/bin/bash

# Variables
export ARCH=arm64
export SUBARCH=arm64
export DTC_EXT=dtc
export DEVICE=vayu
export DEVICE_CONFIG=vayu_gcc_defconfig

# Mandatory for vayu, but custom build seems to break something...
export BUILD_DTBO=false

# Do we build final zip ?
export BUILD_ZIP=true

# prepare env
export TC_PATH="$HOME/gcc"
export TC_PATH32="$HOME/gcc64"
export CLANG_PATH="$HOME/proton-clang"

FUNNY_FLAGS_PRESET_GCC=" \
	--param max-inline-insns-single=600 \
	--param max-inline-insns-auto=750 \
	--param large-stack-frame=12288 \
	--param inline-min-speedup=5 \
	--param inline-unit-growth=60"

# git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 $TC_PATH --depth=1 &
# git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 $TC_PATH32 --depth=1 &
# git clone -q --depth=1 --single-branch https://github.com/kdrag0n/proton-clang $CLANG_PATH &
# wait

git clone https://github.com/mvaisakh/gcc-arm.git $TC_PATH --depth=1 &
git clone https://github.com/mvaisakh/gcc-arm64.git $TC_PATH32 --depth=1 &
wait

# Google CLANG  9.x :
# https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/android-9.0.0_r48/clang-4691093.tar.gz
#export CLANG_PATH=$PWD/../clang
export OUT_PATH=$PWD/outgcc

#
# Kernel building
#

# Update PATH (dtc,clang,tc)
# DTC needed (https://forum.xda-developers.com/attachments/device-tree-compiler-zip.4829019/)
# More info:  https://forum.xda-developers.com/t/guide-how-to-compile-kernel-dtbo-for-redmi-k20.3973787/
PATH="/android/bin:$CLANG_PATH/bin:$TC_PATH/bin:$TC_PATH32/bin:$PATH"

mkdir -p $OUT_PATH

compile_kernel () {

make O=$OUT_PATH ARCH=arm64 $DEVICE_CONFIG

# Build kernel
# make -j$(nproc --all) O=$OUT_PATH ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-elf- CROSS_COMPILE_ARM32=arm-eabi-
make -j$(nproc --all) O=$OUT_PATH \
                             ARCH=arm64 \
			     CROSS_COMPILE_ARM32=arm-eabi- \
			     CROSS_COMPILE=aarch64-elf- 

# Building DTBO
# https://android.googlesource.com/platform/system/libufdt/+archive/master/utils.tar.gz
if $BUILD_DTBO; then
	echo -e "Building DTBO..."
	MKDTBOIMG_PATH=~/android/bin/

# DEPRECATED:
#	if ! mkdtimg create /$OUT_PATH/arch/arm64/boot/dtbo.img --page_size=4096 $OUT_PATH/arch/arm64/boot/dts/qcom/*.dtbo; then
	if ! python $MKDTBOIMG_PATH/mkdtboimg.py create /$OUT_PATH/arch/arm64/boot/dtbo.img --page_size=4096 $OUT_PATH/arch/arm64/boot/dts/qcom/*.dtbo; then
		echo -e "Error creating DTBO"
		exit 1
	else
		echo -e "DTBO created successfully"
	fi
fi

find $OUT_PATH/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > $OUT_PATH/arch/arm64/boot/dtb

}

#
# Kernel packaging
#

# AnyKernel

export ANYKERNEL_URL=https://github.com/lybdroid/AnyKernel3.git
export ANYKERNEL_PATH=$OUT_PATH/AnyKernel3
export ANYKERNEL_BRANCH=vayu-miui
export ZIPDATE=$(date '+%Y%m%d-%H%M')
export GITLOG=$(git log --pretty=format:'"%h : %s"' -1)
export ZIPNAME="lybkernel-gaming-$DEVICE-$ZIPDATE.zip"

pacakge_zip () {

if $BUILD_ZIP; then

if [ -f "$OUT_PATH/arch/arm64/boot/Image" ]; then
	echo -e "Packaging...\n"
	git clone -q $ANYKERNEL_URL $ANYKERNEL_PATH -b $ANYKERNEL_BRANCH
	cp $OUT_PATH/arch/arm64/boot/Image $ANYKERNEL_PATH

	if  [ -f "$OUT_PATH/arch/arm64/boot/dtb" ]; then
		cp $OUT_PATH/arch/arm64/boot/dtb $ANYKERNEL_PATH
	fi

	if  [ -f "$OUT_PATH/arch/arm64/boot/dtbo.img" ]; then
		cp $OUT_PATH/arch/arm64/boot/dtbo.img $ANYKERNEL_PATH
	else
		if ! $BUILD_DTBO; then
			echo -e "DTBO not needed."
		else
			echo -e "DTBO not found! Error!"
			exit 1
		fi
	fi
	rm -f *zip
	cd $ANYKERNEL_PATH
	zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder
	cd ..
	echo -e "Cleaning anykernel structure..."
	rm -rf $ANYKERNEL_PATH

	echo "Kernel packaged: $ZIPNAME"

	ZIP=$ZIPNAME
    curl -F document=@$ZIP "https://api.telegram.org/bot$BOTTOKEN/sendDocument" \
        -F chat_id="$CHATID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html" \
        -F caption="For <b>Poco X3 (vayu)</b> <code>$GITLOG</code>"


	echo -e "Cleaning build directory..."
	rm -rf $OUT_PATH/arch/arm64/boot
	cd ..
else
	echo -e "Error packaging kernel."
	cd ..
fi

fi
}
ZIPNAME="lybkernel-tsmod_noeff-$DEVICE-$ZIPDATE.zip"
curl https://github.com/lybdroid/kernel_xiaomi_vayu/commit/f34969ebfdbf4133aeccb1b76e07603284d8df95.patch | git am
compile_kernel
pacakge_zip

curl https://github.com/lybdroid/kernel_xiaomi_vayu/commit/cc0f575d69d8e302536240c1ea5e5e3d50748212.patch | git am
curl https://github.com/lybdroid/kernel_xiaomi_vayu/commit/8d4ecaa855c484fa02092865d1d305ce2f7656cf.patch | git am
ZIPNAME="lybkernel-tsmod_noeff-ocuv-$DEVICE-$ZIPDATE.zip"
compile_kernel
pacakge_zip

git reset --hard origin/eleven-riced
ZIPNAME="lybkernel-tsmod-$DEVICE-$ZIPDATE.zip"
curl https://github.com/lybdroid/kernel_xiaomi_vayu/commit/f34969ebfdbf4133aeccb1b76e07603284d8df95.patch | git am
sed -i 's/lyb_boost_def = false/lyb_boost_def = true/g' drivers/misc/lyb_perf.c
compile_kernel
pacakge_zip

git reset --hard origin/eleven-riced
ZIPNAME="lybkernel-stock-$DEVICE-$ZIPDATE.zip"
sed -i 's/lyb_boost_def = false/lyb_boost_def = true/g' drivers/misc/lyb_perf.c
sed -i 's/CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI=y/CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI_STOCK=y/g' arch/arm64/configs/vayu_gcc_defconfig
sed -i 's/CONFIG_TOUCHSCREEN_NVT_DEBUG_FS=y/CONFIG_TOUCHSCREEN_NVT_DEBUG_FS_STOCK=y/g' arch/arm64/configs/vayu_gcc_defconfig
compile_kernel
pacakge_zip

git reset --hard origin/eleven-riced
ZIPNAME="lybkernel-stock_noeff-$DEVICE-$ZIPDATE.zip"
sed -i 's/CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI=y/CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI_STOCK=y/g' arch/arm64/configs/vayu_gcc_defconfig
sed -i 's/CONFIG_TOUCHSCREEN_NVT_DEBUG_FS=y/CONFIG_TOUCHSCREEN_NVT_DEBUG_FS_STOCK=y/g' arch/arm64/configs/vayu_gcc_defconfig
compile_kernel
pacakge_zip