const std = @import("std");
const builtin = @import("builtin");
const llvmconf = @import("llvm_config.zig");
const Build = std.Build;

const log = std.log.scoped(.dxcompiler_headers);

fn ensureCommandExists(allocator: std.mem.Allocator, name: []const u8, exist_check: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ name, exist_check },
        .cwd = ".",
    }) catch // e.g. FileNotFound
        {
        return false;
    };

    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    if (result.term.Exited != 0)
        return false;

    return true;
}

// -----------------------
// Header generation logic
// -----------------------

pub const header_output_path = "generated-include";

const hctgen_script = "utils/hct/hctgen.py";
const hctdb_script = "utils/hct/hctdb.py";
const hctdb_helper_script = "utils/hct/hctdb_instrhelp.py";
const gen_version_script = "utils/version/gen_version.py";


// From cmake/modules/HCT.cmake
fn addHLSLhctgen(b: *Build, mode: []const u8, output_file: []const u8) *Build.Step.Run { 
    const python_cmd = b.addSystemCommand(&.{ "python3" });

    python_cmd.setCwd(b.path("."));
    python_cmd.addFileArg(b.path(hctgen_script));

    python_cmd.addArg("--force-lf");
    python_cmd.addArg(mode);
    python_cmd.addArg("--output");
    python_cmd.addFileArg(b.path(header_output_path).path(b, output_file));

    return python_cmd;
}   

// From utils/version/CMakeLists.txt
fn generateVersionFile(b: *Build, comptime output_file: []const u8, comptime gen_flags: []const u8) *Build.Step.Run {
    const python_cmd = b.addSystemCommand(&.{ "python3" });

    python_cmd.setCwd(b.path("."));
    python_cmd.addFileArg(b.path(gen_version_script));

    python_cmd.addArg(gen_flags);
    python_cmd.addArg("--output");
    python_cmd.addFileArg(b.path(header_output_path).path(b, output_file));

    return python_cmd;
}

fn configureLLVMTablegenExecutable(b: *Build, name: []const u8, files: []const []const u8, optimize: std.builtin.OptimizeMode) *Build.Step.Compile {
    // TableGen will always only run on the host machine on build, so the target will always be the host.
    const target = b.resolveTargetQuery(.{});

    const tablegen_exe = b.addExecutable(.{
        .name = name,
        .optimize = optimize,
        .target = target,
    });

    const base_flags = [_][]const u8{
        "-Wno-unused-command-line-argument",
        "-Wno-unused-variable",
        "-Wno-missing-exception-spec",
        "-Wno-macro-redefined",
        "-Wno-unknown-attributes",
        "-Wno-implicit-fallthrough",
        "-fms-extensions", // __uuidof and friends (on non-windows targets)
    };

    // Source files
    tablegen_exe.addCSourceFiles(.{
        .files = files,
        .flags = &(base_flags ++ .{ "-std=c++17"} )
    });

    // support files
    tablegen_exe.addCSourceFiles(.{
        .files = &(lib_support ++ lib_mssupport),
        .flags = &(base_flags ++ .{ "-std=c++17"} )
    });

    // C support files
    tablegen_exe.addCSourceFiles(.{
        .files = &lib_support_c,
        .flags = &base_flags
    });

    tablegen_exe.addIncludePath(b.path("include"));
    tablegen_exe.linkLibCpp();
    
    if (target.result.os.tag != .windows) 
        tablegen_exe.addIncludePath(b.path("external/DirectX-Headers/include/wsl/stubs"));

    llvmconf.addConfigHeaders(b, tablegen_exe);

    return tablegen_exe;
}

fn ensureFile(b: *Build, file: Build.LazyPath) void
{
    b.build_root.handle.makePath(file.dirname().getPath(b))
    catch |err| 
    {
        log.err("Failed to create output path for file: {s}", .{ @errorName(err) });
        std.process.exit(1);
    };

    const file_handle = b.build_root.handle.createFile(file.getPath(b), .{})
    catch |err|
    {
        log.err("Failed to create file: {s}", .{ @errorName(err) });
        std.process.exit(1);
    };

    file_handle.close();
}

