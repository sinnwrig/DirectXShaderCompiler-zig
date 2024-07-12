const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

// /include/llvm/Config/llvm-config.h.cmake
// /include/llvm/Config/config.h.cmake (derives llvm-config.h.cmake)
pub fn addConfigHeader(b: *Build, target: std.Target, which: anytype) *std.Build.Step.ConfigHeader {
    // Note: LLVM_HOST_TRIPLEs can be found by running $ llc --version | grep Default
    // Note: arm64 is an alias for aarch64, we always use aarch64 over arm64.
    const cross_platform = .{
        .LLVM_PREFIX = "/usr/local",
        .LLVM_DEFAULT_TARGET_TRIPLE = "dxil-ms-dx",
        .LLVM_ENABLE_THREADS = 1,
        .LLVM_HAS_ATOMICS = 1,
        .LLVM_VERSION_MAJOR = 3,
        .LLVM_VERSION_MINOR = 7,
        .LLVM_VERSION_PATCH = 0,
        .PACKAGE_VERSION = "3.7-dxcompiler-zig",
        .LLVM_BINDIR = "",
        .LLVM_CONFIGTIME = "",
        .LLVM_DATADIR = "",
        .LLVM_DOCSDIR = "",
        .LLVM_ETCDIR = "",
        .LLVM_INCLUDEDIR = "",
        .LLVM_INFODIR = "",
        .LLVM_MANDIR = "",
        .LLVM_NATIVE_ARCH = ""
    };  

    const LLVMConfigH = struct {
        LLVM_HOST_TRIPLE: []const u8,
        LLVM_ON_WIN32: ?i64 = null,
        LLVM_ON_UNIX: ?i64 = null,
        HAVE_SYS_MMAN_H: ?i64 = null,
    };
    const llvm_config_h = blk: {
        if (target.os.tag == .windows) {
            break :blk switch (target.abi) {
                .gnu => switch (target.cpu.arch) {
                    .x86_64 => merge(cross_platform, LLVMConfigH{
                        .LLVM_HOST_TRIPLE = "x86_64-w64-mingw32",
                        .LLVM_ON_WIN32 = 1,
                    }),
                    .aarch64 => merge(cross_platform, LLVMConfigH{
                        .LLVM_HOST_TRIPLE = "aarch64-w64-mingw32",
                        .LLVM_ON_WIN32 = 1,
                    }),
                    else => @panic("target architecture not supported"),
                },
                else => @panic("target ABI not supported"),
            };
        } else if (target.os.tag.isDarwin()) {
            break :blk switch (target.cpu.arch) {
                .aarch64 => merge(cross_platform, LLVMConfigH{
                    .LLVM_HOST_TRIPLE = "aarch64-apple-darwin",
                    .LLVM_ON_UNIX = 1,
                    .HAVE_SYS_MMAN_H = 1,
                }),
                .x86_64 => merge(cross_platform, LLVMConfigH{
                    .LLVM_HOST_TRIPLE = "x86_64-apple-darwin",
                    .LLVM_ON_UNIX = 1,
                    .HAVE_SYS_MMAN_H = 1,
                }),
                else => @panic("target architecture not supported"),
            };
        } else {
            // Assume linux-like
            // TODO: musl support?
            break :blk switch (target.cpu.arch) {
                .aarch64 => merge(cross_platform, LLVMConfigH{
                    .LLVM_HOST_TRIPLE = "aarch64-linux-gnu",
                    .LLVM_ON_UNIX = 1,
                    .HAVE_SYS_MMAN_H = 1,
                }),
                .x86_64 => merge(cross_platform, LLVMConfigH{
                    .LLVM_HOST_TRIPLE = "x86_64-linux-gnu",
                    .LLVM_ON_UNIX = 1,
                    .HAVE_SYS_MMAN_H = 1,
                }),
                else => @panic("target architecture not supported"),
            };
        }
    };

    const tag = target.os.tag;
    const if_windows: ?i64 = if (tag == .windows) 1 else null;
    const if_not_windows: ?i64 = if (tag == .windows) null else 1;
    const if_windows_or_linux: ?i64 = if (tag == .windows and !tag.isDarwin()) 1 else null;
    const if_darwin: ?i64 = if (tag.isDarwin()) 1 else null;

    const config_h = merge(llvm_config_h, .{
        .HAVE_STRERROR = if_windows,
        .HAVE_STRERROR_R = if_not_windows,
        .HAVE_MALLOC_H = if_windows_or_linux,
        .HAVE_MALLOC_MALLOC_H = if_darwin,
        .HAVE_MALLOC_ZONE_STATISTICS = if_not_windows,
        .HAVE_GETPAGESIZE = if_not_windows,
        .HAVE_PTHREAD_H = if_not_windows,
        .HAVE_PTHREAD_GETSPECIFIC = if_not_windows,
        .HAVE_PTHREAD_MUTEX_LOCK = if_not_windows,
        .HAVE_PTHREAD_RWLOCK_INIT = if_not_windows,
        .HAVE_DLOPEN = if_not_windows,
        .HAVE_DLFCN_H = if_not_windows, //
        .HAVE_UNISTD_H = 1,

        .BUG_REPORT_URL = "http://llvm.org/bugs/",
        .ENABLE_BACKTRACES = 0,
        .ENABLE_CRASH_OVERRIDES = 0,
        .DISABLE_LLVM_DYLIB_ATEXIT = 0,
        .ENABLE_PIC = 0,
        .ENABLE_TIMESTAMPS = 1,
        .HAVE_CLOSEDIR = 1,
        .HAVE_CXXABI_H = 1,
        .HAVE_DECL_STRERROR_S = 1,
        .HAVE_DIRENT_H = 1,
        .HAVE_ERRNO_H = 1,
        .HAVE_FCNTL_H = 1,
        .HAVE_FENV_H = 1,
        .HAVE_GETCWD = 1,
        .HAVE_GETTIMEOFDAY = 1,
        .HAVE_INT64_T = 1,
        .HAVE_INTTYPES_H = 1,
        .HAVE_ISATTY = 1,
        .HAVE_LIBPSAPI = 1,
        .HAVE_LIBSHELL32 = 1,
        .HAVE_LIMITS_H = 1,
        .HAVE_LINK_EXPORT_DYNAMIC = 1,
        .HAVE_MKSTEMP = 1,
        .HAVE_MKTEMP = 1,
        .HAVE_OPENDIR = 1,
        .HAVE_READDIR = 1,
        .HAVE_SIGNAL_H = 1,
        .HAVE_STDINT_H = 1,
        .HAVE_STRTOLL = 1,
        .HAVE_SYS_PARAM_H = 1,
        .HAVE_SYS_STAT_H = 1,
        .HAVE_SYS_TIME_H = 1,
        .HAVE_UINT64_T = 1,
        .HAVE_UTIME_H = 1,
        .HAVE__ALLOCA = 1,
        .HAVE___ASHLDI3 = 1,
        .HAVE___ASHRDI3 = 1,
        .HAVE___CMPDI2 = 1,
        .HAVE___DIVDI3 = 1,
        .HAVE___FIXDFDI = 1,
        .HAVE___FIXSFDI = 1,
        .HAVE___FLOATDIDF = 1,
        .HAVE___LSHRDI3 = 1,
        .HAVE___MAIN = 1,
        .HAVE___MODDI3 = 1,
        .HAVE___UDIVDI3 = 1,
        .HAVE___UMODDI3 = 1,
        .HAVE____CHKSTK_MS = 1,
        .LLVM_ENABLE_ZLIB = 0,
        .PACKAGE_BUGREPORT = "http://llvm.org/bugs/",
        .PACKAGE_NAME = "LLVM",
        .PACKAGE_STRING = "LLVM 3.7-v1.4.0.2274-1812-g84da60c6c-dirty",
        .RETSIGTYPE = "void",
        .WIN32_ELMCB_PCSTR = "PCSTR",
        .HAVE__CHSIZE_S = 1,

        .HAVE_DECL_ARC4RANDOM = 0,
        .HAVE_BACKTRACE = 0,
        .HAVE_DIA_SDK = 0,
        .HAVE_DLERROR = 0,
        .HAVE_EXECINFO_H = 0,
        .HAVE_FFI_CALL = 0,
        .HAVE_FFI_FFI_H = 0,
        .HAVE_FFI_H = 0,
        .HAVE_FUTIMES = 0,
        .HAVE_FUTIMENS = 0,
        .HAVE_GETRLIMIT = 0,
        .HAVE_GETRUSAGE = 0,
        .HAVE_LIBDL = 0,
        .HAVE_LIBPTHREAD = 0,
        .HAVE_LIBZ = 0,
        .HAVE_LIBEDIT = 0,
        .HAVE_LINK_H = 0,
        .HAVE_LONGJMP = 0,
        .HAVE_MACH_MACH_H = 0,
        .HAVE_MACH_O_DYLD_H = 0,
        .HAVE_MALLINFO = 0,
        .HAVE_MALLINFO2 = 0,
        .HAVE_MALLCTL = 0,
        .HAVE_MKDTEMP = 0,
        .HAVE_NDIR_H = 0,
        .HAVE_POSIX_SPAWN = 0,
        .HAVE_PREAD = 0,
        .HAVE_RAND48 = 0,
        .HAVE_REALPATH = 0,
        .HAVE_SBRK = 0,
        .HAVE_SETENV = 0,
        .HAVE_SETJMP = 0,
        .HAVE_SETRLIMIT = 0,
        .HAVE_SIGLONGJMP = 0,
        .HAVE_SIGSETJMP = 0,
        .HAVE_SYS_DIR_H = 0,
        .HAVE_STRDUP = 0,
        .HAVE_STRTOQ = 0,
        .HAVE_SYS_IOCTL_H = 0,
        .HAVE_SYS_NDIR_H = 0,
        .HAVE_SYS_RESOURCE_H = 0,
        .HAVE_SYS_TYPES_H = 0,
        .HAVE_SYS_UIO_H = 0,
        .HAVE_SYS_WAIT_H = 0,
        .HAVE_TERMINFO = 0,
        .HAVE_TERMIOS_H = 0,
        .HAVE_U_INT64_T = 0,
        .HAVE_VALGRIND_VALGRIND_H = 0,
        .HAVE_WRITEV = 0,
        .HAVE_ZLIB_H = 0,
        .HAVE___ALLOCA = 0,
        .HAVE___CHKSTK = 0,
        .HAVE___CHKSTK_MS = 0,
        .HAVE____CHKSTK = 0,
        .LTDL_DLOPEN_DEPLIBS = 0,
        .LTDL_SHLIB_EXT = "",
        .LTDL_SYSSEARCHPATH = "",
        .strtoll = "",
        .strtoull = "",
        .stricmp = "",
        .strdup = "",
    });

    return switch (which) {
        .llvm_config_h => b.addConfigHeader(.{
            .style = .{ .cmake = b.path("include/llvm/Config/llvm-config.h.cmake") },
            .include_path = "llvm/Config/llvm-config.h",
        }, llvm_config_h),
        .config_h => b.addConfigHeader(.{
            .style = .{ .cmake = b.path("include/llvm/Config/config.h.cmake") },
            .include_path = "llvm/Config/config.h",
        }, config_h),
        else => unreachable,
    };
}

// Merge struct types A and B
fn Merge(comptime a: type, comptime b: type) type {
    const a_fields = @typeInfo(a).Struct.fields;
    const b_fields = @typeInfo(b).Struct.fields;

    return @Type(std.builtin.Type{
        .Struct = .{
            .layout = .auto,
            .fields = a_fields ++ b_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

// Merge struct values A and B
fn merge(a: anytype, b: anytype) Merge(@TypeOf(a), @TypeOf(b)) {
    var merged: Merge(@TypeOf(a), @TypeOf(b)) = undefined;
    inline for (@typeInfo(@TypeOf(merged)).Struct.fields) |f| {
        if (@hasField(@TypeOf(a), f.name)) @field(merged, f.name) = @field(a, f.name);
        if (@hasField(@TypeOf(b), f.name)) @field(merged, f.name) = @field(b, f.name);
    }
    return merged;
}