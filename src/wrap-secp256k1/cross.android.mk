CONFIGUREFLAGS_SECP256K1 += AR=$(TOOLCHAIN)/bin/llvm-ar
CONFIGUREFLAGS_SECP256K1 += CC=$(TOOLCHAIN)/bin/$(MTRIPLE)$(CROSS_ANDROID_API)-clang
CONFIGUREFLAGS_SECP256K1 += AS=$(TOOLCHAIN)/bin/$(MTRIPLE)$(CROSS_ANDROID_API)-clang
CONFIGUREFLAGS_SECP256K1 += CXX=$(TOOLCHAIN)/bin/$(MTRIPLE)$(CROSS_ANDROID_API)-clang++
CONFIGUREFLAGS_SECP256K1 += LD=$(TOOLCHAIN)/bin/ld
CONFIGUREFLAGS_SECP256K1 += RANLIB=$(TOOLCHAIN)/bin/llvm-ranlib
CONFIGUREFLAGS_SECP256K1 += STRIP=$(TOOLCHAIN)/bin/llvm-strip
# CONFIGUREFLAGS_SECP256K1 += CFLAGS="$(CFLAGS) -sysroot $(CROSS_SYSROOT)"

# CFLAGS="-mthumb -march=armv7-a" CCASFLAGS="-Wa,-mthumb -Wa,-march=armv7-a"