const clang_path = "tools/clang/include/clang/";
const clang_out = "clang/";

const include_paths = [_][]const u8{
    "-I", "./",
    "-I", "lib/Target",
    "-I", "include",
    "-I", "tools/clang/include",
    "-I", "tools/clang/include/clang",
};

fn tablegen(b: *Build, tablegen_exe: *Build.Step.Compile, tablegen_file: Build.LazyPath, output_file: Build.LazyPath, additional_args: []const []const u8) *Build.Step.Run {
    const tablegen_cmd = b.addRunArtifact(tablegen_exe);

    tablegen_cmd.setCwd(b.path("."));

    ensureFile(b, output_file);
    
    tablegen_cmd.addArgs(additional_args);
    tablegen_cmd.addArgs(&include_paths);
    tablegen_cmd.addArg("-I");
    tablegen_cmd.addFileArg(tablegen_file.dirname());
    tablegen_cmd.addFileArg(tablegen_file);
    tablegen_cmd.addArg("-o");
    tablegen_cmd.addFileArg(output_file);

    return tablegen_cmd;
}

// Emulates behavior of diagnostic tablegen macro in tools/clang/include/clang/Basic/CMakeLists.txt
fn diagTablegen(b: *Build, tablegen_exe: *Build.Step.Compile, diagnostic_path: Build.LazyPath, output_path: Build.LazyPath, comptime component_name: []const u8) *Build.Step.Run {
    return tablegen(b, tablegen_exe, 
        diagnostic_path, 
        output_path.path(b, "Diagnostic" ++ component_name ++ "Kinds.inc"),
        &.{ "-gen-clang-diags-defs", "-clang-component=" ++ component_name });
}

