const std = @import("std");
const builtin = @import("builtin");
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
    const regenerate_headers = b.option(bool, "regenerate_headers", "Regenerate DXC headers and tables (requires python3 installation)") orelse false;

    const dxcompiler = b.addStaticLibrary(.{
        .name = "dxcompiler",
        .optimize = optimize,
        .target = target,
    });

    if (regenerate_headers)
    {
        dxcompiler.step.dependOn(headers.buildDXCHeaders(b, optimize));
    }
            
    // Microsoft does some shit.
    dxcompiler.root_module.sanitize_c = false;
    dxcompiler.root_module.sanitize_thread = false; // sometimes in parallel, too.
    dxcompiler.pie = true;

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

    llvmconf.addConfigHeaders(b, dxcompiler);
    addIncludes(b, dxcompiler);

    const cpp_sources =
        tools_clang_lib_lex_sources ++
        tools_clang_lib_basic_sources ++
        tools_clang_lib_driver_sources ++
        tools_clang_lib_analysis_sources ++
        tools_clang_lib_index_sources ++
        tools_clang_lib_parse_sources ++
        tools_clang_lib_ast_sources ++
        tools_clang_lib_edit_sources ++
        tools_clang_lib_sema_sources ++
        tools_clang_lib_codegen_sources ++
        tools_clang_lib_astmatchers_sources ++
        tools_clang_lib_tooling_core_sources ++
        tools_clang_lib_tooling_sources ++
        tools_clang_lib_format_sources ++
        tools_clang_lib_rewrite_sources ++
        tools_clang_lib_frontend_sources ++
        tools_clang_tools_libclang_sources ++
        tools_clang_tools_dxcompiler_sources ++
        lib_bitcode_reader_sources ++
        lib_bitcode_writer_sources ++
        lib_ir_sources ++
        lib_irreader_sources ++
        lib_linker_sources ++
        lib_asmparser_sources ++
        lib_analysis_sources ++
        lib_mssupport_sources ++
        lib_transforms_utils_sources ++
        lib_transforms_instcombine_sources ++
        lib_transforms_ipo_sources ++
        lib_transforms_scalar_sources ++
        lib_transforms_vectorize_sources ++
        lib_target_sources ++
        lib_profiledata_sources ++
        lib_option_sources ++
        lib_passprinters_sources ++
        lib_passes_sources ++
        lib_hlsl_sources ++
        lib_support_cpp_sources ++
        lib_dxcsupport_sources ++
        lib_dxcbindingtable_sources ++
        lib_dxil_sources ++
        lib_dxilcontainer_sources ++
        lib_dxilpixpasses_sources ++
        lib_dxilcompression_cpp_sources ++
        lib_dxilrootsignature_sources;

    const c_sources =
        lib_support_c_sources ++
        lib_dxilcompression_c_sources;

    dxcompiler.addCSourceFile(.{
        .file = b.path("zig-source/DxcCInterface.cpp"),
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
            .files = &tools_clang_lib_spirv,
            .flags = cppflags.items,
        });

        if (b.lazyDependency("SPIRV-Tools", .{
            .target = target,
            .optimize = optimize,
            .header_path = b.path("external/SPIRV-Headers").getPath(b), // Absolute path for SPIRV-Headers
            .no_link = true, // Linker not in use
            .no_reduce = true, // Reducer not in use
            .rebuild_headers = regenerate_headers,
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
    const dxcompiler_zig = b.addModule("dxcompiler", .{
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
            .name = "dxcompiler",
            .optimize = optimize,
            .target = target,
        });

        dxcompiler_shared.addCSourceFile(.{
            .file = b.path("zig-source/SharedMain.cpp"),
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

        llvmconf.addConfigHeaders(b, dxc_exe);
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

fn addIncludes(b: *Build, step: *std.Build.Step.Compile) void {
    // TODO: Find out how to remove dependency on DIA SDK.
    step.addIncludePath(b.path("external/DIA/include"));
    
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

// find tools/clang/lib/Lex | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_lex_sources = [_][]const u8{
    "tools/clang/lib/Lex/MacroInfo.cpp",
    "tools/clang/lib/Lex/Preprocessor.cpp",
    "tools/clang/lib/Lex/PPExpressions.cpp",
    "tools/clang/lib/Lex/PreprocessorLexer.cpp",
    "tools/clang/lib/Lex/HeaderSearch.cpp",
    "tools/clang/lib/Lex/PPDirectives.cpp",
    "tools/clang/lib/Lex/ScratchBuffer.cpp",
    "tools/clang/lib/Lex/ModuleMap.cpp",
    "tools/clang/lib/Lex/TokenLexer.cpp",
    "tools/clang/lib/Lex/Lexer.cpp",
    "tools/clang/lib/Lex/HLSLMacroExpander.cpp",
    "tools/clang/lib/Lex/PTHLexer.cpp",
    "tools/clang/lib/Lex/PPCallbacks.cpp",
    "tools/clang/lib/Lex/Pragma.cpp",
    "tools/clang/lib/Lex/PPCaching.cpp",
    "tools/clang/lib/Lex/PreprocessingRecord.cpp",
    "tools/clang/lib/Lex/PPMacroExpansion.cpp",
    "tools/clang/lib/Lex/HeaderMap.cpp",
    "tools/clang/lib/Lex/LiteralSupport.cpp",
    "tools/clang/lib/Lex/PPLexerChange.cpp",
    "tools/clang/lib/Lex/TokenConcatenation.cpp",
    "tools/clang/lib/Lex/PPConditionalDirectiveRecord.cpp",
    "tools/clang/lib/Lex/MacroArgs.cpp",
};

// find tools/clang/lib/Basic | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_basic_sources = [_][]const u8{
    "tools/clang/lib/Basic/OpenMPKinds.cpp",
    "tools/clang/lib/Basic/TargetInfo.cpp",
    "tools/clang/lib/Basic/LangOptions.cpp",
    "tools/clang/lib/Basic/Warnings.cpp",
    "tools/clang/lib/Basic/Builtins.cpp",
    "tools/clang/lib/Basic/DiagnosticOptions.cpp",
    "tools/clang/lib/Basic/Module.cpp",
    "tools/clang/lib/Basic/Version.cpp",
    "tools/clang/lib/Basic/IdentifierTable.cpp",
    "tools/clang/lib/Basic/TokenKinds.cpp",
    "tools/clang/lib/Basic/ObjCRuntime.cpp",
    "tools/clang/lib/Basic/SourceManager.cpp",
    "tools/clang/lib/Basic/VersionTuple.cpp",
    "tools/clang/lib/Basic/FileSystemStatCache.cpp",
    "tools/clang/lib/Basic/FileManager.cpp",
    "tools/clang/lib/Basic/CharInfo.cpp",
    "tools/clang/lib/Basic/OperatorPrecedence.cpp",
    "tools/clang/lib/Basic/SanitizerBlacklist.cpp",
    "tools/clang/lib/Basic/VirtualFileSystem.cpp",
    "tools/clang/lib/Basic/DiagnosticIDs.cpp",
    "tools/clang/lib/Basic/Diagnostic.cpp",
    "tools/clang/lib/Basic/Targets.cpp",
    "tools/clang/lib/Basic/Attributes.cpp",
    "tools/clang/lib/Basic/SourceLocation.cpp",
    "tools/clang/lib/Basic/Sanitizers.cpp",
};

// find tools/clang/lib/Driver | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_driver_sources = [_][]const u8{
    "tools/clang/lib/Driver/Job.cpp",
    "tools/clang/lib/Driver/ToolChains.cpp",
    "tools/clang/lib/Driver/DriverOptions.cpp",
    "tools/clang/lib/Driver/Types.cpp",
    "tools/clang/lib/Driver/MinGWToolChain.cpp",
    "tools/clang/lib/Driver/Phases.cpp",
    "tools/clang/lib/Driver/MSVCToolChain.cpp",
    "tools/clang/lib/Driver/Compilation.cpp",
    "tools/clang/lib/Driver/Driver.cpp",
    "tools/clang/lib/Driver/Multilib.cpp",
    "tools/clang/lib/Driver/Tools.cpp",
    "tools/clang/lib/Driver/SanitizerArgs.cpp",
    "tools/clang/lib/Driver/Tool.cpp",
    "tools/clang/lib/Driver/Action.cpp",
    "tools/clang/lib/Driver/CrossWindowsToolChain.cpp",
    "tools/clang/lib/Driver/ToolChain.cpp",
};

// find tools/clang/lib/Analysis | grep -v 'CocoaConventions.cpp' | grep -v 'FormatString.cpp' | grep -v 'PrintfFormatString.cpp' | grep -v 'ScanfFormatString.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_analysis_sources = [_][]const u8{
    "tools/clang/lib/Analysis/ReachableCode.cpp",
    "tools/clang/lib/Analysis/ThreadSafetyLogical.cpp",
    "tools/clang/lib/Analysis/ThreadSafetyCommon.cpp",
    "tools/clang/lib/Analysis/CFG.cpp",
    "tools/clang/lib/Analysis/BodyFarm.cpp",
    "tools/clang/lib/Analysis/ThreadSafety.cpp",
    "tools/clang/lib/Analysis/UninitializedValues.cpp",
    "tools/clang/lib/Analysis/CFGReachabilityAnalysis.cpp",
    "tools/clang/lib/Analysis/Dominators.cpp",
    "tools/clang/lib/Analysis/PseudoConstantAnalysis.cpp",
    "tools/clang/lib/Analysis/AnalysisDeclContext.cpp",
    "tools/clang/lib/Analysis/LiveVariables.cpp",
    "tools/clang/lib/Analysis/CallGraph.cpp",
    "tools/clang/lib/Analysis/PostOrderCFGView.cpp",
    "tools/clang/lib/Analysis/ProgramPoint.cpp",
    "tools/clang/lib/Analysis/ObjCNoReturn.cpp",
    "tools/clang/lib/Analysis/ThreadSafetyTIL.cpp",
    "tools/clang/lib/Analysis/CFGStmtMap.cpp",
    "tools/clang/lib/Analysis/Consumed.cpp",
    "tools/clang/lib/Analysis/CodeInjector.cpp",
};

// find tools/clang/lib/Index | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_index_sources = [_][]const u8{
    "tools/clang/lib/Index/CommentToXML.cpp",
    "tools/clang/lib/Index/USRGeneration.cpp",
};

// find tools/clang/lib/Parse | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_parse_sources = [_][]const u8{
    "tools/clang/lib/Parse/ParseExprCXX.cpp",
    "tools/clang/lib/Parse/ParseTemplate.cpp",
    "tools/clang/lib/Parse/ParseDeclCXX.cpp",
    "tools/clang/lib/Parse/ParseInit.cpp",
    "tools/clang/lib/Parse/ParseOpenMP.cpp",
    "tools/clang/lib/Parse/HLSLRootSignature.cpp",
    "tools/clang/lib/Parse/ParseObjc.cpp",
    "tools/clang/lib/Parse/ParseDecl.cpp",
    "tools/clang/lib/Parse/ParseExpr.cpp",
    "tools/clang/lib/Parse/ParseHLSL.cpp",
    "tools/clang/lib/Parse/ParseCXXInlineMethods.cpp",
    "tools/clang/lib/Parse/ParseStmtAsm.cpp",
    "tools/clang/lib/Parse/ParseStmt.cpp",
    "tools/clang/lib/Parse/ParsePragma.cpp",
    "tools/clang/lib/Parse/Parser.cpp",
    "tools/clang/lib/Parse/ParseAST.cpp",
    "tools/clang/lib/Parse/ParseTentative.cpp",
};

