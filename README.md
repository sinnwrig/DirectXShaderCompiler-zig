# DirectX Shader Compiler built with Zig

This repository is a fork of Microsoft's [DirectXShaderCompiler](https://github.com/microsoft/DirectXShaderCompiler) modified to allow cross-platform and static building powered by Zig's build system. Zig enables _DXC_ to be built in a much more straightforward way, by combining several cross-platform compiler toolchains into one buildsystem powered by a single build language.<br> 

Much to all of the work needed to do this was made possible by the [Mach Engine](https://github.com/hexops/mach) and their own fork of [DXC](https://github.com/hexops/DirectXShaderCompiler) and [DXC Built with Zig](https://github.com/hexops/mach-dxcompiler), which fixes several annoying quirks that make _DXC_ difficult to compile as a static or dynamic library for Windows, Linux, and MacOS. In fact, this repository still relies on several external libraries that have been modified to work with Zig, provided by Stephen Gutekanst (the creator of mach-dxcompiler) and the folks at Hexops. 

### Differences from microsoft/DirectXShaderCompiler

As a result of the wonderful work by the people behind _mach-dxcompiler_, DXC can now be built for multiple platforms using Zig as its build-system (See Stephen Gutekanst's ['Building the DirectX shader compiler better than Microsoft?'](https://devlog.hexops.com/2024/building-the-directx-shader-compiler-better-than-microsoft/) for details on what they do different). Some of the biggest differences are a removal of the dependency on _dxil.dll_, a proprietry code-signing blob, and changes to make _DXC_ correctly work as a static library. 

### Differences from hexops/dxc and mach-dxcompiler

Unfortunately, the Hexops fork of DXC does not attempt to keep up-to-date with source DXC and is primarily designed to serve the purpose of a DXIL bytecode generator for the Mach Engine and not as a standalone library. As such, it lacks features such as SPIR-V bytecode generation, which are essential for developers seeking to cross-compile HLSL for several platforms.<br>

Mach also does not integrate the zig buildsystem directly with _DXC_ source and keeps their buildsystem one level above. This project will instead attempt to integrate directly with source _DXC_ and maintain the source relatively up-to-date with the upstream as long as there are no issues. It will provide the option to build with SPIR-V bytecode generation, and modify the C API to adopt the general DXC naming conventions.
