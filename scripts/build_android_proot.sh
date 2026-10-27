#!/usr/bin/env bash
set -euo pipefail
# Standalone executables, installed by Android in nativeLibraryDir. No executable
# is downloaded at runtime; the ELF loader is bundled alongside PRoot.
repo=$(cd "$(dirname "$0")/.." && pwd)
ndk=${1:?Usage: build_android_proot.sh NDK_PATH ABI OUTPUT_DIRECTORY}
abi=${2:?}
output=${3:?}
case "$abi" in
  arm64-v8a) triple=aarch64-linux-android ;;
  armeabi-v7a) triple=armv7a-linux-androideabi ;;
  x86_64) triple=x86_64-linux-android ;;
  *) exit 2 ;;
esac
tools="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
cc="$tools/${triple}24-clang"
work="$repo/build/android-proot/$abi"
mkdir -p "$work" "$output"
rm -rf "$work/source"
cp -a "$repo/third_party/proot" "$work/source"
"$cc" -O2 -DNO_CONFIG_H=1 -D__STDC_WANT_LIB_EXT1__=1 \
  -I"$work/source/lib/talloc" -I"$repo/third_party/talloc" \
  -c "$repo/third_party/talloc/talloc.c" -o "$work/talloc.o"
"$tools/llvm-ar" rcs "$work/libtalloc.a" "$work/talloc.o"
make -C "$work/source/src" -j2 \
  CC="$cc" STRIP="$tools/llvm-strip" OBJCOPY="$tools/llvm-objcopy" \
  OBJDUMP="$tools/llvm-objdump" GIT=true \
  CFLAGS="-O2 -DDEVCAT_NATIVE_ONLY -I$repo/third_party/talloc" \
  LDFLAGS="-L$work -ltalloc -static -Wl,-z,noexecstack,-z,max-page-size=16384" \
  proot
cp "$work/source/src/proot" "$output/libdevcat_proot.so"
cp "$work/source/src/loader/loader" "$output/libdevcat_loader.so"
"$tools/llvm-strip" "$output/libdevcat_proot.so"
chmod 755 "$output"/*.so