// find tools/clang/lib/AST | grep -v 'NSAPI.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_ast_sources = [_][]const u8{
    "tools/clang/lib/AST/ExprConstant.cpp",
    "tools/clang/lib/AST/ExprCXX.cpp",
    "tools/clang/lib/AST/CommentCommandTraits.cpp",
    "tools/clang/lib/AST/Mangle.cpp",
    "tools/clang/lib/AST/ASTDiagnostic.cpp",
    "tools/clang/lib/AST/CommentParser.cpp",
    "tools/clang/lib/AST/AttrImpl.cpp",
    "tools/clang/lib/AST/ASTDumper.cpp",
    "tools/clang/lib/AST/DeclOpenMP.cpp",
    "tools/clang/lib/AST/ASTTypeTraits.cpp",
    "tools/clang/lib/AST/ASTImporter.cpp",
    "tools/clang/lib/AST/StmtPrinter.cpp",
    "tools/clang/lib/AST/CommentBriefParser.cpp",
    "tools/clang/lib/AST/APValue.cpp",
    "tools/clang/lib/AST/ASTConsumer.cpp",
    "tools/clang/lib/AST/DeclCXX.cpp",
    "tools/clang/lib/AST/Stmt.cpp",
    "tools/clang/lib/AST/CommentSema.cpp",
    "tools/clang/lib/AST/HlslTypes.cpp",
    "tools/clang/lib/AST/ASTContextHLSL.cpp",
    "tools/clang/lib/AST/InheritViz.cpp",
    "tools/clang/lib/AST/Expr.cpp",
    "tools/clang/lib/AST/RecordLayout.cpp",
    "tools/clang/lib/AST/StmtIterator.cpp",
    "tools/clang/lib/AST/ExprClassification.cpp",
    "tools/clang/lib/AST/DeclPrinter.cpp",
    "tools/clang/lib/AST/DeclBase.cpp",
    "tools/clang/lib/AST/StmtProfile.cpp",
    "tools/clang/lib/AST/Comment.cpp",
    "tools/clang/lib/AST/VTTBuilder.cpp",
    "tools/clang/lib/AST/Decl.cpp",
    "tools/clang/lib/AST/SelectorLocationsKind.cpp",
    "tools/clang/lib/AST/TypeLoc.cpp",
    "tools/clang/lib/AST/DeclarationName.cpp",
    "tools/clang/lib/AST/DeclObjC.cpp",
    "tools/clang/lib/AST/VTableBuilder.cpp",
    "tools/clang/lib/AST/CommentLexer.cpp",
    "tools/clang/lib/AST/StmtViz.cpp",
    "tools/clang/lib/AST/DeclTemplate.cpp",
    "tools/clang/lib/AST/CXXInheritance.cpp",
    "tools/clang/lib/AST/RecordLayoutBuilder.cpp",
    "tools/clang/lib/AST/RawCommentList.cpp",
    "tools/clang/lib/AST/TemplateBase.cpp",
    "tools/clang/lib/AST/HlslBuiltinTypeDeclBuilder.cpp",
    "tools/clang/lib/AST/DeclFriend.cpp",
    "tools/clang/lib/AST/ItaniumMangle.cpp",
    "tools/clang/lib/AST/ASTContext.cpp",
    "tools/clang/lib/AST/TemplateName.cpp",
    "tools/clang/lib/AST/ParentMap.cpp",
    "tools/clang/lib/AST/ItaniumCXXABI.cpp",
    "tools/clang/lib/AST/NestedNameSpecifier.cpp",
    "tools/clang/lib/AST/MicrosoftMangle.cpp",
    "tools/clang/lib/AST/DeclGroup.cpp",
    "tools/clang/lib/AST/Type.cpp",
    "tools/clang/lib/AST/ExternalASTSource.cpp",
    "tools/clang/lib/AST/TypePrinter.cpp",
    "tools/clang/lib/AST/MicrosoftCXXABI.cpp",
};

// find tools/clang/lib/Edit | grep -v 'RewriteObjCFoundationAPI.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_edit_sources = [_][]const u8{
    "tools/clang/lib/Edit/EditedSource.cpp",
    "tools/clang/lib/Edit/Commit.cpp",
};

