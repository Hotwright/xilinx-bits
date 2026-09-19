#!/bin/bash
# Build nextpnr-himbaechel (xilinx uarch) as a WASI WebAssembly command.
#
# The recipe is YoWASP's (github.com/YoWASP/nextpnr, build.sh) - wasi-sdk,
# Boost 1.81 built for wasm32, Eigen 3.4, chipdb kept OUTSIDE the binary - with
# these deliberate changes:
#
#   1. The source is ../../eda-tools/nextpnr at our own commit, not YoWASP's
#      pinned nextpnr-src. Himbaechel checks the chipdb against the binary, so
#      the .wasm and chipdb-xc7s25.bin must come from one tree, and YoWASP's
#      pin has neither the Spartan-7 part-name parsing nor xc7s25 in its device
#      list.
#   2. -DHIMBAECHEL_UARCH="xilinx" (YoWASP ships gowin).
#   3. No ccache: not installed here.
#   4. CMAKE_SYSTEM_NAME is WASI rather than YoWASP's Generic - see the
#      toolchain file below.
#   5. wasi-sdk 34, target wasm32-wasip1, plus wasi_throw_stubs.cc. nextpnr
#      throws and no wasi-sdk sysroot without exception handling defines the
#      __cxa_* runtime. wasi-sdk 34 does offer an eh/ multilib that does, but
#      building against it emits the WebAssembly exception-handling proposal,
#      which jco refuses to transpile - and jco is the route to the browser.
#      So: no exception handling, and the stubs satisfy the linker. See the
#      header comment of wasi_throw_stubs.cc for why that is sound here.
#
# EXTERNAL_CHIPDB is the load-bearing option. The chipdb is ~20 MB and is read
# from ${EXTERNAL_CHIPDB_ROOT} at run time, so the browser can fetch it
# separately instead of it being welded into the .wasm.
#
# Stages are separable so a failure isolates: boost | eigen | bba | nextpnr | all
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NEXTPNR_SRC="${NEXTPNR_SRC:-/mnt/i/Hotwright/eda-tools/nextpnr}"
WASI_SDK_PATH="${WASI_SDK_PATH:-/home/sc/wasi-sdk-34.0-x86_64-linux}"
BOOST="${HERE}/boost-1.81.0"
EIGEN="${HERE}/eigen-3.4.0"
STAGE="${1:-all}"

# Threading is experimental in the upstream recipe and unnecessary here.
WASI_TARGET="wasm32-wasip1"
WASI_SYSROOT="--sysroot ${WASI_SDK_PATH}/share/wasi-sysroot"
WASI_CFLAGS="-flto"
WASI_LDFLAGS="-flto -Wl,--strip-all"

[ -d "$WASI_SDK_PATH" ] || { echo "no wasi-sdk at $WASI_SDK_PATH" >&2; exit 1; }

toolchain() {
    cat > "${HERE}/Toolchain-WASI.cmake" <<END
cmake_minimum_required(VERSION 3.4...3.31)
set(WASI TRUE)
# WASI, not YoWASP's "Generic". nextpnr keys two things off this name:
# -DNPNR_DISABLE_THREADS (CMakeLists.txt's "STREQUAL WASI" branch, reached only
# when _REENTRANT is absent, which it is on the non-threads triple) and
# -lwasi-emulated-mman at link. Under "Generic" neither fires, find_package
# (Threads) succeeds against the HOST pthreads, and the build dies in
# placer1.cc on std::lock_guard - wasm32-wasi libc++ has no <mutex>.
set(CMAKE_SYSTEM_NAME WASI)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR wasm32)
set(CMAKE_C_COMPILER ${WASI_SDK_PATH}/bin/clang)
set(CMAKE_CXX_COMPILER ${WASI_SDK_PATH}/bin/clang++)
set(CMAKE_LINKER ${WASI_SDK_PATH}/bin/wasm-ld CACHE STRING "wasi build")
set(CMAKE_AR ${WASI_SDK_PATH}/bin/ar CACHE STRING "wasi build")
set(CMAKE_RANLIB ${WASI_SDK_PATH}/bin/ranlib CACHE STRING "wasi build")
set(CMAKE_C_COMPILER_TARGET ${WASI_TARGET})
set(CMAKE_CXX_COMPILER_TARGET ${WASI_TARGET})
set(CMAKE_C_FLAGS "${WASI_SYSROOT} ${WASI_CFLAGS}" CACHE STRING "wasi build")
set(CMAKE_CXX_FLAGS "${WASI_SYSROOT} ${WASI_CFLAGS}" CACHE STRING "wasi build")
set(CMAKE_EXE_LINKER_FLAGS "${WASI_LDFLAGS}" CACHE STRING "wasi build")
# The exception-runtime stubs must come AFTER the objects that reference them;
# CMAKE_EXE_LINKER_FLAGS is emitted before those, CMAKE_CXX_STANDARD_LIBRARIES
# after. Injecting the object here rather than patching nextpnr's CMakeLists
# keeps the stubs entirely on our side of the tree.
set(CMAKE_CXX_STANDARD_LIBRARIES "${HERE}/wasi_throw_stubs.o" CACHE STRING "wasi build")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
END
}

