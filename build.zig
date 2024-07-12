const std = @import("std");
const builtin = @import("builtin");
const sources = @import("sources.zig");
const headers = @import("gen_headers.zig");
const llvmconf = @import("llvm_config.zig");
const Build = std.Build;

const log = std.log.scoped(.directxshadercompiler);

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const debug_symbols = b.option(bool, "debug_symbols", "Whether to produce detailed debug symbols (g0) or not. These increase binary size considerably.") orelse false;
    const build_shared = b.option(bool, "shared", "Build dxcompiler shared libraries") orelse false;
    const build_spirv = b.option(bool, "spirv", "Build spir-v compilation support") orelse false;
    const skip_executables = b.option(bool, "skip_executables", "Skip building executables") orelse false;
    const skip_tests = b.option(bool, "skip_tests", "Skip building tests") orelse false;
    const build_headers = b.option(bool, "build_headers", "Rebuild DXC headers and tables (requires python3 installation)") orelse false;

    const dxcompiler = b.addStaticLibrary(.{
        .name = "dxcompiler",
        .optimize = optimize,
        .target = target,
    });

    if (build_headers)
    {
        dxcompiler.step.dependOn(headers.buildDXCHeaders(b, optimize, target));
    }
            
    // Microsoft does some shit.
    dxcompiler.root_module.sanitize_c = false;
    dxcompiler.root_module.sanitize_thread = false; // sometimes in parallel, too.

    var cflags = std.ArrayList([]const u8).init(b.allocator);
    var cppflags = std.ArrayList([]const u8).init(b.allocator);

    if (!debug_symbols) {
        try cflags.append("-g0");
        try cppflags.append("-g0");
    }
    try cppflags.append("-std=c++17");

    const base_flags = &.{
        "-Wno-unused-command-line-argument",
        "-Wno-unused-variable",
        "-Wno-missing-exception-spec",
        "-Wno-macro-redefined",
        "-Wno-unknown-attributes",
        "-Wno-implicit-fallthrough",
        "-fms-extensions", // __uuidof and friends (on non-windows targets)
    };

    try cflags.appendSlice(base_flags);
    try cppflags.appendSlice(base_flags);

    addConfigHeaders(b, dxcompiler);
    addIncludes(b, dxcompiler);

    const cpp_sources =
        sources.tools_clang_lib_lex_sources ++
        sources.tools_clang_lib_basic_sources ++
        sources.tools_clang_lib_driver_sources ++
        sources.tools_clang_lib_analysis_sources ++
        sources.tools_clang_lib_index_sources ++
        sources.tools_clang_lib_parse_sources ++
        sources.tools_clang_lib_ast_sources ++
        sources.tools_clang_lib_edit_sources ++
        sources.tools_clang_lib_sema_sources ++
        sources.tools_clang_lib_codegen_sources ++
        sources.tools_clang_lib_astmatchers_sources ++
        sources.tools_clang_lib_tooling_core_sources ++
        sources.tools_clang_lib_tooling_sources ++
        sources.tools_clang_lib_format_sources ++
        sources.tools_clang_lib_rewrite_sources ++
        sources.tools_clang_lib_frontend_sources ++
        sources.tools_clang_tools_libclang_sources ++
        sources.tools_clang_tools_dxcompiler_sources ++
        sources.lib_bitcode_reader_sources ++
        sources.lib_bitcode_writer_sources ++
        sources.lib_ir_sources ++
        sources.lib_irreader_sources ++
        sources.lib_linker_sources ++
        sources.lib_asmparser_sources ++
        sources.lib_analysis_sources ++
        sources.lib_mssupport_sources ++
        sources.lib_transforms_utils_sources ++
        sources.lib_transforms_instcombine_sources ++
        sources.lib_transforms_ipo_sources ++
        sources.lib_transforms_scalar_sources ++
        sources.lib_transforms_vectorize_sources ++
        sources.lib_target_sources ++
        sources.lib_profiledata_sources ++
        sources.lib_option_sources ++
        sources.lib_passprinters_sources ++
        sources.lib_passes_sources ++
        sources.lib_hlsl_sources ++
        sources.lib_support_cpp_sources ++
        sources.lib_dxcsupport_sources ++
        sources.lib_dxcbindingtable_sources ++
        sources.lib_dxil_sources ++
        sources.lib_dxilcontainer_sources ++
        sources.lib_dxilpixpasses_sources ++
        sources.lib_dxilcompression_cpp_sources ++
        sources.lib_dxilrootsignature_sources;

    const c_sources =
        sources.lib_support_c_sources ++
        sources.lib_dxilcompression_c_sources;

    dxcompiler.addCSourceFile(.{
        .file = b.path("zig-source/dxc_c_interface.cpp"),
        .flags = &.{
            "-fms-extensions", // __uuidof and friends (on non-windows targets)
        },
    });

    dxcompiler.addCSourceFiles(.{
        .files = &cpp_sources,
        .flags = cppflags.items,
    });

    dxcompiler.addCSourceFiles(.{
        .files = &c_sources,
        .flags = cflags.items,
    });

    dxcompiler.defineCMacro("NDEBUG", ""); // disable assertions
            
    if (target.result.os.tag == .windows) {
        dxcompiler.defineCMacro("LLVM_ON_WIN32", "1");
        dxcompiler.linkSystemLibrary("version");
    } else {
        dxcompiler.defineCMacro("HAVE_DLFCN_H", "1");
        dxcompiler.defineCMacro("LLVM_ON_UNIX", "1");
    }

    if (build_shared) 
    {
        dxcompiler.defineCMacro("DXC_C_SHARED_LIBRARY", "1");
        dxcompiler.defineCMacro("DXC_C_IMPLEMENTATION", "1");
    }

    linkDxcDependencies(dxcompiler);

    // TODO: investigate SSE2 #define / cmake option for CPU target
    //
    // TODO: investigate how projects/dxilconv/lib/DxbcConverter/DxbcConverterImpl.h is getting pulled
    // in, we can get rid of dxbc conversion presumably

    // Link SPIRV-Tools and build SPIR-V codegen sources
    if (build_spirv)
    {
        dxcompiler.defineCMacro("ENABLE_SPIRV_CODEGEN", "");

        addSPIRVIncludes(b, dxcompiler);

        // Add clang SPIRV tooling sources
        dxcompiler.addCSourceFiles(.{
            .files = &sources.tools_clang_lib_spirv,
            .flags = cppflags.items,
        });

        if (b.lazyDependency("SPIRV-Tools", .{
            .target = target,
            .optimize = optimize,
            .header_path = b.path("external/SPIRV-Headers").getPath(b), // Absolute path for SPIRV-Headers
            .no_link = true, // Linker not in use
            .no_reduce = true, // Reducer not in use
        })) |dep| 
        {
            dxcompiler.linkLibrary(dep.artifact("SPIRV-Tools-opt"));
            dxcompiler.linkLibrary(dep.artifact("SPIRV-Tools-val"));
        }
    }

    b.installArtifact(dxcompiler);

    const install_step = b.step("dxcompiler", "Build and install the dxcompiler static library");
    install_step.dependOn(&b.addInstallArtifact(dxcompiler, .{}).step);