// find tools/clang/lib/Sema | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_sema_sources = [_][]const u8{
    "tools/clang/lib/Sema/SemaDXR.cpp",
    "tools/clang/lib/Sema/CodeCompleteConsumer.cpp",
    "tools/clang/lib/Sema/SemaOverload.cpp",
    "tools/clang/lib/Sema/SemaLambda.cpp",
    "tools/clang/lib/Sema/SemaTemplateDeduction.cpp",
    "tools/clang/lib/Sema/MultiplexExternalSemaSource.cpp",
    "tools/clang/lib/Sema/IdentifierResolver.cpp",
    "tools/clang/lib/Sema/TypeLocBuilder.cpp",
    "tools/clang/lib/Sema/SemaCUDA.cpp",
    "tools/clang/lib/Sema/SemaTemplateInstantiate.cpp",
    "tools/clang/lib/Sema/SemaTemplate.cpp",
    "tools/clang/lib/Sema/DelayedDiagnostic.cpp",
    "tools/clang/lib/Sema/SemaTemplateInstantiateDecl.cpp",
    "tools/clang/lib/Sema/SemaDeclCXX.cpp",
    "tools/clang/lib/Sema/ScopeInfo.cpp",
    "tools/clang/lib/Sema/SemaStmtAttr.cpp",
    "tools/clang/lib/Sema/SemaChecking.cpp",
    "tools/clang/lib/Sema/SemaCast.cpp",
    "tools/clang/lib/Sema/SemaInit.cpp",
    "tools/clang/lib/Sema/SemaType.cpp",
    "tools/clang/lib/Sema/SemaDeclAttr.cpp",
    "tools/clang/lib/Sema/SemaOpenMP.cpp",
    "tools/clang/lib/Sema/SemaFixItUtils.cpp",
    "tools/clang/lib/Sema/SemaTemplateVariadic.cpp",
    "tools/clang/lib/Sema/SemaExprCXX.cpp",
    "tools/clang/lib/Sema/Scope.cpp",
    "tools/clang/lib/Sema/DeclSpec.cpp",
    "tools/clang/lib/Sema/SemaLookup.cpp",
    "tools/clang/lib/Sema/SemaPseudoObject.cpp",
    "tools/clang/lib/Sema/AttributeList.cpp",
    "tools/clang/lib/Sema/SemaDeclObjC.cpp",
    "tools/clang/lib/Sema/SemaCXXScopeSpec.cpp",
    "tools/clang/lib/Sema/SemaExprMember.cpp",
    "tools/clang/lib/Sema/SemaAccess.cpp",
    "tools/clang/lib/Sema/SemaStmt.cpp",
    "tools/clang/lib/Sema/SemaCodeComplete.cpp",
    "tools/clang/lib/Sema/SemaExprObjC.cpp",
    "tools/clang/lib/Sema/SemaAttr.cpp",
    "tools/clang/lib/Sema/SemaStmtAsm.cpp",
    "tools/clang/lib/Sema/SemaExpr.cpp",
    "tools/clang/lib/Sema/JumpDiagnostics.cpp",
    "tools/clang/lib/Sema/SemaHLSL.cpp",
    "tools/clang/lib/Sema/SemaHLSLDiagnoseTU.cpp",
    "tools/clang/lib/Sema/SemaObjCProperty.cpp",
    "tools/clang/lib/Sema/SemaConsumer.cpp",
    "tools/clang/lib/Sema/SemaDecl.cpp",
    "tools/clang/lib/Sema/SemaExceptionSpec.cpp",
    "tools/clang/lib/Sema/Sema.cpp",
    "tools/clang/lib/Sema/AnalysisBasedWarnings.cpp",
};

// find tools/clang/lib/CodeGen | grep -v 'CGObjCGNU.cpp' | grep -v 'CGObjCMac.cpp' | grep -v 'CGObjCRuntime.cpp' | grep -v 'CGOpenCLRuntime.cpp' | grep -v 'CGOpenMPRuntime.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_codegen_sources = [_][]const u8{
    "tools/clang/lib/CodeGen/ObjectFilePCHContainerOperations.cpp",
    "tools/clang/lib/CodeGen/CGHLSLMSFinishCodeGen.cpp",
    "tools/clang/lib/CodeGen/CGDeclCXX.cpp",
    "tools/clang/lib/CodeGen/SanitizerMetadata.cpp",
    "tools/clang/lib/CodeGen/CGDecl.cpp",
    "tools/clang/lib/CodeGen/TargetInfo.cpp",
    "tools/clang/lib/CodeGen/CGCall.cpp",
    "tools/clang/lib/CodeGen/CGVTables.cpp",
    "tools/clang/lib/CodeGen/CGExprScalar.cpp",
    "tools/clang/lib/CodeGen/CGBlocks.cpp",
    "tools/clang/lib/CodeGen/CGExpr.cpp",
    "tools/clang/lib/CodeGen/CodeGenPGO.cpp",
    "tools/clang/lib/CodeGen/CGStmtOpenMP.cpp",
    "tools/clang/lib/CodeGen/CGExprCXX.cpp",
    "tools/clang/lib/CodeGen/BackendUtil.cpp",
    "tools/clang/lib/CodeGen/CGAtomic.cpp",
    "tools/clang/lib/CodeGen/CGCUDARuntime.cpp",
    "tools/clang/lib/CodeGen/CGHLSLRootSignature.cpp",
    "tools/clang/lib/CodeGen/CodeGenAction.cpp",
    "tools/clang/lib/CodeGen/CGStmt.cpp",
    "tools/clang/lib/CodeGen/CodeGenABITypes.cpp",
    "tools/clang/lib/CodeGen/CGClass.cpp",
    "tools/clang/lib/CodeGen/CGException.cpp",
    "tools/clang/lib/CodeGen/CGHLSLRuntime.cpp",
    "tools/clang/lib/CodeGen/CGExprComplex.cpp",
    "tools/clang/lib/CodeGen/CGExprConstant.cpp",
    "tools/clang/lib/CodeGen/ModuleBuilder.cpp",
    "tools/clang/lib/CodeGen/CodeGenTypes.cpp",
    "tools/clang/lib/CodeGen/CGCUDANV.cpp",
    "tools/clang/lib/CodeGen/CGRecordLayoutBuilder.cpp",
    "tools/clang/lib/CodeGen/CoverageMappingGen.cpp",
    "tools/clang/lib/CodeGen/CGExprAgg.cpp",
    "tools/clang/lib/CodeGen/CGVTT.cpp",
    "tools/clang/lib/CodeGen/CGCXX.cpp",
    "tools/clang/lib/CodeGen/CGCleanup.cpp",
    "tools/clang/lib/CodeGen/CGHLSLMS.cpp",
    "tools/clang/lib/CodeGen/CodeGenFunction.cpp",
    "tools/clang/lib/CodeGen/ItaniumCXXABI.cpp",
    "tools/clang/lib/CodeGen/CGDebugInfo.cpp",
    "tools/clang/lib/CodeGen/CGCXXABI.cpp",
    "tools/clang/lib/CodeGen/CGObjC.cpp",
    "tools/clang/lib/CodeGen/CodeGenModule.cpp",
    "tools/clang/lib/CodeGen/CGBuiltin.cpp",
    "tools/clang/lib/CodeGen/CodeGenTBAA.cpp",
    "tools/clang/lib/CodeGen/CGLoopInfo.cpp",
    "tools/clang/lib/CodeGen/MicrosoftCXXABI.cpp",
};

// find tools/clang/lib/ASTMatchers | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_astmatchers_sources = [_][]const u8{
    "tools/clang/lib/ASTMatchers/Dynamic/Diagnostics.cpp",
    "tools/clang/lib/ASTMatchers/Dynamic/Registry.cpp",
    "tools/clang/lib/ASTMatchers/Dynamic/VariantValue.cpp",
    "tools/clang/lib/ASTMatchers/Dynamic/Parser.cpp",
    "tools/clang/lib/ASTMatchers/ASTMatchersInternal.cpp",
    "tools/clang/lib/ASTMatchers/ASTMatchFinder.cpp",
};

// find tools/clang/lib/Tooling/Core | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_tooling_core_sources = [_][]const u8{
    "tools/clang/lib/Tooling/Core/Replacement.cpp",
};

// find tools/clang/lib/Tooling | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_tooling_sources = [_][]const u8{
    "tools/clang/lib/Tooling/JSONCompilationDatabase.cpp",
    "tools/clang/lib/Tooling/FileMatchTrie.cpp",
    "tools/clang/lib/Tooling/Core/Replacement.cpp",
    "tools/clang/lib/Tooling/RefactoringCallbacks.cpp",
    "tools/clang/lib/Tooling/CommonOptionsParser.cpp",
    "tools/clang/lib/Tooling/CompilationDatabase.cpp",
    "tools/clang/lib/Tooling/ArgumentsAdjusters.cpp",
    "tools/clang/lib/Tooling/Refactoring.cpp",
    "tools/clang/lib/Tooling/Tooling.cpp",
};

// find tools/clang/lib/Format | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_format_sources = [_][]const u8{
    "tools/clang/lib/Format/FormatToken.cpp",
    "tools/clang/lib/Format/ContinuationIndenter.cpp",
    "tools/clang/lib/Format/Format.cpp",
    "tools/clang/lib/Format/UnwrappedLineFormatter.cpp",
    "tools/clang/lib/Format/WhitespaceManager.cpp",
    "tools/clang/lib/Format/BreakableToken.cpp",
    "tools/clang/lib/Format/TokenAnnotator.cpp",
    "tools/clang/lib/Format/UnwrappedLineParser.cpp",
};