pub fn buildDXCHeaders(b: *Build, optimize: std.builtin.OptimizeMode) *std.Build.Step 
{    
// ------------------
// hctgen.py tablegen
// ------------------

    if (!ensureCommandExists(b.allocator, "python3", "--version")) {
        log.err("'python3 --version' failed. Ensure a valid python3 installation is present on the path.", .{});
        std.process.exit(1);
    }

    const headers_step = b.step("build-headers", "Build DXC headers");
    
    // In the cmake build system, these files map to all invocations to `add_hlsl_hctgen` with the BUILD_DIR option on. 
    // Invocations without BUILD_DIR (I think?) are not required to be present in `generated-include`.  
    headers_step.dependOn(&addHLSLhctgen(b, "DxilValidationInc", "dxc/HLSL/DxilValidation.inc").step);
    headers_step.dependOn(&addHLSLhctgen(b, "DxilPIXPasses", "DxilPIXPasses.inc").step);
    headers_step.dependOn(&addHLSLhctgen(b, "DxcOptimizer", "DxcOptimizer.inc").step);
    headers_step.dependOn(&addHLSLhctgen(b, "DxilValidation", "DxilValidationImpl.inc").step);
    headers_step.dependOn(&addHLSLhctgen(b, "DxilIntrinsicTables", "gen_intrin_main_tables_15.h").step);
    headers_step.dependOn(&addHLSLhctgen(b, "DxcDisassembler", "DxcDisassembler.inc").step);
    
    //copyVersionFile("dxcversion.inc"); // Use a fixed version file (version/version.inc)
    headers_step.dependOn(&generateVersionFile(b, "dxcversion.inc", "--official").step); // Dynamically generate the version file

    // llvm-tblgen executable
    const llvm_tablegen = configureLLVMTablegenExecutable(b, "llvm-tblgen", &(llvm_utils_tablegen ++ lib_tablegen), optimize);

    // clang-tblgen executable
    const clang_tablegen = configureLLVMTablegenExecutable(b, "clang-tblgen", &(clang_tools_clang_utils_tablegen ++ lib_tablegen), optimize);

    headers_step.dependOn(&b.addInstallArtifact(llvm_tablegen, .{}).step);
    headers_step.dependOn(&b.addInstallArtifact(clang_tablegen, .{}).step);

    const out_path = b.path(header_output_path);

    // dxcetw.h must be empty since we can't guarantee that the host device has the Message Compiler (mc) installed.
    // Regardless, it doesn't matter since the instrumentation manifest is only important for perf/debug analyzing.
    ensureFile(b, out_path.path(b, "dxcetw.h"));

// -------------
// LLVM tablegen
// -------------

// -----------------------------------------------------------------
// DXC support include file. From include/dxc/Support/CMakeLists.txt
// -----------------------------------------------------------------
    
    // All cmake function invocations for `tablegen`
    headers_step.dependOn(&tablegen(b, llvm_tablegen, 
        b.path("include/dxc/Support/HLSLOptions.td"), 
        out_path.path(b, "dxc/Support/HLSLOptions.inc"), 
        &.{ "-gen-opt-parser-defs" }).step);

// ---------------------------------------------------------
// LLVM IR include file. From include/llvm/IR/CMakeLists.txt
// ---------------------------------------------------------

    headers_step.dependOn(&tablegen(b, llvm_tablegen, 
        b.path("include/llvm/IR/Intrinsics.td"), 
        out_path.path(b, "llvm/IR/Intrinsics.gen"), 
        &.{ "-gen-intrinsic" }).step);

// --------------
// Clang tablegen
// -------------- 

    const clang_src_path = b.path(clang_path);
    const clang_out_path = out_path.path(b, clang_out);

// -------------------------------------------------------------------------
// Driver include file. From tools/clang/include/clang/Driver/CMakeLists.txt
// -------------------------------------------------------------------------

    headers_step.dependOn(&tablegen(b, llvm_tablegen,
        clang_src_path.path(b, "Driver/Options.td"), 
        clang_out_path.path(b, "Driver/Options.inc"), 
        &.{ "-gen-opt-parser-defs" }).step);

// -----------------------------------------------------------------------
// AST include files. From tools/clang/include/clang/Driver/CMakeLists.txt
// -----------------------------------------------------------------------

    const src_basic_path = clang_src_path.path(b, "Basic");
    const src_ast_path = clang_src_path.path(b, "AST");

    const out_ast_path = clang_out_path.path(b, "AST");
    const attr_path = src_basic_path.path(b, "Attr.td");
    
    // From tools/clang/include/clang/Driver/CMakeLists.txt
    headers_step.dependOn(&tablegen(b, clang_tablegen,
        attr_path, 
        out_ast_path.path(b, "Attrs.inc"), 
        &.{ "-gen-clang-attr-classes" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen,
        attr_path,
        out_ast_path.path(b, "AttrImpl.inc"), 
        &.{ "-gen-clang-attr-impl" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen,
        attr_path,
        out_ast_path.path(b, "AttrDump.inc"), 
        &.{ "-gen-clang-attr-dump" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        out_ast_path.path(b, "AttrVisitor.inc"), 
        &.{ "-gen-clang-attr-ast-visitor" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_basic_path.path(b, "StmtNodes.td"), 
        out_ast_path.path(b, "StmtNodes.inc"), 
        &.{ "-gen-clang-stmt-nodes" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_basic_path.path(b, "DeclNodes.td"), 
        out_ast_path.path(b, "DeclNodes.inc"), 
        &.{ "-gen-clang-decl-nodes" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_basic_path.path(b, "CommentNodes.td"), 
        out_ast_path.path(b, "CommentNodes.inc"), 
        &.{ "-gen-clang-comment-nodes" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_ast_path.path(b, "CommentHTMLTags.td"), 
        out_ast_path.path(b, "CommentHTMLTags.inc"),
        &.{ "-gen-clang-comment-html-tags" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_ast_path.path(b, "CommentHTMLTags.td"), 
        out_ast_path.path(b, "CommentHTMLTagsProperties.inc"),
        &.{ "-gen-clang-comment-html-tags-properties" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_ast_path.path(b, "CommentHTMLNamedCharacterReferences.td"), 
        out_ast_path.path(b, "CommentHTMLNamedCharacterReferences.inc"),
        &.{ "-gen-clang-comment-html-named-character-references" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_ast_path.path(b, "CommentCommands.td"), 
        out_ast_path.path(b, "CommentCommandInfo.inc"),
        &.{ "-gen-clang-comment-command-info" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_ast_path.path(b, "CommentCommands.td"), 
        out_ast_path.path(b, "CommentCommandList.inc"),
        &.{ "-gen-clang-comment-command-list" }).step);

// ------------------------------------------------------------------------
// Basic include files. From tools/clang/include/clang/Basic/CMakeLists.txt
// ------------------------------------------------------------------------

    const diagnostic_path = src_basic_path.path(b, "Diagnostic.td");
    const out_basic_path = clang_out_path.path(b, "Basic");

    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Analysis").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "AST").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Comment").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Common").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Driver").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Frontend").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Lex").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Parse").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Sema").step);
    headers_step.dependOn(&diagTablegen(b, clang_tablegen, diagnostic_path, out_basic_path, "Serialization").step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        diagnostic_path,
        out_basic_path.path(b, "DiagnosticGroups.inc"),
        &.{ "-gen-clang-diag-groups" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        diagnostic_path,
        out_basic_path.path(b, "DiagnosticIndexName.inc"),
        &.{ "-gen-clang-diags-index-name" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        out_basic_path.path(b, "AttrList.inc"),
        &.{ "-gen-clang-attr-list" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        out_basic_path.path(b, "AttrHasAttributeImpl.inc"),
        &.{ "-gen-clang-attr-has-attribute-impl" }).step);

// -----------------------------------------------------------------------
// Parse include file. From tools/clang/include/clang/Parse/CMakeLists.txt
// -----------------------------------------------------------------------

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        clang_out_path.path(b, "Parse/AttrParserStringSwitches.inc"),
        &.{ "-gen-clang-attr-parser-string-switches" }).step);

// ----------------------------------------------------------------------
// Sema include files. From tools/clang/include/clang/Sema/CMakeLists.txt
// ----------------------------------------------------------------------

    const sema_out_path = clang_out_path.path(b, "Sema");

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        sema_out_path.path(b, "AttrTemplateInstantiate.inc"),
        &.{ "-gen-clang-attr-template-instantiate" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        sema_out_path.path(b, "AttrParsedAttrList.inc"),
        &.{ "-gen-clang-attr-parsed-attr-list" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        sema_out_path.path(b, "AttrParsedAttrKinds.inc"),
        &.{ "-gen-clang-attr-parsed-attr-kinds" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        sema_out_path.path(b, "AttrSpellingListIndex.inc"),
        &.{ "-gen-clang-attr-spelling-index" }).step);

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        sema_out_path.path(b, "AttrParsedAttrImpl.inc"),
        &.{ "-gen-clang-attr-parsed-attr-impl" }).step);

// ----------------------------------------------------------------------------------------
// Serialization include files. From tools/clang/include/clang/Serialization/CMakeLists.txt
// ----------------------------------------------------------------------------------------
    
    const serialization_out_path = clang_out_path.path(b, "Serialization");

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        serialization_out_path.path(b, "AttrPCHRead.inc"),
        &.{ "-gen-clang-attr-pch-read" }).step);
    
    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        attr_path,
        serialization_out_path.path(b, "AttrPCHWrite.inc"),
        &.{ "-gen-clang-attr-pch-write" }).step);
    
// ---------------------------------------------------------------------------
// Headers include file. From tools/clang/include/clang/Headers/CMakeLists.txt
// ---------------------------------------------------------------------------

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        src_basic_path.path(b, "arm_neon.td"),
        clang_out_path.path(b, "Headers/arm_neon.h"),
        &.{ "-gen-arm-neon" }).step);

