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
set(CMAKE_C_COMPILER /home/sc/wasi-sdk-34.0-x86_64-linux/bin/clang)
set(CMAKE_CXX_COMPILER /home/sc/wasi-sdk-34.0-x86_64-linux/bin/clang++)
set(CMAKE_LINKER /home/sc/wasi-sdk-34.0-x86_64-linux/bin/wasm-ld CACHE STRING "wasi build")
set(CMAKE_AR /home/sc/wasi-sdk-34.0-x86_64-linux/bin/ar CACHE STRING "wasi build")
set(CMAKE_RANLIB /home/sc/wasi-sdk-34.0-x86_64-linux/bin/ranlib CACHE STRING "wasi build")
set(CMAKE_C_COMPILER_TARGET wasm32-wasip1)
set(CMAKE_CXX_COMPILER_TARGET wasm32-wasip1)
set(CMAKE_C_FLAGS "--sysroot /home/sc/wasi-sdk-34.0-x86_64-linux/share/wasi-sysroot -flto" CACHE STRING "wasi build")
set(CMAKE_CXX_FLAGS "--sysroot /home/sc/wasi-sdk-34.0-x86_64-linux/share/wasi-sysroot -flto" CACHE STRING "wasi build")
set(CMAKE_EXE_LINKER_FLAGS "-flto -Wl,--strip-all" CACHE STRING "wasi build")
# The exception-runtime stubs must come AFTER the objects that reference them;
# CMAKE_EXE_LINKER_FLAGS is emitted before those, CMAKE_CXX_STANDARD_LIBRARIES
# after. Injecting the object here rather than patching nextpnr's CMakeLists
# keeps the stubs entirely on our side of the tree.
set(CMAKE_CXX_STANDARD_LIBRARIES "/mnt/i/Hotwright/0-xilinx-bits/wasm-build/wasi_throw_stubs.o" CACHE STRING "wasi build")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