// find tools/clang/lib/Rewrite | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_rewrite_sources = [_][]const u8{
    "tools/clang/lib/Rewrite/HTMLRewrite.cpp",
    "tools/clang/lib/Rewrite/RewriteRope.cpp",
    "tools/clang/lib/Rewrite/DeltaTree.cpp",
    "tools/clang/lib/Rewrite/TokenRewriter.cpp",
    "tools/clang/lib/Rewrite/Rewriter.cpp",
};

// find tools/clang/lib/Frontend | grep -v 'RewriteModernObjC.cpp' | grep -v 'ChainedIncludesSource.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_frontend_sources = [_][]const u8{
    "tools/clang/lib/Frontend/ASTConsumers.cpp",
    "tools/clang/lib/Frontend/InitPreprocessor.cpp",
    "tools/clang/lib/Frontend/FrontendActions.cpp",
    "tools/clang/lib/Frontend/InitHeaderSearch.cpp",
    "tools/clang/lib/Frontend/ASTMerge.cpp",
    "tools/clang/lib/Frontend/Rewrite/RewriteMacros.cpp",
    "tools/clang/lib/Frontend/Rewrite/FixItRewriter.cpp",
    "tools/clang/lib/Frontend/Rewrite/InclusionRewriter.cpp",
    "tools/clang/lib/Frontend/Rewrite/RewriteTest.cpp",
    "tools/clang/lib/Frontend/Rewrite/FrontendActions_rewrite.cpp",
    "tools/clang/lib/Frontend/Rewrite/RewriteObjC.cpp",
    "tools/clang/lib/Frontend/Rewrite/HTMLPrint.cpp",
    "tools/clang/lib/Frontend/DependencyGraph.cpp",
    "tools/clang/lib/Frontend/FrontendAction.cpp",
    "tools/clang/lib/Frontend/MultiplexConsumer.cpp",
    "tools/clang/lib/Frontend/TextDiagnostic.cpp",
    "tools/clang/lib/Frontend/ModuleDependencyCollector.cpp",
    "tools/clang/lib/Frontend/DiagnosticRenderer.cpp",
    "tools/clang/lib/Frontend/CompilerInvocation.cpp",
    "tools/clang/lib/Frontend/CreateInvocationFromCommandLine.cpp",
    "tools/clang/lib/Frontend/PCHContainerOperations.cpp",
    "tools/clang/lib/Frontend/TextDiagnosticPrinter.cpp",
    "tools/clang/lib/Frontend/CodeGenOptions.cpp",
    "tools/clang/lib/Frontend/HeaderIncludeGen.cpp",
    "tools/clang/lib/Frontend/ASTUnit.cpp",
    "tools/clang/lib/Frontend/ChainedDiagnosticConsumer.cpp",
    "tools/clang/lib/Frontend/SerializedDiagnosticPrinter.cpp",
    "tools/clang/lib/Frontend/LayoutOverrideSource.cpp",
    "tools/clang/lib/Frontend/CacheTokens.cpp",
    "tools/clang/lib/Frontend/FrontendOptions.cpp",
    "tools/clang/lib/Frontend/LangStandards.cpp",
    "tools/clang/lib/Frontend/TextDiagnosticBuffer.cpp",
    "tools/clang/lib/Frontend/PrintPreprocessedOutput.cpp",
    "tools/clang/lib/Frontend/DependencyFile.cpp",
    "tools/clang/lib/Frontend/SerializedDiagnosticReader.cpp",
    "tools/clang/lib/Frontend/VerifyDiagnosticConsumer.cpp",
    "tools/clang/lib/Frontend/CompilerInstance.cpp",
    "tools/clang/lib/Frontend/LogDiagnosticPrinter.cpp",
};

// find tools/clang/tools/libclang | grep -v 'ARCMigrate.cpp' | grep -v 'BuildSystem.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_tools_libclang_sources = [_][]const u8{
    "tools/clang/tools/libclang/dxcisenseimpl.cpp",
    "tools/clang/tools/libclang/IndexBody.cpp",
    "tools/clang/tools/libclang/CIndexCXX.cpp",
    "tools/clang/tools/libclang/CIndexer.cpp",
    "tools/clang/tools/libclang/IndexingContext.cpp",
    "tools/clang/tools/libclang/CXLoadedDiagnostic.cpp",
    "tools/clang/tools/libclang/Indexing.cpp",
    "tools/clang/tools/libclang/CXCursor.cpp",
    "tools/clang/tools/libclang/dxcrewriteunused.cpp",
    "tools/clang/tools/libclang/CXCompilationDatabase.cpp",
    "tools/clang/tools/libclang/CIndexInclusionStack.cpp",
    "tools/clang/tools/libclang/CXStoredDiagnostic.cpp",
    "tools/clang/tools/libclang/CIndexHigh.cpp",
    "tools/clang/tools/libclang/CXType.cpp",
    "tools/clang/tools/libclang/CIndex.cpp",
    "tools/clang/tools/libclang/CIndexCodeCompletion.cpp",
    "tools/clang/tools/libclang/IndexTypeSourceInfo.cpp",
    "tools/clang/tools/libclang/CIndexDiagnostic.cpp",
    "tools/clang/tools/libclang/CXString.cpp",
    "tools/clang/tools/libclang/IndexDecl.cpp",
    "tools/clang/tools/libclang/CXComment.cpp",
    "tools/clang/tools/libclang/CXSourceLocation.cpp",
    "tools/clang/tools/libclang/CIndexUSRs.cpp",
};

// find tools/clang/tools/dxcompiler | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_tools_dxcompiler_sources = [_][]const u8{
    "tools/clang/tools/dxcompiler/MachSiegbertVogtDXCSA.cpp",
    "tools/clang/tools/dxcompiler/dxcdisassembler.cpp",
    "tools/clang/tools/dxcompiler/dxcvalidator.cpp",
    "tools/clang/tools/dxcompiler/dxillib.cpp",
    "tools/clang/tools/dxcompiler/dxcfilesystem.cpp",
    "tools/clang/tools/dxcompiler/DXCompiler.cpp",
    "tools/clang/tools/dxcompiler/dxcutil.cpp",
    "tools/clang/tools/dxcompiler/dxclinker.cpp",
    "tools/clang/tools/dxcompiler/dxcshadersourceinfo.cpp",
    "tools/clang/tools/dxcompiler/dxcassembler.cpp",
    "tools/clang/tools/dxcompiler/dxcapi.cpp",
    "tools/clang/tools/dxcompiler/dxclibrary.cpp",
    "tools/clang/tools/dxcompiler/dxcpdbutils.cpp",
    "tools/clang/tools/dxcompiler/dxcompilerobj.cpp",
};

// find lib/Bitcode/Reader | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_bitcode_reader_sources = [_][]const u8{
    "lib/Bitcode/Reader/BitReader.cpp",
    "lib/Bitcode/Reader/BitstreamReader.cpp",
    "lib/Bitcode/Reader/BitcodeReader.cpp",
};

// find lib/Bitcode/Writer | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_bitcode_writer_sources = [_][]const u8{
    "lib/Bitcode/Writer/BitcodeWriterPass.cpp",
    "lib/Bitcode/Writer/BitWriter.cpp",
    "lib/Bitcode/Writer/ValueEnumerator.cpp",
    "lib/Bitcode/Writer/BitcodeWriter.cpp",
};

// find lib/IR | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_ir_sources = [_][]const u8{
    "lib/IR/DebugInfoMetadata.cpp",
    "lib/IR/GCOV.cpp",
    "lib/IR/IRBuilder.cpp",
    "lib/IR/Pass.cpp",
    "lib/IR/AutoUpgrade.cpp",
    "lib/IR/Core.cpp",
    "lib/IR/InlineAsm.cpp",
    "lib/IR/Module.cpp",
    "lib/IR/GVMaterializer.cpp",
    "lib/IR/Operator.cpp",
    "lib/IR/DataLayout.cpp",
    "lib/IR/IntrinsicInst.cpp",
    "lib/IR/DebugLoc.cpp",
    "lib/IR/Dominators.cpp",
    "lib/IR/Constants.cpp",
    "lib/IR/PassRegistry.cpp",
    "lib/IR/DiagnosticPrinter.cpp",
    "lib/IR/ValueSymbolTable.cpp",
    "lib/IR/Globals.cpp",
    "lib/IR/ConstantRange.cpp",
    "lib/IR/LegacyPassManager.cpp",
    "lib/IR/Function.cpp",
    "lib/IR/TypeFinder.cpp",
    "lib/IR/DebugInfo.cpp",
    "lib/IR/LLVMContextImpl.cpp",
    "lib/IR/Verifier.cpp",
    "lib/IR/Comdat.cpp",
    "lib/IR/Value.cpp",
    "lib/IR/Use.cpp",
    "lib/IR/MetadataTracking.cpp",
    "lib/IR/Mangler.cpp",
    "lib/IR/DiagnosticInfo.cpp",
    "lib/IR/ValueTypes.cpp",
    "lib/IR/DIBuilder.cpp",
    "lib/IR/User.cpp",
    "lib/IR/MDBuilder.cpp",
    "lib/IR/Metadata.cpp",
    "lib/IR/BasicBlock.cpp",
    "lib/IR/Instruction.cpp",
    "lib/IR/AsmWriter.cpp",
    "lib/IR/Statepoint.cpp",
    "lib/IR/LLVMContext.cpp",
    "lib/IR/Instructions.cpp",
    "lib/IR/PassManager.cpp",
    "lib/IR/ConstantFold.cpp",
    "lib/IR/IRPrintingPasses.cpp",
    "lib/IR/Attributes.cpp",
    "lib/IR/Type.cpp",
};