// -------------------------------------------------------------------------
// Checkers include file. From tools/clang/lib/StaticAnalyzer/CMakeLists.txt
// -------------------------------------------------------------------------

    const clang_lib_path = b.path("tools/clang/lib");

    headers_step.dependOn(&tablegen(b, clang_tablegen, 
        clang_lib_path.path(b, "StaticAnalyzer/Checkers/Checkers.td"),
        clang_out_path.path(b, "StaticAnalyzer/Checkers.inc"),
        &.{ "-gen-clang-sa-checkers" }).step);
    
    return headers_step;
}

// find utils/TableGen | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const llvm_utils_tablegen = [_][]const u8{
    "utils/TableGen/AsmMatcherEmitter.cpp",
    "utils/TableGen/AsmWriterEmitter.cpp",
    "utils/TableGen/AsmWriterInst.cpp",
    "utils/TableGen/CallingConvEmitter.cpp",
    "utils/TableGen/CodeEmitterGen.cpp",
    "utils/TableGen/CodeGenDAGPatterns.cpp",
    "utils/TableGen/CodeGenInstruction.cpp",
    "utils/TableGen/CodeGenMapTable.cpp",
    "utils/TableGen/CodeGenRegisters.cpp",
    "utils/TableGen/CodeGenSchedule.cpp",
    "utils/TableGen/CodeGenTarget.cpp",
    "utils/TableGen/DAGISelEmitter.cpp",
    "utils/TableGen/DAGISelMatcherEmitter.cpp",
    "utils/TableGen/DAGISelMatcherGen.cpp",
    "utils/TableGen/DAGISelMatcherOpt.cpp",
    "utils/TableGen/DAGISelMatcher.cpp",
    "utils/TableGen/DFAPacketizerEmitter.cpp",
    "utils/TableGen/DisassemblerEmitter.cpp",
    "utils/TableGen/FastISelEmitter.cpp",
    "utils/TableGen/FixedLenDecoderEmitter.cpp",
    "utils/TableGen/InstrInfoEmitter.cpp",
    "utils/TableGen/IntrinsicEmitter.cpp",
    "utils/TableGen/OptParserEmitter.cpp",
    "utils/TableGen/PseudoLoweringEmitter.cpp",
    "utils/TableGen/RegisterInfoEmitter.cpp",
    "utils/TableGen/SubtargetEmitter.cpp",
    "utils/TableGen/TableGen.cpp",
    "utils/TableGen/CTagsEmitter.cpp",
};

