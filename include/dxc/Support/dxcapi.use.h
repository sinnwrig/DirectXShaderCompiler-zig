//////////////////////////////////////////////////////////////////////////////
//                                                                           //
// dxcapi.use.h                                                              //
// Copyright (C) Microsoft Corporation. All rights reserved.                 //
// This file is distributed under the University of Illinois Open Source     //
// License. See LICENSE.TXT for details.                                     //
//                                                                           //
// Provides support for DXC API users.                                       //
//                                                                           //
///////////////////////////////////////////////////////////////////////////////

#ifndef __DXCAPI_USE_H__
#define __DXCAPI_USE_H__

#include "dxc/dxcapi.h"

// Mach change start: static dxcompiler/dxil
#include <string>
// Mach change end

namespace dxc {

extern const char *kDxCompilerLib;
extern const char *kDxilLib;

// Mach change start: static dxcompiler/dxil
extern "C" BOOL MachDxcompilerInvokeDllMain();
extern "C" void MachDxcompilerInvokeDllShutdown();
static bool dxcompiler_dll_loaded = false;
// Mach change end

// Helper class to dynamically load the dxcompiler or a compatible libraries.
class DxcDllSupport {
protected:
  // Mach change start: static dxcompiler/dxil
  BOOL m_initialized;
  std::string m_dllName;
  // Mach change end
  HMODULE m_dll;
  DxcCreateInstanceProc m_createFn;
  DxcCreateInstance2Proc m_createFn2;

// Mach change start: static dxcompiler/dxil
//   HRESULT InitializeInternal(LPCSTR dllName, LPCSTR fnName) {
//     if (m_dll != nullptr)
//       return S_OK;

// #ifdef _WIN32
//     m_dll = LoadLibraryA(dllName);
//     if (m_dll == nullptr)
//       return HRESULT_FROM_WIN32(GetLastError());
//     m_createFn = (DxcCreateInstanceProc)GetProcAddress(m_dll, fnName);

//     if (m_createFn == nullptr) {
//       HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
//       FreeLibrary(m_dll);
//       m_dll = nullptr;
//       return hr;
//     }
// #else
//     m_dll = ::dlopen(dllName, RTLD_LAZY);
//     if (m_dll == nullptr)
//       return E_FAIL;
//     m_createFn = (DxcCreateInstanceProc)::dlsym(m_dll, fnName);

//     if (m_createFn == nullptr) {
//       ::dlclose(m_dll);
//       m_dll = nullptr;
//       return E_FAIL;
//     }
// #endif

//     // Only basic functions used to avoid requiring additional headers.
//     m_createFn2 = nullptr;
//     char fnName2[128];
//     size_t s = strlen(fnName);
//     if (s < sizeof(fnName2) - 2) {
//       memcpy(fnName2, fnName, s);
//       fnName2[s] = '2';
//       fnName2[s + 1] = '\0';
// #ifdef _WIN32
//       m_createFn2 = (DxcCreateInstance2Proc)GetProcAddress(m_dll, fnName2);
// #else
//       m_createFn2 = (DxcCreateInstance2Proc)::dlsym(m_dll, fnName2);
// #endif
//     }

//     return S_OK;
//   }
  HRESULT InitializeInternal(LPCSTR dllName, LPCSTR fnName) {
    // The compilation process occurs as follows:
    //
    // 1. Compilation begins
    // 2. InitializeInternal(kDxCompilerLib, "DxcCreateInstance") is called
    // 3. MachDxcompilerInvokeDllMain() is invoked..
    //   3a. which calls dxcompiler.dll's DllMain entrypoint
    //   3b. which triggers loading of dxil.dll
    // 4. InitializeInternal(kDxilLib, "DxcCreateInstance") is called
    //   4a. E_FAIL is returned, indicating dxil.dll is not present
    //   4b. We silence the warning related to dxil.dll not being present and
    //       code signing not occuring (commented out)
    // 5. We perform Mach Siegbert Vogt DXCSA on the final container/blob before the
    //    compiler writes it to disk.
    //
    // Look for "DXCSA" in the codebase to see where signing happens.

    // Store which DLL this is for later, so we can MachDxcompilerInvokeDllShutdown later.
    m_dllName = dllName;

    // If this is dxil.dll, emulate that we do not have it.
    if (strcmp(dllName, kDxilLib) == 0) {
      return E_FAIL;
    }

    // If this is dxcompiler.dll, emulate as if we loaded it in-process.
    if (strcmp(fnName, "DxcCreateInstance") == 0) {
      m_initialized = true;
      m_createFn = &DxcCreateInstance;
      m_createFn2 = &DxcCreateInstance2;

      // If this is the first time this is called, invoke DllMain() 
      if (!dxcompiler_dll_loaded) {
        if (!MachDxcompilerInvokeDllMain()) {
          fprintf(stderr, "mach-dxcompiler: MachDxcompilerInvokeDllMain failed\n");
          return E_FAIL;
        }
        dxcompiler_dll_loaded = true;
      }
      return S_OK;
    }
    fprintf(stderr, "mach-dxcompiler: InitializeInternal: unknown GetProcAddress name: %s\n", fnName);
    return E_FAIL;
  }
// Mach change end

public:
  // Mach change start: static dxcompiler/dxil
  // DxcDllSupport() : m_dll(nullptr), m_createFn(nullptr), m_createFn2(nullptr) {}
  DxcDllSupport() : m_initialized(false), m_dll(nullptr), m_createFn(nullptr), m_createFn2(nullptr) {}
  // Mach change end