// find lib/IRReader | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_irreader_sources = [_][]const u8{
    "lib/IRReader/IRReader.cpp",
};

// find lib/Linker | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_linker_sources = [_][]const u8{
    "lib/Linker/LinkModules.cpp",
};

// find lib/AsmParser | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_asmparser_sources = [_][]const u8{
    "lib/AsmParser/LLParser.cpp",
    "lib/AsmParser/LLLexer.cpp",
    "lib/AsmParser/Parser.cpp",
};

// find lib/Analysis | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_analysis_sources = [_][]const u8{
    "lib/Analysis/regioninfo.cpp",
    "lib/Analysis/DxilConstantFolding.cpp",
    "lib/Analysis/CGSCCPassManager.cpp",
    "lib/Analysis/DxilValueCache.cpp",
    "lib/Analysis/AliasSetTracker.cpp",
    "lib/Analysis/LoopPass.cpp",
    "lib/Analysis/MemDerefPrinter.cpp",
    "lib/Analysis/regionprinter.cpp",
    "lib/Analysis/DominanceFrontier.cpp",
    "lib/Analysis/Loads.cpp",
    "lib/Analysis/BlockFrequencyInfoImpl.cpp",
    "lib/Analysis/Analysis.cpp",
    "lib/Analysis/ReducibilityAnalysis.cpp",
    "lib/Analysis/CodeMetrics.cpp",
    "lib/Analysis/TargetTransformInfo.cpp",
    "lib/Analysis/CFG.cpp",
    "lib/Analysis/SparsePropagation.cpp",
    "lib/Analysis/IntervalPartition.cpp",
    "lib/Analysis/ScalarEvolutionNormalization.cpp",
    "lib/Analysis/CFGPrinter.cpp",
    "lib/Analysis/IPA/IPA.cpp",
    "lib/Analysis/IPA/GlobalsModRef.cpp",
    "lib/Analysis/IPA/InlineCost.cpp",
    "lib/Analysis/IPA/CallGraph.cpp",
    "lib/Analysis/IPA/CallGraphSCCPass.cpp",
    "lib/Analysis/IPA/CallPrinter.cpp",
    "lib/Analysis/Lint.cpp",
    "lib/Analysis/ScalarEvolution.cpp",
    "lib/Analysis/MemoryDependenceAnalysis.cpp",
    "lib/Analysis/PostDominators.cpp",
    "lib/Analysis/TypeBasedAliasAnalysis.cpp",
    "lib/Analysis/DxilSimplify.cpp",
    "lib/Analysis/DivergenceAnalysis.cpp",
    "lib/Analysis/BlockFrequencyInfo.cpp",
    "lib/Analysis/VectorUtils.cpp",
    "lib/Analysis/Delinearization.cpp",
    "lib/Analysis/AssumptionCache.cpp",
    "lib/Analysis/AliasAnalysisEvaluator.cpp",
    "lib/Analysis/IVUsers.cpp",
    "lib/Analysis/ValueTracking.cpp",
    "lib/Analysis/PHITransAddr.cpp",
    "lib/Analysis/NoAliasAnalysis.cpp",
    "lib/Analysis/AliasDebugger.cpp",
    "lib/Analysis/DependenceAnalysis.cpp",
    "lib/Analysis/LibCallSemantics.cpp",
    "lib/Analysis/DomPrinter.cpp",
    "lib/Analysis/Trace.cpp",
    "lib/Analysis/LazyValueInfo.cpp",
    "lib/Analysis/ConstantFolding.cpp",
    "lib/Analysis/LoopAccessAnalysis.cpp",
    "lib/Analysis/BranchProbabilityInfo.cpp",
    "lib/Analysis/TargetLibraryInfo.cpp",
    "lib/Analysis/CaptureTracking.cpp",
    "lib/Analysis/IteratedDominanceFrontier.cpp",
    "lib/Analysis/MemoryLocation.cpp",
    "lib/Analysis/InstructionSimplify.cpp",
    "lib/Analysis/VectorUtils2.cpp",
    "lib/Analysis/MemDepPrinter.cpp",
    "lib/Analysis/InstCount.cpp",
    "lib/Analysis/CostModel.cpp",
    "lib/Analysis/DxilConstantFoldingExt.cpp",
    "lib/Analysis/ScopedNoAliasAA.cpp",
    "lib/Analysis/ModuleDebugInfoPrinter.cpp",
    "lib/Analysis/LibCallAliasAnalysis.cpp",
    "lib/Analysis/MemoryBuiltins.cpp",
    "lib/Analysis/PtrUseVisitor.cpp",
    "lib/Analysis/AliasAnalysisCounter.cpp",
    "lib/Analysis/ScalarEvolutionAliasAnalysis.cpp",
    "lib/Analysis/BasicAliasAnalysis.cpp",
    "lib/Analysis/ScalarEvolutionExpander.cpp",
    "lib/Analysis/LoopInfo.cpp",
    "lib/Analysis/CFLAliasAnalysis.cpp",
    "lib/Analysis/Interval.cpp",
    "lib/Analysis/RegionPass.cpp",
    "lib/Analysis/LazyCallGraph.cpp",
    "lib/Analysis/AliasAnalysis.cpp",
};

// find lib/MSSupport | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_mssupport_sources = [_][]const u8{
    "lib/MSSupport/MSFileSystemImpl.cpp",
};

// find lib/Transforms/Utils | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_transforms_utils_sources = [_][]const u8{
    "lib/Transforms/Utils/LoopUtils.cpp",
    "lib/Transforms/Utils/DemoteRegToStack.cpp",
    "lib/Transforms/Utils/Utils.cpp",
    "lib/Transforms/Utils/SimplifyCFG.cpp",
    "lib/Transforms/Utils/LoopSimplifyId.cpp",
    "lib/Transforms/Utils/UnifyFunctionExitNodes.cpp",
    "lib/Transforms/Utils/SSAUpdater.cpp",
    "lib/Transforms/Utils/SimplifyIndVar.cpp",
    "lib/Transforms/Utils/BasicBlockUtils.cpp",
    "lib/Transforms/Utils/ASanStackFrameLayout.cpp",
    "lib/Transforms/Utils/FlattenCFG.cpp",
    "lib/Transforms/Utils/CmpInstAnalysis.cpp",
    "lib/Transforms/Utils/ModuleUtils.cpp",
    "lib/Transforms/Utils/LoopUnroll.cpp",
    "lib/Transforms/Utils/LowerSwitch.cpp",
    "lib/Transforms/Utils/LoopVersioning.cpp",
    "lib/Transforms/Utils/AddDiscriminators.cpp",
    "lib/Transforms/Utils/Local.cpp",
    "lib/Transforms/Utils/PromoteMemoryToRegister.cpp",
    "lib/Transforms/Utils/LCSSA.cpp",
    "lib/Transforms/Utils/BypassSlowDivision.cpp",
    "lib/Transforms/Utils/Mem2Reg.cpp",
    "lib/Transforms/Utils/CodeExtractor.cpp",
    "lib/Transforms/Utils/InlineFunction.cpp",
    "lib/Transforms/Utils/LoopSimplify.cpp",
    "lib/Transforms/Utils/SimplifyLibCalls.cpp",
    "lib/Transforms/Utils/MetaRenamer.cpp",
    "lib/Transforms/Utils/CloneModule.cpp",
    "lib/Transforms/Utils/IntegerDivision.cpp",
    "lib/Transforms/Utils/LoopUnrollRuntime.cpp",
    "lib/Transforms/Utils/ValueMapper.cpp",
    "lib/Transforms/Utils/InstructionNamer.cpp",
    "lib/Transforms/Utils/CtorUtils.cpp",
    "lib/Transforms/Utils/GlobalStatus.cpp",
    "lib/Transforms/Utils/LowerInvoke.cpp",
    "lib/Transforms/Utils/SimplifyInstructions.cpp",
    "lib/Transforms/Utils/BuildLibCalls.cpp",
    "lib/Transforms/Utils/SymbolRewriter.cpp",
    "lib/Transforms/Utils/BreakCriticalEdges.cpp",
    "lib/Transforms/Utils/CloneFunction.cpp",
};

