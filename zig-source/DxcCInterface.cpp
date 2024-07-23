// TODO: investigate if we can eliminate this for Windows builds
#ifdef _WIN32
    #ifdef _MSC_VER
        #define __C89_NAMELESS
        #define __C89_NAMELESSUNIONNAME
        #define WIN32_LEAN_AND_MEAN
        #include <windows.h>
        #include <wrl/client.h>
        #define CComPtr Microsoft::WRL::ComPtr
    #else // _MSC_VER
        #include <windows.h>
        #include <wrl/client.h>
    #endif // _MSC_VER
#endif // _WIN32

// Avoid __declspec(dllimport) since dxcompiler is static.
#define DXC_API_IMPORT
#include <dxcapi.h>
#include <cassert>
#include <stddef.h>
#include <string>
#include <iostream>

#include "DxcCInterface.h"

#ifdef __cplusplus
extern "C" {
#endif

// Provides a way for C applications to override file inclusion by offloading it to a function pointer
class DelegateIncludeHandler : public IDxcIncludeHandler 
{
public:
    ULONG STDMETHODCALLTYPE AddRef() override { return 0; }
    ULONG STDMETHODCALLTYPE Release() override { return 0; }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppvObject) override {
        if (riid == __uuidof(IDxcIncludeHandler) || riid == __uuidof(IUnknown)) {
            *ppvObject = this;
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }

    DxcIncludeCallbacks* callbacks;
    IDxcUtils* utils;

    DelegateIncludeHandler(DxcIncludeCallbacks* callbacks_ptr, IDxcUtils* util_ptr) { 
        callbacks = callbacks_ptr;
        utils = util_ptr;
    }

    HRESULT STDMETHODCALLTYPE LoadSource(LPCWSTR filename, IDxcBlob **ppIncludeSource) override {
        if (callbacks->include_func == nullptr || callbacks->free_func == nullptr)
            return E_POINTER;

        DxcIncludeResult* include_result = callbacks->include_func(callbacks->include_ctx, filename);

        LPCWSTR include_text = include_result != nullptr && include_result->header_data != nullptr ? include_result->header_data : L"";
        size_t include_len = include_result != nullptr ? include_result->header_length : 0;

        CComPtr<IDxcBlobEncoding> text_blob;
        HRESULT result = utils->CreateBlob(include_text, include_len, DXC_CP_UTF16, &text_blob);

        if (SUCCEEDED(result)) 
            *ppIncludeSource = text_blob.Detach();
            
        callbacks->free_func(callbacks->include_ctx, include_result);

        return S_OK;
    }
};  


// Mach change start: static dxcompiler/dxil
BOOL DxcompilerInvokeDllMain();
void DxcompilerInvokeDllShutdown();

//----------------
// DxcCompiler
//----------------
DXC_EXPORT DxcCompiler DxcInitialize() {
    DxcompilerInvokeDllMain();
    CComPtr<IDxcCompiler3> dxcInstance;
    HRESULT hr = DxcCreateInstance(CLSID_DxcCompiler, IID_PPV_ARGS(&dxcInstance));
    assert(SUCCEEDED(hr));
    return reinterpret_cast<DxcCompiler>(dxcInstance.Detach());
}

DXC_EXPORT void DxcFinalize(DxcCompiler compiler) {
    CComPtr<IDxcCompiler3> dxcInstance = CComPtr(reinterpret_cast<IDxcCompiler3*>(compiler));
    dxcInstance.Release();
    DxcompilerInvokeDllShutdown();
}

//---------------------
// DxcCompileResult
//---------------------
DXC_EXPORT DxcCompileResult DxcCompile(
    DxcCompiler compiler,
    DxcCompileOptions* options
) {
    CComPtr<IDxcCompiler3> dxcInstance = CComPtr(reinterpret_cast<IDxcCompiler3*>(compiler));

    CComPtr<IDxcUtils> pUtils;
    DxcCreateInstance(CLSID_DxcUtils, IID_PPV_ARGS(&pUtils));

    CComPtr<IDxcBlobEncoding> pSource;
    pUtils->CreateBlob(options->code, options->code_len, DXC_CP_UTF8, &pSource);

    DxcBuffer sourceBuffer;
    sourceBuffer.Ptr = pSource->GetBufferPointer();
    sourceBuffer.Size = pSource->GetBufferSize();
    sourceBuffer.Encoding = 0;

    DelegateIncludeHandler* handler = nullptr;
    if (options->include_callbacks != nullptr) // Leave include handler as default (nullptr) unless there's available callbacks
        handler = new DelegateIncludeHandler(options->include_callbacks, pUtils);

    CComPtr<IDxcResult> pCompileResult;
    HRESULT hr = dxcInstance->Compile(
        &sourceBuffer,
        options->args,
        (uint32_t)options->args_len,
        handler,
        IID_PPV_ARGS(&pCompileResult)
    );

    if (handler != nullptr)
        delete handler;

    assert(SUCCEEDED(hr));

    return reinterpret_cast<DxcCompileResult>(pCompileResult.Detach());
}

DXC_EXPORT DxcCompileError DxcCompileResultGetError(DxcCompileResult result) {
    CComPtr<IDxcResult> pCompileResult = CComPtr(reinterpret_cast<IDxcResult*>(result));
    CComPtr<IDxcBlobWide> pErrors;
    
    pCompileResult->GetOutput(DXC_OUT_ERRORS, IID_PPV_ARGS(&pErrors), nullptr);

    if (pErrors && pErrors->GetStringLength() > 0) {
        return reinterpret_cast<DxcCompileError>(pErrors.Detach());
    }
    
    return nullptr;
}

DXC_EXPORT DxcCompileObject DxcCompileResultGetObject(DxcCompileResult result) {
    CComPtr<IDxcResult> pCompileResult = CComPtr(reinterpret_cast<IDxcResult*>(result));
    CComPtr<IDxcBlob> pObject;

    pCompileResult->GetOutput(DXC_OUT_OBJECT, IID_PPV_ARGS(&pObject), nullptr);

    if (pObject && pObject->GetBufferSize() > 0) {
        return reinterpret_cast<DxcCompileObject>(pObject.Detach());
    }
    return nullptr;
}

DXC_EXPORT void DxcCompileResultRelease(DxcCompileResult result) {
    CComPtr<IDxcResult> pCompileResult = CComPtr(reinterpret_cast<IDxcResult*>(result));
    pCompileResult.Release();
}

//---------------------
// DxcCompileObject
//---------------------
DXC_EXPORT char const* DxcCompileObjectGetBytes(DxcCompileObject object) {
    CComPtr<IDxcBlob> pObject = CComPtr(reinterpret_cast<IDxcBlob*>(object));
    return (char const*)(pObject->GetBufferPointer());
}

DXC_EXPORT size_t DxcCompileObjectGetBytesLength(DxcCompileObject object) {
    CComPtr<IDxcBlob> pObject = CComPtr(reinterpret_cast<IDxcBlob*>(object));
    return pObject->GetBufferSize();
}

DXC_EXPORT void DxcCompileObjectRelease(DxcCompileObject object) {
    CComPtr<IDxcBlob> pObject = CComPtr(reinterpret_cast<IDxcBlob*>(object));
    pObject.Release();
}

//--------------------
// DxcCompileError
//--------------------
DXC_EXPORT char const* DxcCompileErrorGetString(DxcCompileError err) {
    CComPtr<IDxcBlobUtf8> pErrors = CComPtr(reinterpret_cast<IDxcBlobUtf8*>(err));
    return (char const*)(pErrors->GetBufferPointer());
}

DXC_EXPORT size_t DxcCompileErrorGetStringLength(DxcCompileError err) {
    CComPtr<IDxcBlobUtf8> pErrors = CComPtr(reinterpret_cast<IDxcBlobUtf8*>(err));
    return pErrors->GetStringLength();
}

DXC_EXPORT void DxcCompileErrorRelease(DxcCompileError err) {
    CComPtr<IDxcBlobUtf8> pErrors = CComPtr(reinterpret_cast<IDxcBlobUtf8*>(err));
    pErrors.Release();
}

#ifdef __cplusplus
} // extern "C"
#endif
