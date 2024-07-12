# DirectX Shader Compiler built with Zig

## Overview

This repository is a fork of Microsoft's [DirectXShaderCompiler](https://github.com/microsoft/DirectXShaderCompiler) modified to allow cross-platform and static building powered by Zig's build system. Zig enables _DXC_ to be built in a much more straightforward way, by combining several cross-platform compiler toolchains into one buildsystem powered by a single build language.<br> 

Much to all of the work needed to do this was made possible by the [Mach Engine](https://github.com/hexops/mach) and their own fork of [DXC](https://github.com/hexops/DirectXShaderCompiler) and [DXC Built with Zig](https://github.com/hexops/mach-dxcompiler), which fixes several annoying quirks that make _DXC_ difficult to compile as a static or dynamic library for Windows, Linux, and MacOS. In fact, this repository still relies on several external libraries that have been modified to work with Zig, provided by Stephen Gutekanst (the creator of mach-dxcompiler) and the folks at Hexops. 

### Differences from microsoft/DirectXShaderCompiler

As a result of the wonderful work by the people behind _mach-dxcompiler_, DXC can now be built for multiple platforms using Zig as its build-system (See Stephen Gutekanst's ['Building the DirectX shader compiler better than Microsoft?'](https://devlog.hexops.com/2024/building-the-directx-shader-compiler-better-than-microsoft/) for details on what they do different). Some of the biggest differences are a removal of the dependency on _dxil.dll_, a proprietry code-signing blob, and changes to make _DXC_ correctly work as a static library. 

Differences between _mach-dxcompiler_ and _DirectXShaderCompiler_:
- Add support for building a statically linked dxcompiler library and dxc executables.
- Removal of dependency on proprietary dxil.dll code-signing blob (see: [Mach Siegbert Vogt DXCSA](https://github.com/hexops/DirectXShaderCompiler/blob/main/tools/clang/tools/dxcompiler/MachSiegbertVogtDXCSA.cpp#L178))
- Additional support for macOS and aarch64 Linux binaries.
- Addition of C API as an alternative to the traditional COM API.

### Differences from hexops/dxc and mach-dxcompiler

Unfortunately, the Hexops fork of DXC does not attempt to keep up-to-date with source DXC and is primarily designed to serve the purpose of a DXIL bytecode generator for the Mach Engine and not as a standalone library. As such, it lacks features such as SPIR-V bytecode generation, which are essential for developers seeking to cross-compile HLSL for several platforms.<br>

Mach also does not integrate the zig buildsystem directly with _DXC_ source and keeps their buildsystem one level above. This project will instead attempt to integrate directly into _DXC_ and maintain relatively up-to-date with upstream _DXC_ as long as there are no issues. It will provide the option to build with SPIR-V bytecode generation, and modify the C API to adopt the general DXC naming conventions.<br>

Differences between _DirectXShaderCompiler-zig_ and _mach-dxcompiler_:
- Direct integration of build.zig file into _DXC_ source repository.
- Options to enable SPIR-V bytecode generation.
- Attempts to keep up-to-date with upstream DXC and SPIRV-Tools (at the potential detriment to stability).
- Renamed the C API and internal functions to follow a more general _DXC/C_ naming convention.
- Removed MSVC and DIA SDK builds due to the lack of support these libraries have for non-windows platforms. PRs welcome which re-add support for them, but I am uninterested and currently unable to add support for them from Linux.
- Moved SPIRV-Tools external dependency from [hexops/spirv-tools](https://github.com/hexops/spirv-tools) to [SPIRV-Tools-zig](https://github.com/sinnwrig/SPIRV-Tools-zig).
- Addition of `-Dregenerate_headers` flag, which rebuilds python generated and tablegen'ned headers used by LLVM, Clang, and DXC into _generated-include_.