// ----------------
// DXC Zig Bindings
// ----------------

    // Zig bindings
    const dxcompiler_zig = b.addModule("dxcompiler-zig", .{
        .root_source_file = b.path("zig-source/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    dxcompiler_zig.addIncludePath(b.path("zig-source"));

    dxcompiler_zig.linkLibrary(dxcompiler);

// ------------------
// DXC shared library
// ------------------

    if (build_shared)
    {
        const dxcompiler_shared = b.addSharedLibrary(.{
            .name = "dxcompiler-shared",
            .optimize = optimize,
            .target = target,
        });

        dxcompiler_shared.addCSourceFile(.{
            .file = b.path("zig-source/shared_main.cpp"),
            .flags = &.{ "-std=c++17" },
        }); 

        dxcompiler_shared.linkLibrary(dxcompiler);

        b.installArtifact(dxcompiler_shared);

        const shared_install_step = b.step("dxcompiler-shared", "Build and install the dxcompiler-shared shared library");
        shared_install_step.dependOn(&b.addInstallArtifact(dxcompiler_shared, .{}).step);
    }

// ------------------
// dxc.exe Executable
// ------------------

    if (!skip_executables)
    {
        const dxc_exe = b.addExecutable(.{
            .name = "dxc",
            .optimize = optimize,
            .target = target,
        });

        dxc_exe.addCSourceFile(.{
            .file = b.path("tools/clang/tools/dxc/dxcmain.cpp"),
            .flags = &.{"-std=c++17", },
        });

        dxc_exe.addCSourceFile(.{
            .file = b.path("tools/clang/tools/dxclib/dxc.cpp"),
            .flags = cppflags.items,
        });

        dxc_exe.addIncludePath(b.path("tools/clang/tools"));

        addConfigHeaders(b, dxc_exe);
        addIncludes(b, dxc_exe);

        dxc_exe.defineCMacro("NDEBUG", ""); // disable assertions

        if (target.result.os.tag != .windows) 
            dxc_exe.defineCMacro("HAVE_DLFCN_H", "1");

        dxc_exe.linkLibrary(dxcompiler);

        b.installArtifact(dxc_exe);

        const install_dxc_step = b.step("dxc", "Build and install dxc.exe");
        install_dxc_step.dependOn(&b.addInstallArtifact(dxc_exe, .{}).step);
    }

// -------------
// DXC Zig Tests
// -------------

    if (!skip_tests)
    {
        const main_tests = b.addTest(.{
            .name = "dxcompiler-tests",
            .root_source_file = b.path("zig-source/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        main_tests.addIncludePath(b.path("zig-source"));
        main_tests.linkLibrary(dxcompiler);

        b.installArtifact(main_tests);

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&b.addRunArtifact(main_tests).step);
    }
}

fn linkDxcDependencies(step: *std.Build.Step.Compile) void {
    const target = step.rootModuleTarget();
    
    step.linkLibCpp();
    
    if (target.os.tag == .windows) {
        step.linkSystemLibrary("ole32");
        step.linkSystemLibrary("oleaut32");
    }
}

fn addConfigHeaders(b: *Build, step: *std.Build.Step.Compile) void {
    // /tools/clang/include/clang/Config/config.h.cmake
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("tools/clang/include/clang/Config/config.h.cmake") },
            .include_path = "clang/Config/config.h",
        },
        .{
            .BUG_REPORT_URL = "",
            .CLANG_DEFAULT_OPENMP_RUNTIME = "",
            .CLANG_LIBDIR_SUFFIX = "",
            .CLANG_RESOURCE_DIR = "",
            .C_INCLUDE_DIRS = "",
            .DEFAULT_SYSROOT = "",
            .GCC_INSTALL_PREFIX = "",
            .CLANG_HAVE_LIBXML = 0,
            .BACKEND_PACKAGE_STRING = "",
            .HOST_LINK_VERSION = "",
        },
    ));

    // /include/llvm/Config/AsmParsers.def.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Config/AsmParsers.def.in") },
            .include_path = "llvm/Config/AsmParsers.def",
        },
        .{
            .LLVM_ENUM_ASM_PARSERS = ""
        },
    ));

    // /include/llvm/Config/Disassemblers.def.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Config/Disassemblers.def.in") },
            .include_path = "llvm/Config/Disassemblers.def",
        },
        .{
            .LLVM_ENUM_DISASSEMBLERS = "", 
        },
    ));

    // /include/llvm/Config/Targets.def.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Config/Targets.def.in") },
            .include_path = "llvm/Config/Targets.def",
        },
        .{
            .LLVM_ENUM_TARGETS = "",
        },
    ));

    // /include/llvm/Config/AsmPrinters.def.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Config/AsmPrinters.def.in") },
            .include_path = "llvm/Config/AsmPrinters.def",
        },
        .{
            .LLVM_ENUM_ASM_PRINTERS = "",
        },
    ));

    // /include/llvm/Support/DataTypes.h.cmake
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Support/DataTypes.h.cmake") },
            .include_path = "llvm/Support/DataTypes.h",
        },
        .{
            .HAVE_INTTYPES_H = 1,
            .HAVE_STDINT_H = 1,
            .HAVE_UINT64_T = 1,
            .HAVE_U_INT64_T = 0,
        },
    ));

    // /tools/clang/include/clang/Basic/Version.inc.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("tools/clang/include/clang/Basic/Version.inc.in") },
            .include_path = "clang/Basic/Version.inc",
        },
        .{
            .CLANG_VERSION = "3.7.0",
            .CLANG_VERSION_MAJOR = 3,
            .CLANG_VERSION_MINOR = 7,
            .CLANG_HAS_VERSION_PATCHLEVEL = 0,
            .CLANG_VERSION_PATCHLEVEL = 0,
        },
    ));

    // /include/llvm/Config/AsmParsers.def.in
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/llvm/Config/AsmParsers.def.in") },
            .include_path = "llvm/Config/AsmParsers.def",
        },
        .{
            .LLVM_ENUM_ASM_PARSERS = ""
        },
    ));

    const target = step.rootModuleTarget();
    step.addConfigHeader(llvmconf.addConfigHeader(b, target, .llvm_config_h));
    step.addConfigHeader(llvmconf.addConfigHeader(b, target, .config_h));

    // /include/dxc/config.h.cmake
    step.addConfigHeader(b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("include/dxc/config.h.cmake") },
            .include_path = "dxc/config.h",
        },
        .{
            .DXC_DISABLE_ALLOCATOR_OVERRIDES = false,
        },
    ));
}

