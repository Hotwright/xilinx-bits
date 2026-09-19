// Exception-runtime stubs for the WASI build of nextpnr.
//
// Why this exists
// ---------------
// Three constraints meet here and only this satisfies all three:
//
//   1. nextpnr throws. log_error() prints its message and then throws
//      log_execution_error_exception; 45 of the 57 objects in this build
//      reference __cxa_throw.
//   2. wasi-sdk's no-exception-handling sysroot - the default multilib, and the
//      ONLY one wasi-sdk 22 shipped - defines none of the __cxa_* runtime.
//   3. The eh/ multilib does define them, but building against it emits the
//      WebAssembly exception-handling proposal, and jco cannot read that:
//      "exceptions proposal not enabled". jco is how this module becomes
//      something @yowasp/runtime can run, which is how it reaches the browser.
//
// So the module is built without exception handling and these stubs satisfy the
// linker. Compiling with exceptions enabled but linking a runtime that cannot
// unwind means `throw` terminates the program instead of transferring control.
//
// Why that is acceptable here, and where it is not
// ------------------------------------------------
// Every throw in this build leads to a fatal path. The catch sites are
// command.cc's and placer1.cc's top-level "catch (log_execution_error_exception)",
// himbaechel/arch.cc's "catch (...)" around opening the chipdb, and
// util.h's "catch (std::invalid_argument)" - and every one of them responds by
// calling log_error, which is itself fatal. Nothing catches an exception and
// carries on, so no successful run can reach this code.
//
// The message is not lost: log_error prints before it throws. What is lost is
// the tidy epilogue and the exit status - the process exits here instead of
// unwinding to main. exit(1) rather than abort() is deliberate: it gives the
// WASI host a clean non-zero exit rather than a trap, which is much easier to
// report in a browser.
//
// If nextpnr ever starts using exceptions for control flow, this becomes wrong
// and silently so. The guard against that is diff_native.mjs: the WASM build
// must produce byte-identical FASM to the native one, which it cannot do if it
// exits early.
#include <cstdlib>
#include <cstddef>

extern "C" {

void *__cxa_allocate_exception(size_t) { return std::malloc(128); }
void __cxa_free_exception(void *p) { std::free(p); }

void __cxa_throw(void *, void *, void (*)(void *)) { std::exit(1); }
void __cxa_rethrow() { std::exit(1); }

// Reached only while unwinding, which cannot happen once __cxa_throw exits.
void *__cxa_begin_catch(void *) { std::exit(1); }
void __cxa_end_catch() {}
void *__cxa_current_exception_type() { return nullptr; }
int __gxx_personality_v0(...) { std::exit(1); }
void _Unwind_Resume(void *) { std::exit(1); }

}