const lib_tablegen = [_][]const u8{
    "lib/TableGen/Error.cpp",
    "lib/TableGen/Main.cpp",
    "lib/TableGen/Record.cpp",
    "lib/TableGen/SetTheory.cpp",
    "lib/TableGen/StringMatcher.cpp",
    "lib/TableGen/TableGenBackend.cpp",
    "lib/TableGen/TGLexer.cpp",
    "lib/TableGen/TGParser.cpp",
};

// find tools/clang/utils/TableGen | grep '\.cpp$' | xargs -I {} -n1 echo '"{}",' | pbcopy
const clang_tools_clang_utils_tablegen = [_][]const u8{
    "tools/clang/utils/TableGen/ClangASTNodesEmitter.cpp",
    "tools/clang/utils/TableGen/ClangAttrEmitter.cpp",
    "tools/clang/utils/TableGen/ClangCommentCommandInfoEmitter.cpp",
    "tools/clang/utils/TableGen/ClangCommentHTMLNamedCharacterReferenceEmitter.cpp",
    "tools/clang/utils/TableGen/ClangCommentHTMLTagsEmitter.cpp",
    "tools/clang/utils/TableGen/ClangDiagnosticsEmitter.cpp",
    "tools/clang/utils/TableGen/ClangSACheckersEmitter.cpp",
    "tools/clang/utils/TableGen/NeonEmitter.cpp",
    "tools/clang/utils/TableGen/TableGen.cpp",
};

// from lib/Support/CMakeLists.txt
const lib_support_c = [_][]const u8{
    "lib/Support/ConvertUTF.c",
    "lib/Support/regcomp.c",
    "lib/Support/regerror.c",
    "lib/Support/regexec.c",
    "lib/Support/regfree.c",
    "lib/Support/regstrlcpy.c",
};