// find lib/Transforms/InstCombine | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_transforms_instcombine_sources = [_][]const u8{
    "lib/Transforms/InstCombine/InstCombineCasts.cpp",
    "lib/Transforms/InstCombine/InstCombineCompares.cpp",
    "lib/Transforms/InstCombine/InstCombineSelect.cpp",
    "lib/Transforms/InstCombine/InstCombineCalls.cpp",
    "lib/Transforms/InstCombine/InstCombineSimplifyDemanded.cpp",
    "lib/Transforms/InstCombine/InstCombineAddSub.cpp",
    "lib/Transforms/InstCombine/InstructionCombining.cpp",
    "lib/Transforms/InstCombine/InstCombineMulDivRem.cpp",
    "lib/Transforms/InstCombine/InstCombineLoadStoreAlloca.cpp",
    "lib/Transforms/InstCombine/InstCombineShifts.cpp",
    "lib/Transforms/InstCombine/InstCombineVectorOps.cpp",
    "lib/Transforms/InstCombine/InstCombineAndOrXor.cpp",
    "lib/Transforms/InstCombine/InstCombinePHI.cpp",
};

// find lib/Transforms/IPO | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_transforms_ipo_sources = [_][]const u8{
    "lib/Transforms/IPO/ExtractGV.cpp",
    "lib/Transforms/IPO/GlobalDCE.cpp",
    "lib/Transforms/IPO/PruneEH.cpp",
    "lib/Transforms/IPO/MergeFunctions.cpp",
    "lib/Transforms/IPO/IPConstantPropagation.cpp",
    "lib/Transforms/IPO/ConstantMerge.cpp",
    "lib/Transforms/IPO/FunctionAttrs.cpp",
    "lib/Transforms/IPO/BarrierNoopPass.cpp",
    "lib/Transforms/IPO/StripSymbols.cpp",
    "lib/Transforms/IPO/Internalize.cpp",
    "lib/Transforms/IPO/StripDeadPrototypes.cpp",
    "lib/Transforms/IPO/DeadArgumentElimination.cpp",
    "lib/Transforms/IPO/ArgumentPromotion.cpp",
    "lib/Transforms/IPO/PassManagerBuilder.cpp",
    "lib/Transforms/IPO/LoopExtractor.cpp",
    "lib/Transforms/IPO/Inliner.cpp",
    "lib/Transforms/IPO/InlineAlways.cpp",
    "lib/Transforms/IPO/LowerBitSets.cpp",
    "lib/Transforms/IPO/InlineSimple.cpp",
    "lib/Transforms/IPO/PartialInlining.cpp",
    "lib/Transforms/IPO/ElimAvailExtern.cpp",
    "lib/Transforms/IPO/IPO.cpp",
    "lib/Transforms/IPO/GlobalOpt.cpp",
};

// find lib/Transforms/Scalar | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_transforms_scalar_sources = [_][]const u8{
    "lib/Transforms/Scalar/LoopRotation.cpp",
    "lib/Transforms/Scalar/LoopInstSimplify.cpp",
    "lib/Transforms/Scalar/ConstantProp.cpp",
    "lib/Transforms/Scalar/StructurizeCFG.cpp",
    "lib/Transforms/Scalar/IndVarSimplify.cpp",
    "lib/Transforms/Scalar/FlattenCFGPass.cpp",
    "lib/Transforms/Scalar/PartiallyInlineLibCalls.cpp",
    "lib/Transforms/Scalar/Scalarizer.cpp",
    "lib/Transforms/Scalar/ADCE.cpp",
    "lib/Transforms/Scalar/SCCP.cpp",
    "lib/Transforms/Scalar/InductiveRangeCheckElimination.cpp",
    "lib/Transforms/Scalar/LoopDistribute.cpp",
    "lib/Transforms/Scalar/Sink.cpp",
    "lib/Transforms/Scalar/DxilEliminateVector.cpp",
    "lib/Transforms/Scalar/CorrelatedValuePropagation.cpp",
    "lib/Transforms/Scalar/EarlyCSE.cpp",
    "lib/Transforms/Scalar/LoopUnrollPass.cpp",
    "lib/Transforms/Scalar/DxilLoopUnroll.cpp",
    "lib/Transforms/Scalar/GVN.cpp",
    "lib/Transforms/Scalar/ConstantHoisting.cpp",
    "lib/Transforms/Scalar/DxilEraseDeadRegion.cpp",
    "lib/Transforms/Scalar/Scalar.cpp",
    "lib/Transforms/Scalar/LoopInterchange.cpp",
    "lib/Transforms/Scalar/JumpThreading.cpp",
    "lib/Transforms/Scalar/Reg2MemHLSL.cpp",
    "lib/Transforms/Scalar/Reg2Mem.cpp",
    "lib/Transforms/Scalar/HoistConstantArray.cpp",
    "lib/Transforms/Scalar/ScalarReplAggregates.cpp",
    "lib/Transforms/Scalar/LoadCombine.cpp",
    "lib/Transforms/Scalar/SeparateConstOffsetFromGEP.cpp",
    "lib/Transforms/Scalar/Reassociate.cpp",
    "lib/Transforms/Scalar/LoopIdiomRecognize.cpp",
    "lib/Transforms/Scalar/SampleProfile.cpp",
    "lib/Transforms/Scalar/DeadStoreElimination.cpp",
    "lib/Transforms/Scalar/SimplifyCFGPass.cpp",
    "lib/Transforms/Scalar/LoopStrengthReduce.cpp",
    "lib/Transforms/Scalar/DxilRemoveDeadBlocks.cpp",
    "lib/Transforms/Scalar/LoopRerollPass.cpp",
    "lib/Transforms/Scalar/LowerAtomic.cpp",
    "lib/Transforms/Scalar/MemCpyOptimizer.cpp",
    "lib/Transforms/Scalar/BDCE.cpp",
    "lib/Transforms/Scalar/LowerExpectIntrinsic.cpp",
    "lib/Transforms/Scalar/DxilFixConstArrayInitializer.cpp",
    "lib/Transforms/Scalar/ScalarReplAggregatesHLSL.cpp",
    "lib/Transforms/Scalar/Float2Int.cpp",
    "lib/Transforms/Scalar/LoopDeletion.cpp",
    "lib/Transforms/Scalar/SROA.cpp",
    "lib/Transforms/Scalar/MergedLoadStoreMotion.cpp",
    "lib/Transforms/Scalar/DCE.cpp",
    "lib/Transforms/Scalar/AlignmentFromAssumptions.cpp",
    "lib/Transforms/Scalar/DxilRemoveUnstructuredLoopExits.cpp",
    "lib/Transforms/Scalar/SpeculativeExecution.cpp",
    "lib/Transforms/Scalar/NaryReassociate.cpp",
    "lib/Transforms/Scalar/LoopUnswitch.cpp",
    "lib/Transforms/Scalar/RewriteStatepointsForGC.cpp",
    "lib/Transforms/Scalar/LICM.cpp",
    "lib/Transforms/Scalar/DxilConditionalMem2Reg.cpp",
    "lib/Transforms/Scalar/PlaceSafepoints.cpp",
    "lib/Transforms/Scalar/LowerTypePasses.cpp",
    "lib/Transforms/Scalar/TailRecursionElimination.cpp",
    "lib/Transforms/Scalar/StraightLineStrengthReduce.cpp",
};

// find lib/Transforms/Vectorize | grep -v 'BBVectorize.cpp' | grep -v 'LoopVectorize.cpp' | grep -v 'LPVectorizer.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_transforms_vectorize_sources = [_][]const u8{
    "lib/Transforms/Vectorize/Vectorize.cpp",
};

// find lib/Target | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_target_sources = [_][]const u8{
    "lib/Target/TargetSubtargetInfo.cpp",
    "lib/Target/TargetLoweringObjectFile.cpp",
    "lib/Target/Target.cpp",
    "lib/Target/TargetRecip.cpp",
    "lib/Target/TargetMachine.cpp",
    "lib/Target/TargetIntrinsicInfo.cpp",
    "lib/Target/TargetMachineC.cpp",
};

