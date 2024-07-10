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

#include <stddef.h>

typedef struct dxc_compiler_impl* dxc_compiler OBJECT_ATTRIBUTE;
typedef struct dxc_compile_result_impl* dxc_compile_result OBJECT_ATTRIBUTE;
typedef struct dxc_compile_error_impl* dxc_compile_error OBJECT_ATTRIBUTE;
typedef struct dxc_compile_object_impl* dxc_compile_object OBJECT_ATTRIBUTE;


typedef struct dxc_include_result {
    const char* header_data; // UTF-8 or null
    size_t header_length;
} dxc_include_result;

typedef dxc_include_result* (*dxc_include_func)(void* ctx, const char* header_name);

typedef int (*dxc_free_include_func)(void* ctx, dxc_include_result* result);

typedef struct dxc_include_callbacks {
    void* include_ctx;
    dxc_include_func include_func;
    dxc_free_include_func free_func;
} dxc_include_callbacks;


typedef struct dxc_compile_options {
    // Required
    char const* code;
    size_t code_len;
    char const* const* args;
    size_t args_len;

    // Optional
    dxc_include_callbacks* include_callbacks; // nullable
} dxc_compile_options;


//----------------
// dxc_compiler
//----------------

/// Initializes a DXC compiler
///
/// Invoke machDxcDeinit when done with the compiler.
DXC_EXPORT dxc_compiler dxc_initialize();

/// Deinitializes the DXC compiler.
DXC_EXPORT void dxc_finalize(dxc_compiler compiler);

//---------------------
// dxc_compile_result
//---------------------

/// Compiles the given code with the given dxc.exe CLI arguments
///
/// Invoke DxcCompileResultDeinit when done with the result.
DXC_EXPORT dxc_compile_result dxc_compile(
    dxc_compiler compiler,
    dxc_compile_options* options
);

/// Returns an error object, or null in the case of success.
///
/// Invoke DxcCompileErrorDeinit when done with the error, iff it was non-null.
DXC_EXPORT dxc_compile_error dxc_compile_result_get_error(dxc_compile_result err);

/// Returns the compiled object code, or null if an error occurred.
DXC_EXPORT dxc_compile_object dxc_compile_result_get_object(dxc_compile_result err);

/// Deinitializes the DXC compiler.
DXC_EXPORT void dxc_compile_result_deinit(dxc_compile_result err);

//---------------------
// dxc_compile_object
//---------------------

/// Returns a pointer to the raw bytes of the compiled object file.
DXC_EXPORT char const* dxc_compile_object_get_bytes(dxc_compile_object err);

/// Returns the length of the compiled object file.
DXC_EXPORT size_t dxc_compile_object_get_bytes_length(dxc_compile_object err);

/// Deinitializes the compiled object, calling Get methods after this is illegal.
DXC_EXPORT void dxc_compile_object_deinit(dxc_compile_object err);

//--------------------
// dxc_compile_error
//--------------------

/// Returns a pointer to the null-terminated UTF-8 encoded error string. This includes
/// compiler warnings, unless they were disabled in the compile arguments.
DXC_EXPORT char const* dxc_compile_error_get_string(dxc_compile_error err);

/// Returns the length of the error string.
DXC_EXPORT size_t dxc_compile_error_get_string_length(dxc_compile_error err);

/// Deinitializes the error, calling Get methods after this is illegal.
DXC_EXPORT void dxc_compile_error_deinit(dxc_compile_error err);

#ifdef __cplusplus
} // extern "C"
#endif

#endif  // MACH_DXC_H_