fn addIncludes(b: *Build, step: *std.Build.Step.Compile) void {
    // DIA SDK not used - don't add it to include path.
    // step.addIncludePath(b.path("external/DIA/include"));
    
    // Will use pregenerated values unless -Dbuild_headers flag is passed
    step.addIncludePath(b.path("generated-include/"));

    step.addIncludePath(b.path("tools/clang/include"));
    step.addIncludePath(b.path("include"));
    step.addIncludePath(b.path("include/llvm"));
    step.addIncludePath(b.path("include/llvm/llvm_assert"));
    step.addIncludePath(b.path("include/llvm/Bitcode"));
    step.addIncludePath(b.path("include/llvm/IR"));
    step.addIncludePath(b.path("include/llvm/IRReader"));
    step.addIncludePath(b.path("include/llvm/Linker"));
    step.addIncludePath(b.path("include/llvm/Analysis"));
    step.addIncludePath(b.path("include/llvm/Transforms"));
    step.addIncludePath(b.path("include/llvm/Transforms/Utils"));
    step.addIncludePath(b.path("include/llvm/Transforms/InstCombine"));
    step.addIncludePath(b.path("include/llvm/Transforms/IPO"));
    step.addIncludePath(b.path("include/llvm/Transforms/Scalar"));
    step.addIncludePath(b.path("include/llvm/Transforms/Vectorize"));
    step.addIncludePath(b.path("include/llvm/Target"));
    step.addIncludePath(b.path("include/llvm/ProfileData"));
    step.addIncludePath(b.path("include/llvm/Option"));
    step.addIncludePath(b.path("include/llvm/PassPrinters"));
    step.addIncludePath(b.path("include/llvm/Passes"));
    step.addIncludePath(b.path("include/dxc"));
    step.addIncludePath(b.path("external/DirectX-Headers/include/directx"));
    
    const target = step.rootModuleTarget();
    
    if (target.os.tag != .windows) 
        step.addIncludePath(b.path("external/DirectX-Headers/include/wsl/stubs"));
}

fn addSPIRVIncludes(b: *Build, step: *std.Build.Step.Compile) void
{
    step.addIncludePath(b.path("external/SPIRV-Tools"));
    step.addIncludePath(b.path("external/SPIRV-Tools/include"));
    step.addIncludePath(b.path("external/SPIRV-Tools/source"));

    step.addIncludePath(b.path("external/SPIRV-Headers/include"));
}