// find lib/ProfileData | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_profiledata_sources = [_][]const u8{
    "lib/ProfileData/InstrProfReader.cpp",
    "lib/ProfileData/CoverageMappingWriter.cpp",
    "lib/ProfileData/CoverageMapping.cpp",
    "lib/ProfileData/InstrProfWriter.cpp",
    "lib/ProfileData/CoverageMappingReader.cpp",
    "lib/ProfileData/SampleProfWriter.cpp",
    "lib/ProfileData/SampleProf.cpp",
    "lib/ProfileData/InstrProf.cpp",
    "lib/ProfileData/SampleProfReader.cpp",
};

// find lib/Option | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_option_sources = [_][]const u8{
    "lib/Option/Arg.cpp",
    "lib/Option/OptTable.cpp",
    "lib/Option/Option.cpp",
    "lib/Option/ArgList.cpp",
};

// find lib/PassPrinters | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_passprinters_sources = [_][]const u8{
    "lib/PassPrinters/PassPrinters.cpp",
};

// find lib/Passes | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_passes_sources = [_][]const u8{
    "lib/Passes/PassBuilder.cpp",
};

// find lib/HLSL | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_hlsl_sources = [_][]const u8{
    "lib/HLSL/HLLegalizeParameter.cpp",
    "lib/HLSL/HLOperations.cpp",
    "lib/HLSL/DxilExportMap.cpp",
    "lib/HLSL/DxilPrecisePropagatePass.cpp",
    "lib/HLSL/DxilPatchShaderRecordBindings.cpp",
    "lib/HLSL/HLUtil.cpp",
    "lib/HLSL/DxilCondenseResources.cpp",
    "lib/HLSL/DxilValidation.cpp",
    "lib/HLSL/DxilDeleteRedundantDebugValues.cpp",
    "lib/HLSL/DxilNoops.cpp",
    "lib/HLSL/ComputeViewIdState.cpp",
    "lib/HLSL/HLMatrixType.cpp",
    "lib/HLSL/DxilPackSignatureElement.cpp",
    "lib/HLSL/DxilLegalizeSampleOffsetPass.cpp",
    "lib/HLSL/HLModule.cpp",
    "lib/HLSL/DxilContainerReflection.cpp",
    "lib/HLSL/DxilLegalizeEvalOperations.cpp",
    "lib/HLSL/ControlDependence.cpp",
    "lib/HLSL/DxilTargetTransformInfo.cpp",
    "lib/HLSL/HLOperationLower.cpp",
    "lib/HLSL/DxilSignatureValidation.cpp",
    "lib/HLSL/DxilRenameResourcesPass.cpp",
    "lib/HLSL/DxilPromoteResourcePasses.cpp",
    "lib/HLSL/PauseResumePasses.cpp",
    "lib/HLSL/HLDeadFunctionElimination.cpp",
    "lib/HLSL/DxilExpandTrigIntrinsics.cpp",
    "lib/HLSL/DxilPoisonValues.cpp",
    "lib/HLSL/DxilGenerationPass.cpp",
    "lib/HLSL/DxilTranslateRawBuffer.cpp",
    "lib/HLSL/ComputeViewIdStateBuilder.cpp",
    "lib/HLSL/DxilTargetLowering.cpp",
    "lib/HLSL/DxilNoOptLegalize.cpp",
    "lib/HLSL/HLExpandStoreIntrinsics.cpp",
    "lib/HLSL/HLMetadataPasses.cpp",
    "lib/HLSL/DxilPreparePasses.cpp",
    "lib/HLSL/HLMatrixBitcastLowerPass.cpp",
    "lib/HLSL/HLPreprocess.cpp",
    "lib/HLSL/HLSignatureLower.cpp",
    "lib/HLSL/HLMatrixLowerPass.cpp",
    "lib/HLSL/HLResource.cpp",
    "lib/HLSL/HLLowerUDT.cpp",
    "lib/HLSL/HLOperationLowerExtension.cpp",
    "lib/HLSL/DxilEliminateOutputDynamicIndexing.cpp",
    "lib/HLSL/DxilSimpleGVNHoist.cpp",
    "lib/HLSL/DxcOptimizer.cpp",
    "lib/HLSL/DxilLinker.cpp",
    "lib/HLSL/DxilConvergent.cpp",
    "lib/HLSL/DxilLoopDeletion.cpp",
    "lib/HLSL/WaveSensitivityAnalysis.cpp",
    "lib/HLSL/DxilPreserveAllOutputs.cpp",
    "lib/HLSL/HLMatrixSubscriptUseReplacer.cpp",
};

// find lib/Support | grep -v 'DynamicLibrary.cpp' | grep -v 'PluginLoader.cpp' | grep -v '\.inc\.cpp' | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_support_cpp_sources = [_][]const u8{
    "lib/Support/BranchProbability.cpp",
    "lib/Support/Memory.cpp",
    "lib/Support/ToolOutputFile.cpp",
    "lib/Support/YAMLTraits.cpp",
    "lib/Support/MD5.cpp",
    "lib/Support/Mutex.cpp",
    "lib/Support/Program.cpp",
    "lib/Support/APFloat.cpp",
    "lib/Support/SpecialCaseList.cpp",
    "lib/Support/LEB128.cpp",
    "lib/Support/FileOutputBuffer.cpp",
    "lib/Support/Process.cpp",
    "lib/Support/regmalloc.cpp",
    "lib/Support/ScaledNumber.cpp",
    "lib/Support/Locale.cpp",
    "lib/Support/TimeProfiler.cpp",
    "lib/Support/FileUtilities.cpp",
    "lib/Support/TimeValue.cpp",
    "lib/Support/TargetRegistry.cpp",
    "lib/Support/Statistic.cpp",
    "lib/Support/Twine.cpp",
    "lib/Support/DAGDeltaAlgorithm.cpp",
    "lib/Support/APSInt.cpp",
    "lib/Support/SearchForAddressOfSpecialSymbol.cpp",
    "lib/Support/LineIterator.cpp",
    "lib/Support/PrettyStackTrace.cpp",
    "lib/Support/Timer.cpp",
    "lib/Support/ConvertUTFWrapper.cpp",
    "lib/Support/LockFileManager.cpp",
    "lib/Support/assert.cpp",
    "lib/Support/ARMBuildAttrs.cpp",
    "lib/Support/CrashRecoveryContext.cpp",
    "lib/Support/Options.cpp",
    "lib/Support/DeltaAlgorithm.cpp",
    "lib/Support/SystemUtils.cpp",
    "lib/Support/ThreadLocal.cpp",
    "lib/Support/YAMLParser.cpp",
    "lib/Support/StringPool.cpp",
    "lib/Support/IntrusiveRefCntPtr.cpp",
    "lib/Support/Watchdog.cpp",
    "lib/Support/StringRef.cpp",
    "lib/Support/Compression.cpp",
    "lib/Support/COM.cpp",
    "lib/Support/FoldingSet.cpp",
    "lib/Support/FormattedStream.cpp",
    "lib/Support/BlockFrequency.cpp",
    "lib/Support/IntervalMap.cpp",
    "lib/Support/MemoryObject.cpp",
    "lib/Support/TargetParser.cpp",
    "lib/Support/raw_os_ostream.cpp",
    "lib/Support/Allocator.cpp",
    "lib/Support/DataExtractor.cpp",
    "lib/Support/APInt.cpp",
    "lib/Support/StreamingMemoryObject.cpp",
    "lib/Support/circular_raw_ostream.cpp",
    "lib/Support/DataStream.cpp",
    "lib/Support/Debug.cpp",
    "lib/Support/Errno.cpp",
    "lib/Support/Path.cpp",
    "lib/Support/raw_ostream.cpp",
    "lib/Support/Atomic.cpp",
    "lib/Support/SmallVector.cpp",
    "lib/Support/MathExtras.cpp",
    "lib/Support/MemoryBuffer.cpp",
    "lib/Support/ErrorHandling.cpp",
    "lib/Support/StringExtras.cpp",
    "lib/Support/Triple.cpp",
    "lib/Support/Hashing.cpp",
    "lib/Support/GraphWriter.cpp",
    "lib/Support/RandomNumberGenerator.cpp",
    "lib/Support/SourceMgr.cpp",
    "lib/Support/Signals.cpp",
    "lib/Support/Dwarf.cpp",
    "lib/Support/StringMap.cpp",
    "lib/Support/MSFileSystemBasic.cpp",
    "lib/Support/IntEqClasses.cpp",
    "lib/Support/Threading.cpp",
    "lib/Support/RWMutex.cpp",
    "lib/Support/StringSaver.cpp",
    "lib/Support/CommandLine.cpp",
    "lib/Support/ManagedStatic.cpp",
    "lib/Support/Host.cpp",
    "lib/Support/Unicode.cpp",
    "lib/Support/SmallPtrSet.cpp",
    "lib/Support/Valgrind.cpp",
    "lib/Support/Regex.cpp",
    "lib/Support/ARMWinEH.cpp",
};