// from lib/Support/CMakeLists.txt
const lib_support = [_][]const u8{
    "lib/Support/APFloat.cpp",
    "lib/Support/APInt.cpp",
    "lib/Support/APSInt.cpp",
    "lib/Support/ARMBuildAttrs.cpp",
    "lib/Support/ARMWinEH.cpp",
    "lib/Support/Allocator.cpp",
    "lib/Support/BlockFrequency.cpp",
    "lib/Support/BranchProbability.cpp",
    "lib/Support/circular_raw_ostream.cpp",
    "lib/Support/COM.cpp",
    "lib/Support/CommandLine.cpp",
    "lib/Support/Compression.cpp",
    "lib/Support/ConvertUTFWrapper.cpp",
    "lib/Support/CrashRecoveryContext.cpp",
    "lib/Support/DataExtractor.cpp",
    "lib/Support/DataStream.cpp",
    "lib/Support/Debug.cpp",
    "lib/Support/DeltaAlgorithm.cpp",
    "lib/Support/DAGDeltaAlgorithm.cpp",
    "lib/Support/Dwarf.cpp",
    "lib/Support/ErrorHandling.cpp",
    "lib/Support/FileUtilities.cpp",
    "lib/Support/FileOutputBuffer.cpp",
    "lib/Support/FoldingSet.cpp",
    "lib/Support/FormattedStream.cpp",
    "lib/Support/GraphWriter.cpp",
    "lib/Support/Hashing.cpp",
    "lib/Support/IntEqClasses.cpp",
    "lib/Support/IntervalMap.cpp",
    "lib/Support/IntrusiveRefCntPtr.cpp",
    "lib/Support/LEB128.cpp",
    "lib/Support/LineIterator.cpp",
    "lib/Support/Locale.cpp",
    "lib/Support/LockFileManager.cpp",
    "lib/Support/ManagedStatic.cpp",
    "lib/Support/MathExtras.cpp",
    "lib/Support/MemoryBuffer.cpp",
    "lib/Support/MemoryObject.cpp",
    "lib/Support/MSFileSystemBasic.cpp",
    "lib/Support/MD5.cpp",
    "lib/Support/Options.cpp",
    "lib/Support/PrettyStackTrace.cpp",
    "lib/Support/RandomNumberGenerator.cpp",
    "lib/Support/Regex.cpp",
    "lib/Support/ScaledNumber.cpp",
    "lib/Support/SmallPtrSet.cpp",
    "lib/Support/SmallVector.cpp",
    "lib/Support/SourceMgr.cpp",
    "lib/Support/SpecialCaseList.cpp",
    "lib/Support/Statistic.cpp",
    "lib/Support/StreamingMemoryObject.cpp",
    "lib/Support/StringExtras.cpp",
    "lib/Support/StringMap.cpp",
    "lib/Support/StringPool.cpp",
    "lib/Support/StringSaver.cpp",
    "lib/Support/StringRef.cpp",
    "lib/Support/SystemUtils.cpp",
    "lib/Support/TargetParser.cpp",
    "lib/Support/Timer.cpp",
    "lib/Support/ToolOutputFile.cpp",
    "lib/Support/Triple.cpp",
    "lib/Support/Twine.cpp",
    "lib/Support/Unicode.cpp",
    "lib/Support/YAMLParser.cpp",
    "lib/Support/YAMLTraits.cpp",
    "lib/Support/raw_os_ostream.cpp",
    "lib/Support/raw_ostream.cpp",
    "lib/Support/regmalloc.cpp",
    "lib/Support/assert.cpp",
    "lib/Support/Atomic.cpp",
    "lib/Support/Errno.cpp",
    "lib/Support/Host.cpp",
    "lib/Support/Memory.cpp",
    "lib/Support/Mutex.cpp",
    "lib/Support/Path.cpp",
    "lib/Support/Process.cpp",
    "lib/Support/Program.cpp",
    "lib/Support/RWMutex.cpp",
    "lib/Support/SearchForAddressOfSpecialSymbol.cpp",
    "lib/Support/Signals.cpp",
    "lib/Support/TargetRegistry.cpp",
    "lib/Support/ThreadLocal.cpp",
    "lib/Support/Threading.cpp",
    "lib/Support/TimeProfiler.cpp",
    "lib/Support/TimeValue.cpp",
    "lib/Support/Valgrind.cpp",
    "lib/Support/Watchdog.cpp",
};

// From lib/MSSupport/CMakeLists.txt
const lib_mssupport = [_][]const u8{
    "lib/MSSupport/MSFileSystemImpl.cpp",
};
