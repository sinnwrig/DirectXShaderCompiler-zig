///////////////////////////////////////////////////////////////////////////////
//                                                                           //
// dxc.cpp                                                                   //
// Copyright (C) Microsoft Corporation. All rights reserved.                 //
// This file is distributed under the University of Illinois Open Source     //
// License. See LICENSE.TXT for details.                                     //
//                                                                           //
// Provides the entry point for the dxc console program.                     //
//                                                                           //
///////////////////////////////////////////////////////////////////////////////

#include "dxclib/dxc.h"

// Mach change start
// #ifdef _WIN32
#if defined(_WIN32) && !defined(__clang__)
// Mach change end
int __cdecl wmain(int argc, const wchar_t **argv_) {
  return dxc::main(argc, argv_);
#else
int main(int argc, const char **argv_) {
  return dxc::main(argc, argv_);
#endif // _WIN32
}