// find lib/Support | grep '\.c$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_support_c_sources = [_][]const u8{
    "lib/Support/ConvertUTF.c",
    "lib/Support/regexec.c",
    "lib/Support/regcomp.c",
    "lib/Support/regerror.c",
    "lib/Support/regstrlcpy.c",
    "lib/Support/regfree.c",
};

// find lib/DxcSupport | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxcsupport_sources = [_][]const u8{
    "lib/DxcSupport/WinIncludes.cpp",
    "lib/DxcSupport/HLSLOptions.cpp",
    "lib/DxcSupport/dxcmem.cpp",
    "lib/DxcSupport/WinFunctions.cpp",
    "lib/DxcSupport/Global.cpp",
    "lib/DxcSupport/Unicode.cpp",
    "lib/DxcSupport/FileIOHelper.cpp",
    "lib/DxcSupport/dxcapi.use.cpp",
    "lib/DxcSupport/WinAdapter.cpp",
};

// find lib/DxcBindingTable | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxcbindingtable_sources = [_][]const u8{
    "lib/DxcBindingTable/DxcBindingTable.cpp",
};

// find lib/DXIL | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxil_sources = [_][]const u8{
    "lib/DXIL/DxilInterpolationMode.cpp",
    "lib/DXIL/DxilCompType.cpp",
    "lib/DXIL/DxilShaderFlags.cpp",
    "lib/DXIL/DxilResourceBase.cpp",
    "lib/DXIL/DxilResource.cpp",
    "lib/DXIL/DxilOperations.cpp",
    "lib/DXIL/DxilSignature.cpp",
    "lib/DXIL/DxilResourceProperties.cpp",
    "lib/DXIL/DxilPDB.cpp",
    "lib/DXIL/DxilNodeProps.cpp",
    "lib/DXIL/DxilWaveMatrix.cpp",
    "lib/DXIL/DxilUtilDbgInfoAndMisc.cpp",
    "lib/DXIL/DxilSignatureElement.cpp",
    "lib/DXIL/DxilSemantic.cpp",
    "lib/DXIL/DxilSampler.cpp",
    "lib/DXIL/DxilModuleHelper.cpp",
    "lib/DXIL/DxilResourceBinding.cpp",
    "lib/DXIL/DxilTypeSystem.cpp",
    "lib/DXIL/DxilCounters.cpp",
    "lib/DXIL/DxilCBuffer.cpp",
    "lib/DXIL/DxilUtil.cpp",
    "lib/DXIL/DxilSubobject.cpp",
    "lib/DXIL/DxilShaderModel.cpp",
    "lib/DXIL/DxilMetadataHelper.cpp",
    "lib/DXIL/DxilModule.cpp",
};

// find lib/DxilContainer | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxilcontainer_sources = [_][]const u8{
    "lib/DxilContainer/DxilRuntimeReflection.cpp", 
    "lib/DxilContainer/DxilRDATBuilder.cpp",
    "lib/DxilContainer/RDATDumper.cpp",
    "lib/DxilContainer/DxilContainerReader.cpp",
    "lib/DxilContainer/D3DReflectionStrings.cpp",
    "lib/DxilContainer/DxilContainer.cpp",
    "lib/DxilContainer/RDATDxilSubobjects.cpp",
    "lib/DxilContainer/D3DReflectionDumper.cpp",
    "lib/DxilContainer/DxcContainerBuilder.cpp",
    "lib/DxilContainer/DxilContainerAssembler.cpp",
};

// find lib/DxilPIXPasses | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxilpixpasses_sources = [_][]const u8{
    "lib/DxilPIXPasses/DxilDbgValueToDbgDeclare.cpp",
    "lib/DxilPIXPasses/DxilRemoveDiscards.cpp",
    "lib/DxilPIXPasses/DxilPIXDXRInvocationsLog.cpp",
    "lib/DxilPIXPasses/DxilForceEarlyZ.cpp",
    "lib/DxilPIXPasses/DxilAnnotateWithVirtualRegister.cpp",
    "lib/DxilPIXPasses/DxilPIXAddTidToAmplificationShaderPayload.cpp",
    "lib/DxilPIXPasses/DxilDebugInstrumentation.cpp",
    "lib/DxilPIXPasses/DxilPIXPasses.cpp",
    "lib/DxilPIXPasses/PixPassHelpers.cpp",
    "lib/DxilPIXPasses/DxilPIXVirtualRegisters.cpp",
    "lib/DxilPIXPasses/DxilShaderAccessTracking.cpp",
    "lib/DxilPIXPasses/DxilOutputColorBecomesConstant.cpp",
    "lib/DxilPIXPasses/DxilReduceMSAAToSingleSample.cpp",
    "lib/DxilPIXPasses/DxilAddPixelHitInstrumentation.cpp",
    "lib/DxilPIXPasses/DxilPIXMeshShaderOutputInstrumentation.cpp",
};

// find lib/DxilCompression | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxilcompression_cpp_sources = [_][]const u8{
    "lib/DxilCompression/DxilCompression.cpp",
};

// find lib/DxilCompression | grep '\.c$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxilcompression_c_sources = [_][]const u8{
    "lib/DxilCompression/miniz.c",
};

// find lib/DxilRootSignature | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const lib_dxilrootsignature_sources = [_][]const u8{
    "lib/DxilRootSignature/DxilRootSignature.cpp",
    "lib/DxilRootSignature/DxilRootSignatureSerializer.cpp",
    "lib/DxilRootSignature/DxilRootSignatureConvert.cpp",
    "lib/DxilRootSignature/DxilRootSignatureValidator.cpp",
};

// find external/SPIRV-Tools/source | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const tools_clang_lib_spirv = [_][]const u8{
    "tools/clang/lib/SPIRV/RemoveBufferBlockVisitor.cpp",
    "tools/clang/lib/SPIRV/LiteralTypeVisitor.cpp",
    "tools/clang/lib/SPIRV/AlignmentSizeCalculator.cpp",
    "tools/clang/lib/SPIRV/RawBufferMethods.cpp",
    "tools/clang/lib/SPIRV/GlPerVertex.cpp",
    "tools/clang/lib/SPIRV/SpirvFunction.cpp",
    "tools/clang/lib/SPIRV/LowerTypeVisitor.cpp",
    "tools/clang/lib/SPIRV/SpirvInstruction.cpp",
    "tools/clang/lib/SPIRV/DeclResultIdMapper.cpp",
    "tools/clang/lib/SPIRV/SpirvEmitter.cpp",
    "tools/clang/lib/SPIRV/SpirvBuilder.cpp",
    "tools/clang/lib/SPIRV/FeatureManager.cpp",
    "tools/clang/lib/SPIRV/SpirvModule.cpp",
    "tools/clang/lib/SPIRV/BlockReadableOrder.cpp",
    "tools/clang/lib/SPIRV/SignaturePackingUtil.cpp",
    "tools/clang/lib/SPIRV/CapabilityVisitor.cpp",
    "tools/clang/lib/SPIRV/SpirvBasicBlock.cpp",
    "tools/clang/lib/SPIRV/NonUniformVisitor.cpp",
    "tools/clang/lib/SPIRV/RelaxedPrecisionVisitor.cpp",
    "tools/clang/lib/SPIRV/SpirvType.cpp",
    "tools/clang/lib/SPIRV/SortDebugInfoVisitor.cpp",
    "tools/clang/lib/SPIRV/SpirvContext.cpp",
    "tools/clang/lib/SPIRV/PreciseVisitor.cpp",
    "tools/clang/lib/SPIRV/EmitSpirvAction.cpp",
    "tools/clang/lib/SPIRV/PervertexInputVisitor.cpp",
    "tools/clang/lib/SPIRV/EmitVisitor.cpp",
    "tools/clang/lib/SPIRV/String.cpp",
    "tools/clang/lib/SPIRV/AstTypeProbe.cpp",
    "tools/clang/lib/SPIRV/DebugTypeVisitor.cpp",
    "tools/clang/lib/SPIRV/InitListHandler.cpp",
    "tools/clang/lib/SPIRV/ConstEvaluator.cpp",
};