  DxcDllSupport(DxcDllSupport &&other) {
    // Mach change start: static dxcompiler/dxil
    m_initialized = other.m_initialized;
    other.m_initialized = false;
    m_dllName = other.m_dllName;
    other.m_dllName = nullptr;
    // Mach change end
    m_dll = other.m_dll;
    other.m_dll = nullptr;
    m_createFn = other.m_createFn;
    other.m_createFn = nullptr;
    m_createFn2 = other.m_createFn2;
    other.m_createFn2 = nullptr;
  }

  ~DxcDllSupport() { Cleanup(); }

  HRESULT Initialize() {
    return InitializeInternal(kDxCompilerLib, "DxcCreateInstance");
  }

  HRESULT InitializeForDll(LPCSTR dll, LPCSTR entryPoint) {
    return InitializeInternal(dll, entryPoint);
  }

  template <typename TInterface>
  HRESULT CreateInstance(REFCLSID clsid, TInterface **pResult) {
    return CreateInstance(clsid, __uuidof(TInterface), (IUnknown **)pResult);
  }

  HRESULT CreateInstance(REFCLSID clsid, REFIID riid, IUnknown **pResult) {
    if (pResult == nullptr)
      return E_POINTER;
    // Mach change start: static dxcompiler/dxil
    // if (m_dll == nullptr)
    if (!m_initialized)
    // Mach change end
      return E_FAIL;
    HRESULT hr = m_createFn(clsid, riid, (LPVOID *)pResult);
    return hr;
  }

  template <typename TInterface>
  HRESULT CreateInstance2(IMalloc *pMalloc, REFCLSID clsid,
                          TInterface **pResult) {
    return CreateInstance2(pMalloc, clsid, __uuidof(TInterface),
                           (IUnknown **)pResult);
  }

  HRESULT CreateInstance2(IMalloc *pMalloc, REFCLSID clsid, REFIID riid,
                          IUnknown **pResult) {
    if (pResult == nullptr)
      return E_POINTER;
    // Mach change start: static dxcompiler/dxil
    // if (m_dll == nullptr)
    if (!m_initialized)
    // Mach change end
      return E_FAIL;
    if (m_createFn2 == nullptr)
      return E_FAIL;
    HRESULT hr = m_createFn2(pMalloc, clsid, riid, (LPVOID *)pResult);
    return hr;
  }

  bool HasCreateWithMalloc() const { return m_createFn2 != nullptr; }

  // Mach change start: static dxcompiler/dxil
  // bool IsEnabled() const { return m_dll != nullptr; }
  bool IsEnabled() const { return m_initialized; }
  // Mach change start

  void Cleanup() {
    // Mach change start: static dxcompiler/dxil
    if (m_dllName == kDxCompilerLib && dxcompiler_dll_loaded) {
      dxcompiler_dll_loaded = false;
      MachDxcompilerInvokeDllShutdown();
    }
    // Mach change end
    if (m_dll != nullptr) {
      m_createFn = nullptr;
      m_createFn2 = nullptr;
#ifdef _WIN32
      FreeLibrary(m_dll);
#else
      ::dlclose(m_dll);
#endif
      m_dll = nullptr;
    }
  }

  // Mach change start: static dxcompiler/dxil
  // HMODULE Detach() {
  //   HMODULE hModule = m_dll;
  //   m_dll = nullptr;
  //   return hModule;
  // }
  void Detach() { m_initialized = false; }
  // Mach change end
};

inline DxcDefine GetDefine(LPCWSTR name, LPCWSTR value) {
  DxcDefine result;
  result.Name = name;
  result.Value = value;
  return result;
}

// Checks an HRESULT and formats an error message with the appended data.
void IFT_Data(HRESULT hr, LPCWSTR data);

void EnsureEnabled(DxcDllSupport &dxcSupport);
void ReadFileIntoBlob(DxcDllSupport &dxcSupport, LPCWSTR pFileName,
                      IDxcBlobEncoding **ppBlobEncoding);
void WriteBlobToConsole(IDxcBlob *pBlob, DWORD streamType = STD_OUTPUT_HANDLE);
void WriteBlobToFile(IDxcBlob *pBlob, LPCWSTR pFileName, UINT32 textCodePage);
void WriteBlobToHandle(IDxcBlob *pBlob, HANDLE hFile, LPCWSTR pFileName,
                       UINT32 textCodePage);
void WriteUtf8ToConsole(const char *pText, int charCount,
                        DWORD streamType = STD_OUTPUT_HANDLE);
void WriteUtf8ToConsoleSizeT(const char *pText, size_t charCount,
                             DWORD streamType = STD_OUTPUT_HANDLE);
void WriteOperationErrorsToConsole(IDxcOperationResult *pResult,
                                   bool outputWarnings);
void WriteOperationResultToConsole(IDxcOperationResult *pRewriteResult,
                                   bool outputWarnings);

} // namespace dxc

#endif