do_boost() {
    # Objects from an earlier SDK are not reusable - different LLVM major
    # version means incompatible LTO bitcode, and the defines have changed too.
    stamp="${BOOST}/.built-for"
    want="${WASI_SDK_PATH}|${WASI_TARGET}|${WASI_CFLAGS}"
    if [ -d "${BOOST}/stage" ] && [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
        echo "== boost: toolchain changed, discarding previous build"
        rm -rf "${BOOST}/bin.v2" "${BOOST}/stage" "$stamp"
    fi

    echo "== boost: b2 engine"
    # The parked note "blocked on b2 headers" was this: b2 is not shipped
    # prebuilt in the release tarball, it is bootstrapped from source natively.
    if [ ! -x "${BOOST}/tools/build/src/engine/b2" ]; then
        ( cd "${BOOST}/tools/build/src/engine" && ./build.sh )
    fi
    echo "== boost: configure for ${WASI_TARGET}"
    # BOOST_NO_CXX11_HDR_MUTEX is not optional at threading=single: without
    # -pthread there is no <mutex>, and boost::system's error_category_impl.hpp
    # uses std::mutex unless told the header does not exist, so
    # libboost_filesystem fails with "no type named 'mutex' in namespace 'std'".
    #
    # BOOST_NO_EXCEPTIONS is deliberately NOT set, unlike YoWASP's recipe: with
    # wasi-sdk 34 exceptions work, and defining it would oblige us to supply
    # boost::throw_exception ourselves.
    cat > "${BOOST}/project-config.jam" <<END
using clang : : ${WASI_SDK_PATH}/bin/clang++ --target=${WASI_TARGET} ${WASI_SYSROOT} ${WASI_CFLAGS} -D_WASI_EMULATED_MMAN -DBOOST_NO_CXX11_HDR_MUTEX ;
project : default-build <toolset>clang ;
libraries = --with-program_options --with-iostreams --with-filesystem --with-system ;
END
    echo "== boost: stage"
    ( cd "${BOOST}" && PATH="${WASI_SDK_PATH}/bin:$PATH" \
        ./tools/build/src/engine/b2 threading=single link=static stage )
    echo "$want" > "$stamp"
}

do_eigen() {
    if [ ! -d "${EIGEN}" ]; then
        echo "== eigen: fetch"
        curl -L https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz \
            | tar xzf - -C "${HERE}"
    fi
    echo "== eigen: install headers"
    cmake -B "${HERE}/eigen-build" -S "${EIGEN}" -DCMAKE_INSTALL_PREFIX="${HERE}/eigen-prefix"
    make -C "${HERE}/eigen-build" install
}

do_bba() {
    # bba-export builds the .bba -> .bin compiler for the HOST: it has to run
    # during the cross build, so it cannot itself be wasm.
    echo "== bba: native build"
    cmake -B "${HERE}/nextpnr-bba-build" -S "${NEXTPNR_SRC}/bba"
    cmake --build "${HERE}/nextpnr-bba-build" -j"$(nproc)"
}

do_stubs() {
    echo "== stubs: compile"
    "${WASI_SDK_PATH}/bin/clang++" --target="${WASI_TARGET}" ${WASI_SYSROOT} \
        -O2 -c "${HERE}/wasi_throw_stubs.cc" -o "${HERE}/wasi_throw_stubs.o"
}

do_nextpnr() {
    toolchain
    do_stubs
    # wasm32-wasip1 ships a stub libpthread, so find_package(Threads) succeeds
    # even though pthread_create always fails - and nextpnr then asks for a
    # Boost thread component we deliberately did not build. nextpnr's
    # find_package(Threads) is not REQUIRED, so CMake's own disable switch is
    # enough, and it makes Threads_FOUND agree with reality.
    echo "== nextpnr: configure"
    cmake -B "${HERE}/nextpnr-build" -S "${NEXTPNR_SRC}" \
        -DCMAKE_TOOLCHAIN_FILE="${HERE}/Toolchain-WASI.cmake" \
        -DCMAKE_PREFIX_PATH="${BOOST}/stage/" \
        -DBOOST_ROOT="${BOOST}" \
        -DEigen3_DIR="${HERE}/eigen-prefix/share/eigen3/cmake" \
        -DBBA_IMPORT="${HERE}/nextpnr-bba-build/bba-export.cmake" \
        -DCMAKE_DISABLE_FIND_PACKAGE_Threads=ON \
        -DSTATIC_BUILD=ON \
        -DBUILD_GUI=OFF \
        -DBUILD_PYTHON=OFF \
        -DBUILD_TESTS=OFF \
        -DEXTERNAL_CHIPDB=ON \
        -DEXTERNAL_CHIPDB_ROOT=/share \
        -DARCH="himbaechel" \
        -DHIMBAECHEL_SPLIT=ON \
        -DHIMBAECHEL_UARCH="xilinx" \
        -DHIMBAECHEL_PRJXRAY_DB=/mnt/i/Hotwright/0-xilinx-bits/xray-db-local \
        -DHIMBAECHEL_XILINX_DEVICES="${DEVICES:-xc7s25;xc7s50;xc7z010}"
    # cmake's bba rule lists only xilinx_gen.py and constids.inc as INPUTS, so a
    # changed prjxray database does not invalidate the chipdb. Delete it when
    # the database has moved (e.g. after re-running 074).
    # FORCE_CHIPDB names which chipdbs to discard: a ;-separated device list,
    # or 1 for all of them. Naming them matters - xc7s50's bba alone is 116 MB
    # and takes minutes, so regenerating it because xc7s25's database changed
    # is pure waste. "1" stays the safe answer when unsure.
    if [ -n "${FORCE_CHIPDB:-}" ]; then
        if [ "${FORCE_CHIPDB}" = 1 ]; then _fc='*'; else _fc="${FORCE_CHIPDB}"; fi
        for _d in $( echo "$_fc" | tr ';' ' ' ); do
            rm -f "${HERE}"/nextpnr-build/himbaechel/uarch/xilinx/chipdb-$_d.bb[a] \
                  "${HERE}"/nextpnr-build/himbaechel/uarch/xilinx/chipdb-$_d.bin \
                  "${HERE}"/nextpnr-build/share/himbaechel/xilinx/chipdb-$_d.bin
        done
    fi
    echo "== nextpnr: build"
    cmake --build "${HERE}/nextpnr-build" -j"$(nproc)"
}

case "$STAGE" in
    boost)   do_boost ;;
    stubs)   do_stubs ;;
    eigen)   do_eigen ;;
    bba)     do_bba ;;
    nextpnr) do_nextpnr ;;
    all)     do_boost; do_eigen; do_bba; do_nextpnr ;;
    *) echo "usage: $0 [boost|eigen|bba|stubs|nextpnr|all]" >&2; exit 1 ;;
esac
echo "== ${STAGE}: ok"
