#ifndef MACH_DXC_H_
#define MACH_DXC_H_

#ifdef __cplusplus
extern "C" {
#endif

#if defined(DXC_C_SHARED_LIBRARY)
#    if defined(_WIN32)
#        if defined(DXC_C_IMPLEMENTATION)
#            define DXC_EXPORT __declspec(dllexport)
#        else
#            define DXC_EXPORT __declspec(dllimport)
#        endif
#    else  // defined(_WIN32)
#        if defined(DXC_C_IMPLEMENTATION)
#            define DXC_EXPORT __attribute__((visibility("default")))
#        else
#            define DXC_EXPORT
#        endif
#    endif  // defined(_WIN32)
#else       // defined(DXC_C_SHARED_LIBRARY)
#    define DXC_EXPORT
#endif  // defined(DXC_C_SHARED_LIBRARY)

#if !defined(OBJECT_ATTRIBUTE)
#define OBJECT_ATTRIBUTE
#endif

#define LPCWSTR const wchar_t*
#include <stddef.h>

typedef struct DxcCompilerImpl* DxcCompiler OBJECT_ATTRIBUTE;
typedef struct DxcCompileResultImpl* DxcCompileResult OBJECT_ATTRIBUTE;
typedef struct DxcCompileErrorImpl* DxcCompileError OBJECT_ATTRIBUTE;
typedef struct DxcCompileObjectImpl* DxcCompileObject OBJECT_ATTRIBUTE;


typedef struct DxcIncludeResultImpl {
    LPCWSTR header_data; // UTF-8 or null
    size_t header_length;
} DxcIncludeResult;

typedef DxcIncludeResult* (*DxcIncludeFunc)(void* ctx, LPCWSTR header_name);

typedef int (*DxcFreeIncludeFunc)(void* ctx, DxcIncludeResult* result);

typedef struct DxcIncludeCallbacksImpl {
    void* include_ctx;
    DxcIncludeFunc include_func;
    DxcFreeIncludeFunc free_func;
} DxcIncludeCallbacks;


typedef struct DxcCompileOptionsImpl {
    // Required
    LPCWSTR code;
    size_t code_len;

    LPCWSTR* args;
    size_t args_len;

    // Optional
    DxcIncludeCallbacks* include_callbacks; // nullable
} DxcCompileOptions;


//----------------
// DxcCompiler
//----------------

/// Initializes a DXC compiler
///
/// Invoke DxcFinalize when done with the compiler.
DXC_EXPORT DxcCompiler DxcInitialize();

/// Deinitializes the DXC compiler.
DXC_EXPORT void DxcFinalize(DxcCompiler compiler);

//---------------------
// DxcCompileResult
//---------------------

/// Compiles the given code with the given dxc.exe CLI arguments
///
/// Invoke DxcCompileResultDeinit when done with the result.
DXC_EXPORT DxcCompileResult DxcCompile(
    DxcCompiler compiler,
    DxcCompileOptions* options
);

/// Returns an error object, or null in the case of success.
///
/// Invoke DxcCompileErrorDeinit when done with the error, iff it was non-null.
DXC_EXPORT DxcCompileError DxcCompileResultGetError(DxcCompileResult err);

/// Returns the compiled object code, or null if an error occurred.
DXC_EXPORT DxcCompileObject DxcCompileResultGetObject(DxcCompileResult err);

/// Deinitializes the DXC compiler.
DXC_EXPORT void DxcCompileResultRelease(DxcCompileResult err);

//---------------------
// DxcCompileObject
//---------------------

/// Returns a pointer to the raw bytes of the compiled object file.
DXC_EXPORT char const* DxcCompileObjectGetBytes(DxcCompileObject err);

/// Returns the length of the compiled object file.
DXC_EXPORT size_t DxcCompileObjectGetBytesLength(DxcCompileObject err);

/// Deinitializes the compiled object, calling Get methods after this is illegal.
DXC_EXPORT void DxcCompileObjectRelease(DxcCompileObject err);

//--------------------
// DxcCompileError
//--------------------

/// Returns a pointer to a wide error string. This includes
/// compiler warnings, unless they were disabled in the compile arguments.
DXC_EXPORT LPCWSTR DxcCompileErrorGetString(DxcCompileError err);

/// Returns the length of the error string.
DXC_EXPORT size_t DxcCompileErrorGetStringLength(DxcCompileError err);

/// Deinitializes the error, calling Get methods after this is illegal.
DXC_EXPORT void DxcCompileErrorRelease(DxcCompileError err);

#ifdef __cplusplus
} // extern "C"
#endif

#endif  // MACH_DXC_H_
