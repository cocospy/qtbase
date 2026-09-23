# Native OpenHarmony build environment: dockerharmony + Harmonybrew + a Qt
# toolchain. arm64 only; meant to run on a native arm64 host, not under qemu.
#
#   docker build -t ohos-qt-builder .github/ohos
#
# The image carries the toolchain only. Build Qt outside it, in a bind-mounted
# work tree, so the build stays on host disk:
#
#   docker run --rm --user "$(id -u):$(id -g)" \
#     -e HOME=/build/home -e TMPDIR=/build/tmp \
#     -v "$PWD:/src:ro" -v /var/tmp/qtbase-ohos-build:/build \
#     ohos-qt-builder cmake -S /src -B /build -G Ninja -DOHOS=ON
#
# --user keeps artifacts owned by the caller rather than root. HOME and TMPDIR
# must point at something writable because that uid has no passwd entry and the
# container's own /tmp is not writable by it.
#
# No toolchain file and no CMAKE_SYSTEM_NAME: this is a native build, so Qt
# takes its native-HarmonyOS path. Qt would set OHOS itself if the host looked
# like HarmonyOS, but uname in a container comes from the host kernel and says
# Linux, so -DOHOS=ON has to be passed by hand.
FROM hqzing/dockerharmony:7.0

ENV HOMEBREW_PREFIX=/storage/Users/currentUser/.harmonybrew \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_ENV_HINTS=1

# Harmonybrew's bin/brew is "#!/usr/bin/zsh", but the OpenHarmony rootfs ships
# only mksh. Unpack zsh and its dependencies straight from Harmonybrew's bottle
# server to break the cycle. Bottles are :any_skip_relocation and their RUNPATH
# is absolute, so they only work under the default prefix.
ARG ZSH_BOTTLE=zsh-5.9.2_2
ARG NCURSES_BOTTLE=ncurses-6.6_1
ARG PCRE2_BOTTLE=pcre2-10.48
RUN set -e; \
    b="https://harmonybrew.atomgit.com/bottles"; \
    mkdir -p "$HOMEBREW_PREFIX/Cellar" "$HOMEBREW_PREFIX/opt"; \
    cd /tmp; \
    for f in "$ZSH_BOTTLE" "$NCURSES_BOTTLE" "$PCRE2_BOTTLE"; do \
        name="${f%-*}"; ver="${f##*-}"; \
        curl -fsSL -o b.tgz "$b/$f.arm64_ohos.bottle.tar.gz"; \
        tar -zxf b.tgz -C "$HOMEBREW_PREFIX/Cellar"; \
        ln -sfn "$HOMEBREW_PREFIX/Cellar/$name/$ver" "$HOMEBREW_PREFIX/opt/$name"; \
        rm -f b.tgz; \
    done; \
    mkdir -p /usr/bin; \
    ln -sf "$HOMEBREW_PREFIX/opt/zsh/bin/zsh" /usr/bin/zsh; \
    zsh --version

RUN NONINTERACTIVE=1 zsh -c "$(curl -fsSL https://harmonybrew.atomgit.com/install.sh)"

