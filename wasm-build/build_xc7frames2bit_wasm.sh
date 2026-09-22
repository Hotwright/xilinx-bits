#!/bin/bash
# Build prjxray's xc7frames2bit as a WASI WebAssembly command, so a browser can
# turn the frames fasm2frames produces into a real .bit.
#
# The recipe is the one build_nextpnr_xilinx_wasm.sh established -- wasi-sdk 34,
# wasm32-wasip1, no exception handling plus wasi_throw_stubs.o, because jco
# cannot transpile a module that uses the WebAssembly exception-handling
# proposal and jco is the route to the browser. Read that script's header for
# the full reasoning; only the differences are noted here:
#
#   1. prjxray vendors every dependency it needs (gflags, cctz, abseil,
#      yaml-cpp under third_party/), so there is no Boost/Eigen stage: one
#      cmake configure covers the lot.
#   2. -Wno-error, and -Wno-deprecated-builtins with it. prjxray compiles with
#      -Wall -Werror against a 2020-era clang; clang 23 finds more, and none of
#      it is ours to fix. -Wno-error alone does NOT do the job: prjxray's own
#      CMakeLists.txt:39 says add_compile_options(-Wall -Werror), and CMake puts
#      directory options AFTER CMAKE_CXX_FLAGS, so the later -Werror wins. What
#      survives that ordering is suppressing the diagnostic itself -- a warning
#      that is never emitted cannot be promoted to an error. The one that stops
#      the build is in vendored abseil, not prjxray:
#        absl/meta/type_traits.h:527: builtin __is_trivially_relocatable is
#        deprecated; use __builtin_is_cpp_trivially_relocatable instead
#      Every libprjxray object includes it through segbits_file_reader.h ->
#      absl/strings/string_view.h, which is why all 14 failed with one error
#      each. Upstream abseil fixed this after the revision vendored here;
#      bumping third_party would be a bigger change than this build needs.
#   3. -D_WASI_EMULATED_MMAN / -lwasi-emulated-mman. lib/memory_mapped_file.cc
#      maps each database file with mmap(PROT_READ, MAP_PRIVATE); WASI has no
#      mmap and its sys/mman.h is a hard #error until this define is set. The
#      emulation wasi-libc ships is enough here because the use is the simplest
#      possible one -- open, fstat, map the whole file read-only, munmap in the
#      destructor, no MAP_SHARED, no writes, no remap. The library goes in
#      CMAKE_CXX_STANDARD_LIBRARIES beside the throw stubs, which is appended
#      after the objects that reference it.
#   4. -DGLOB_TILDE=0. lib/database.cc globs segbits_*.db with
#      GLOB_NOSORT | GLOB_TILDE. wasi-libc has a real glob() -- glob.c.obj
#      defines it, it is not a stub -- but not the GNU GLOB_TILDE extension,
#      which expands a leading ~ in the pattern. The pattern here is
#      absl::StrCat(db_path_, "/segbits_*.db") with db_path_ an absolute mount
#      path, so there is never a ~ to expand and dropping the flag changes
#      nothing. Defining it to 0 leaves the expression as GLOB_NOSORT | 0
#      rather than patching prjxray's source.
#   5. Only the one target is built. The other tools in tools/ (bitread,
#      segmatch, ...) are developer utilities that the browser has no use for,
#      and each one that fails to link is a failure this build does not need.
#
# Stages: configure | build | all
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( dirname "$HERE" )"
XRAY="${XRAY:-${ROOT}/prjxray}"
WASI_SDK_PATH="${WASI_SDK_PATH:-/home/sc/wasi-sdk-34.0-x86_64-linux}"
BUILD="${HERE}/prjxray-build"
STAGE="${1:-all}"

[ -d "$WASI_SDK_PATH" ] || { echo "no wasi-sdk at $WASI_SDK_PATH" >&2; exit 1; }
[ -d "$XRAY" ] || { echo "no prjxray at $XRAY" >&2; exit 1; }

# The stubs object is shared with the nextpnr build; build it if that script
# has not already.
stubs() {
    [ -f "${HERE}/wasi_throw_stubs.o" ] && return
    "${WASI_SDK_PATH}/bin/clang++" --sysroot "${WASI_SDK_PATH}/share/wasi-sysroot" \
        --target=wasm32-wasip1 -fno-exceptions -O2 \
        -c "${HERE}/wasi_throw_stubs.cc" -o "${HERE}/wasi_throw_stubs.o"
}

toolchain() {
    cat > "${HERE}/Toolchain-WASI-prjxray.cmake" <<END
cmake_minimum_required(VERSION 3.4...3.31)
set(WASI TRUE)
set(CMAKE_SYSTEM_NAME WASI)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR wasm32)
set(CMAKE_C_COMPILER ${WASI_SDK_PATH}/bin/clang)
set(CMAKE_CXX_COMPILER ${WASI_SDK_PATH}/bin/clang++)
set(CMAKE_LINKER ${WASI_SDK_PATH}/bin/wasm-ld CACHE STRING "wasi build")
set(CMAKE_AR ${WASI_SDK_PATH}/bin/ar CACHE STRING "wasi build")
set(CMAKE_RANLIB ${WASI_SDK_PATH}/bin/ranlib CACHE STRING "wasi build")
set(CMAKE_C_COMPILER_TARGET wasm32-wasip1)
set(CMAKE_CXX_COMPILER_TARGET wasm32-wasip1)
set(CMAKE_C_FLAGS "--sysroot ${WASI_SDK_PATH}/share/wasi-sysroot -Wno-error -Wno-deprecated-builtins -D_WASI_EMULATED_MMAN -DGLOB_TILDE=0" CACHE STRING "wasi build")
set(CMAKE_CXX_FLAGS "--sysroot ${WASI_SDK_PATH}/share/wasi-sysroot -Wno-error -Wno-deprecated-builtins -D_WASI_EMULATED_MMAN -DGLOB_TILDE=0" CACHE STRING "wasi build")
set(CMAKE_EXE_LINKER_FLAGS "-Wl,--strip-all" CACHE STRING "wasi build")
# After the objects that reference them -- see the nextpnr script.
set(CMAKE_CXX_STANDARD_LIBRARIES "${HERE}/wasi_throw_stubs.o -lwasi-emulated-mman" CACHE STRING "wasi build")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
END
}

configure() {
    stubs; toolchain
    cmake -S "$XRAY" -B "$BUILD" \
        -DCMAKE_TOOLCHAIN_FILE="${HERE}/Toolchain-WASI-prjxray.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPRJXRAY_BUILD_TESTING=OFF \
        -DBUILD_TESTING=OFF \
        -DGFLAGS_BUILD_TESTING=OFF \
        -DGFLAGS_BUILD_SHARED_LIBS=OFF \
        -DYAML_CPP_BUILD_TESTS=OFF \
        -DYAML_CPP_BUILD_TOOLS=OFF
}

build() {
    cmake --build "$BUILD" --target xc7frames2bit -j"$(nproc)"
    ls -l "${BUILD}/tools/xc7frames2bit"*
}

case "$STAGE" in
    configure) configure ;;
    build)     build ;;
    all)       configure; build ;;
    *) echo "usage: $0 [configure|build|all]" >&2; exit 1 ;;
esac