ENV PATH=${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${PATH}

RUN brew install cmake ninja python git pkgconf ohos-sdk-native

ENV NATIVE_OHOS_SDK=${HOMEBREW_PREFIX}/opt/ohos-sdk-native
ENV OHOS_TOOLCHAIN_FILE=${NATIVE_OHOS_SDK}/build/cmake/ohos.toolchain.cmake

# The rootfs has no ar/ranlib/strip at all; the only ones are the SDK's
# llvm-* tools. Appended, not prepended, so brew's tools keep priority.
ENV PATH=${PATH}:${NATIVE_OHOS_SDK}/llvm/bin
ENV AR=${NATIVE_OHOS_SDK}/llvm/bin/llvm-ar \
    RANLIB=${NATIVE_OHOS_SDK}/llvm/bin/llvm-ranlib

# Qt's third-party dependencies for OpenHarmony, static, unpacked into the SDK
# sysroot. Even used natively the SDK clang searches only its own sysroot, never
# the container's /usr, so this is the one place that needs no extra flags.
#
# They go in sysroot/usr/lib rather than sysroot/usr/lib/aarch64-linux-ohos for
# two reasons: the linker searches it first, so our static libz wins over the
# SDK's link-time stub libz.so (whose runtime counterpart this rootfs lacks),
# and it is a plain <prefix>/lib, which is where CMake's find_library looks.
ARG OHOS_ADDITIONAL_PACKAGES_URL=https://github.com/jobor/qtbase/releases/download/ohos-deps-2026.07.29/ohos-additional-packages-2026.07.29-arm64-static.zip
ARG OHOS_ADDITIONAL_PACKAGES_SHA256=97e604363f065353751d67f66a004a1f2d420a6abd03c6b1e13b0e887bdbf42f
RUN set -e; \
    curl -fsSL -o /tmp/ap.zip "$OHOS_ADDITIONAL_PACKAGES_URL"; \
    echo "$OHOS_ADDITIONAL_PACKAGES_SHA256  /tmp/ap.zip" | sha256sum -c -; \
    python3 -m zipfile -e /tmp/ap.zip /tmp/ap; \
    ap=/tmp/ap/arm64-static; \
    sysroot="$NATIVE_OHOS_SDK/sysroot/usr"; \
    cp -a "$ap/include/." "$sysroot/include/"; \
    cp -a "$ap/lib/." "$sysroot/lib/"; \
    if [ -d "$ap/share" ]; then cp -a "$ap/share/." "$sysroot/share/"; fi; \
    rm -rf /tmp/ap /tmp/ap.zip

ENV PKG_CONFIG_PATH=${NATIVE_OHOS_SDK}/sysroot/usr/lib/pkgconfig \
    CMAKE_PREFIX_PATH=${NATIVE_OHOS_SDK}/sysroot/usr

# The SDK clang is not on PATH as cc/c++; name it so CMake picks it up without
# a toolchain file.
ENV CC=${NATIVE_OHOS_SDK}/llvm/bin/clang \
    CXX=${NATIVE_OHOS_SDK}/llvm/bin/clang++

# dockerharmony is an OpenHarmony userland, not a system image, so it ships
# none of the platform libraries. Without them libQt6Core cannot be loaded and
# no build-time tool linking it can run, which stops the build at qvkgen.
#
# Real libraries where the closure is shallow and self-contained: 11 files,
# 680 KB, the transitive closure of libdeviceinfo_ndk, libtime_service_ndk and
# libhilog_ndk. Extracted from harmony-contrib/ohos-qemu v20260919, arm64
# standard-system image. OpenHarmony is Apache-2.0.
#
# The other three Qt6Core needs get generated stubs: libace_napi pulls in the
# ArkTS engine and libohfileuri the system ability manager and IPC, neither of
# which belongs in a build container. /system/lib64 is first in the
# container's musl search path.
ARG OHOS_RUNTIME_LIBS_URL=https://github.com/jobor/qtbase/releases/download/ohos-runtime-libs-20260919/ohos-runtime-libs-20260919.tar.gz
ARG OHOS_RUNTIME_LIBS_SHA256=c03a44be84513a63c22b2bfc18c365da91d2eb1095c021a34d66d3ba3a3c3464
COPY gen-shims.py /tmp/ctx/
RUN set -e; \
    curl -fsSL -o /tmp/rt.tar.gz "$OHOS_RUNTIME_LIBS_URL"; \
    echo "$OHOS_RUNTIME_LIBS_SHA256  /tmp/rt.tar.gz" | sha256sum -c -; \
    mkdir -p /system/lib64; \
    tar -xzf /tmp/rt.tar.gz -C /system/lib64; \
    rm -f /tmp/rt.tar.gz; \
    python3 /tmp/ctx/gen-shims.py "$NATIVE_OHOS_SDK" /system/lib64 "$CC"

# Qt links some third-party libraries from Harmonybrew rather than the
# additional-packages archive, pcre2 among them, because the archive ships no
# pcre2 at all. Brew's lib directory is on no default search path, so those
# libraries resolve while building, where CMake gives binaries an RPATH
# covering the link directories, and then fail to load once Qt is installed
# and that RPATH is replaced.
#
# LD_LIBRARY_PATH rather than a loader config file: OHOS musl resolves
# libraries through the namespace config in /etc/ld-musl-namespace-aarch64.ini,
# not /etc/ld-musl-aarch64.path, and editing the latter has no effect at all.
ENV LD_LIBRARY_PATH=${HOMEBREW_PREFIX}/lib

RUN cmake --version && ninja --version && python3 --version && git --version && \
    "$CC" --version && \
    ls "$NATIVE_OHOS_SDK/sysroot/usr/lib/libpng16.a" && \
    ls "$NATIVE_OHOS_SDK/sysroot/usr/include/png.h"
