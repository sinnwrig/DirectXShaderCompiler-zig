// Licensed under the Mach license (MIT or Apache at your choosing)
// See https://github.com/hexops/mach/blob/main/LICENSE
// This file is also a derivitive of WinIncludes.h and WinAdapter.h, and therefor also under their
// licenses.
//
// This is a mix of WinIncludes.h and WinAdapter.h but tailored to support the zig/clang GNU ABI
// target and MinGW Windows headers.

#ifndef LLVM_SUPPORT_ZIG_GNU_WIN_ADAPTER_H
#define LLVM_SUPPORT_ZIG_GNU_WIN_ADAPTER_H

#if defined(__clang__) && !defined(_MSC_VER) && defined(_WIN32) // Zig windows-gnu target

// MinGW UUIDOF specializations
//-------------------------------------------------------------
// This is needed because clang GNU target / MinGW headers will emit references to e.g.
//
// error: undefined symbol: _GUID const& __mingw_uuidof<IDxcSystemAccess>()
//
// which do not match MSVC.
#include <guiddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define MINGW_UUIDOF(type, spec)                                              \
    extern "C++" {                                                            \
    struct __declspec(uuid(spec)) type;                                       \
    template<> const GUID &__mingw_uuidof<type>() {                           \
        static constexpr IID __uuid_inst = guid_from_string(spec);            \
        return __uuid_inst;                                                   \
    }                                                                         \
    template<> const GUID &__mingw_uuidof<type*>() {                          \
        return __mingw_uuidof<type>();                                        \
    }                                                                         \
    }

constexpr uint8_t nybble_from_hex(char c) {
  return ((c >= '0' && c <= '9')
              ? (c - '0')
              : ((c >= 'a' && c <= 'f')
                     ? (c - 'a' + 10)
                     : ((c >= 'A' && c <= 'F') ? (c - 'A' + 10)
                                               : /* Should be an error */ -1)));
}

constexpr uint8_t byte_from_hex(char c1, char c2) {
  return nybble_from_hex(c1) << 4 | nybble_from_hex(c2);
}

constexpr uint8_t byte_from_hexstr(const char str[2]) {
  return nybble_from_hex(str[0]) << 4 | nybble_from_hex(str[1]);
}

constexpr GUID guid_from_string(const char str[37]) {
  return GUID{static_cast<uint32_t>(byte_from_hexstr(str)) << 24 |
                  static_cast<uint32_t>(byte_from_hexstr(str + 2)) << 16 |
                  static_cast<uint32_t>(byte_from_hexstr(str + 4)) << 8 |
                  byte_from_hexstr(str + 6),
              static_cast<uint16_t>(
                  static_cast<uint16_t>(byte_from_hexstr(str + 9)) << 8 |
                  byte_from_hexstr(str + 11)),
              static_cast<uint16_t>(
                  static_cast<uint16_t>(byte_from_hexstr(str + 14)) << 8 |
                  byte_from_hexstr(str + 16)),
              {byte_from_hexstr(str + 19), byte_from_hexstr(str + 21),
               byte_from_hexstr(str + 24), byte_from_hexstr(str + 26),
               byte_from_hexstr(str + 28), byte_from_hexstr(str + 30),
               byte_from_hexstr(str + 32), byte_from_hexstr(str + 34)}};
}

#ifdef ZIG_MINGW_DECLARE_SPECIALIZATIONS
#define CROSS_PLATFORM_UUIDOF(type, spec) MINGW_UUIDOF(type, spec)
#else // ZIG_MINGW_DECLARE_SPECIALIZATIONS
#define CROSS_PLATFORM_UUIDOF(type, spec)
#endif // ZIG_MINGW_DECLARE_SPECIALIZATIONS
#endif // __cplusplus



// General
//-------------------------------------------------------------
// mingw-w64 tends to define it as 0x0502 in its headers.
#undef _WIN32_WINNT
#undef _WIN32_IE

// Require at least Windows 7 (Updated from XP)
#define _WIN32_WINNT 0x0601
#define _WIN32_IE 0x0800 // MinGW at it again.

#define NOATOM 1
#define NOGDICAPMASKS 1
#define NOMETAFILE 1
#define NOOPENFILE 1
#define NORASTEROPS 1
#define NOSCROLL 1
#define NOSOUND 1
#define NOSYSMETRICS 1
#define NOWH 1
#define NOCOMM 1
#define NOKANJI 1
#define NOCRYPT 1
#define NOMCX 1
#define WIN32_LEAN_AND_MEAN 1
#define VC_EXTRALEAN 1
#define NONAMELESSSTRUCT 1

// Map these errors to equivalent errnos.
#define ERROR_NOT_CAPABLE EPERM
#define ERROR_UNHANDLED_EXCEPTION EBADF

#define STRSAFE_NO_DEPRECATE
#include <strsafe.h>
#include <intsafe.h>
#include <unknwn.h>
#undef MemoryFence
#undef IN
#undef OUT
#undef interface

// winnt.h conflicts with Coff.h, this is just a big #undef list.
//-------------------------------------------------------------
#undef IMAGE_DOS_SIGNATURE
#undef IMAGE_OS2_SIGNATURE
#undef IMAGE_OS2_SIGNATURE_LE
#undef IMAGE_VXD_SIGNATURE
#undef IMAGE_NT_SIGNATURE
#undef IMAGE_SIZEOF_FILE_HEADER
#undef IMAGE_FILE_RELOCS_STRIPPED
#undef IMAGE_FILE_EXECUTABLE_IMAGE
#undef IMAGE_FILE_LINE_NUMS_STRIPPED
#undef IMAGE_FILE_LOCAL_SYMS_STRIPPED
#undef IMAGE_FILE_AGGRESIVE_WS_TRIM
#undef IMAGE_FILE_LARGE_ADDRESS_AWARE
#undef IMAGE_FILE_BYTES_REVERSED_LO
#undef IMAGE_FILE_32BIT_MACHINE
#undef IMAGE_FILE_DEBUG_STRIPPED
#undef IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP
#undef IMAGE_FILE_NET_RUN_FROM_SWAP
#undef IMAGE_FILE_SYSTEM
#undef IMAGE_FILE_DLL
#undef IMAGE_FILE_UP_SYSTEM_ONLY
#undef IMAGE_FILE_BYTES_REVERSED_HI
#undef IMAGE_FILE_MACHINE_UNKNOWN
#undef IMAGE_FILE_MACHINE_I386
#undef IMAGE_FILE_MACHINE_R3000
#undef IMAGE_FILE_MACHINE_R4000
#undef IMAGE_FILE_MACHINE_R10000
#undef IMAGE_FILE_MACHINE_WCEMIPSV2
#undef IMAGE_FILE_MACHINE_ALPHA
#undef IMAGE_FILE_MACHINE_SH3
#undef IMAGE_FILE_MACHINE_SH3DSP
#undef IMAGE_FILE_MACHINE_SH3E
#undef IMAGE_FILE_MACHINE_SH4
#undef IMAGE_FILE_MACHINE_SH5
#undef IMAGE_FILE_MACHINE_ARM
#undef IMAGE_FILE_MACHINE_ARMV7
#undef IMAGE_FILE_MACHINE_ARMNT
#undef IMAGE_FILE_MACHINE_ARM64
#undef IMAGE_FILE_MACHINE_THUMB
#undef IMAGE_FILE_MACHINE_AM33
#undef IMAGE_FILE_MACHINE_POWERPC
#undef IMAGE_FILE_MACHINE_POWERPCFP
#undef IMAGE_FILE_MACHINE_IA64
#undef IMAGE_FILE_MACHINE_MIPS16
#undef IMAGE_FILE_MACHINE_ALPHA64
#undef IMAGE_FILE_MACHINE_MIPSFPU
#undef IMAGE_FILE_MACHINE_MIPSFPU16
#undef IMAGE_FILE_MACHINE_AXP64
#undef IMAGE_FILE_MACHINE_TRICORE
#undef IMAGE_FILE_MACHINE_CEF
#undef IMAGE_FILE_MACHINE_EBC
#undef IMAGE_FILE_MACHINE_AMD64
#undef IMAGE_FILE_MACHINE_M32R
#undef IMAGE_FILE_MACHINE_CEE
#undef IMAGE_NUMBEROF_DIRECTORY_ENTRIES
#undef IMAGE_SIZEOF_ROM_OPTIONAL_HEADER
#undef IMAGE_SIZEOF_STD_OPTIONAL_HEADER
#undef IMAGE_SIZEOF_NT_OPTIONAL32_HEADER
#undef IMAGE_SIZEOF_NT_OPTIONAL64_HEADER
#undef IMAGE_NT_OPTIONAL_HDR32_MAGIC
#undef IMAGE_NT_OPTIONAL_HDR64_MAGIC
#undef IMAGE_ROM_OPTIONAL_HDR_MAGIC
#undef IMAGE_SIZEOF_NT_OPTIONAL_HEADER
#undef IMAGE_NT_OPTIONAL_HDR_MAGIC
#undef IMAGE_SIZEOF_NT_OPTIONAL_HEADER
#undef IMAGE_NT_OPTIONAL_HDR_MAGIC
#undef IMAGE_FIRST_SECTION
#undef IMAGE_SUBSYSTEM_UNKNOWN
#undef IMAGE_SUBSYSTEM_NATIVE
#undef IMAGE_SUBSYSTEM_WINDOWS_GUI
#undef IMAGE_SUBSYSTEM_WINDOWS_CUI
#undef IMAGE_SUBSYSTEM_OS2_CUI
#undef IMAGE_SUBSYSTEM_POSIX_CUI
#undef IMAGE_SUBSYSTEM_NATIVE_WINDOWS
#undef IMAGE_SUBSYSTEM_WINDOWS_CE_GUI
#undef IMAGE_SUBSYSTEM_EFI_APPLICATION
#undef IMAGE_SUBSYSTEM_EFI_BOOT_SERVICE_DRIVER
#undef IMAGE_SUBSYSTEM_EFI_RUNTIME_DRIVER
#undef IMAGE_SUBSYSTEM_EFI_ROM
#undef IMAGE_SUBSYSTEM_XBOX
#undef IMAGE_SUBSYSTEM_WINDOWS_BOOT_APPLICATION
#undef IMAGE_DLLCHARACTERISTICS_HIGH_ENTROPY_VA
#undef IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE
#undef IMAGE_DLLCHARACTERISTICS_FORCE_INTEGRITY
#undef IMAGE_DLLCHARACTERISTICS_NX_COMPAT
#undef IMAGE_DLLCHARACTERISTICS_NO_ISOLATION
#undef IMAGE_DLLCHARACTERISTICS_NO_SEH
#undef IMAGE_DLLCHARACTERISTICS_NO_BIND
#undef IMAGE_DLLCHARACTERISTICS_APPCONTAINER
#undef IMAGE_DLLCHARACTERISTICS_WDM_DRIVER
#undef IMAGE_DLLCHARACTERISTICS_GUARD_CF
#undef IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE
#undef IMAGE_DIRECTORY_ENTRY_EXPORT
#undef IMAGE_DIRECTORY_ENTRY_IMPORT
#undef IMAGE_DIRECTORY_ENTRY_RESOURCE
#undef IMAGE_DIRECTORY_ENTRY_EXCEPTION
#undef IMAGE_DIRECTORY_ENTRY_SECURITY
#undef IMAGE_DIRECTORY_ENTRY_BASERELOC
#undef IMAGE_DIRECTORY_ENTRY_DEBUG
#undef IMAGE_DIRECTORY_ENTRY_ARCHITECTURE
#undef IMAGE_DIRECTORY_ENTRY_GLOBALPTR
#undef IMAGE_DIRECTORY_ENTRY_TLS
#undef IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG
#undef IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT
#undef IMAGE_DIRECTORY_ENTRY_IAT
#undef IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT
#undef IMAGE_DIRECTORY_ENTRY_COM_DESCRIPTOR
#undef IMAGE_SIZEOF_SHORT_NAME
#undef IMAGE_SIZEOF_SECTION_HEADER
#undef IMAGE_SCN_TYPE_NO_PAD
#undef IMAGE_SCN_CNT_CODE
#undef IMAGE_SCN_CNT_INITIALIZED_DATA
#undef IMAGE_SCN_CNT_UNINITIALIZED_DATA
#undef IMAGE_SCN_LNK_OTHER
#undef IMAGE_SCN_LNK_INFO
#undef IMAGE_SCN_LNK_REMOVE
#undef IMAGE_SCN_LNK_COMDAT
#undef IMAGE_SCN_NO_DEFER_SPEC_EXC
#undef IMAGE_SCN_GPREL
#undef IMAGE_SCN_MEM_FARDATA
#undef IMAGE_SCN_MEM_PURGEABLE
#undef IMAGE_SCN_MEM_16BIT
#undef IMAGE_SCN_MEM_LOCKED
#undef IMAGE_SCN_MEM_PRELOAD
#undef IMAGE_SCN_ALIGN_1BYTES
#undef IMAGE_SCN_ALIGN_2BYTES
#undef IMAGE_SCN_ALIGN_4BYTES
#undef IMAGE_SCN_ALIGN_8BYTES
#undef IMAGE_SCN_ALIGN_16BYTES
#undef IMAGE_SCN_ALIGN_32BYTES
#undef IMAGE_SCN_ALIGN_64BYTES
#undef IMAGE_SCN_ALIGN_128BYTES
#undef IMAGE_SCN_ALIGN_256BYTES
#undef IMAGE_SCN_ALIGN_512BYTES
#undef IMAGE_SCN_ALIGN_1024BYTES
#undef IMAGE_SCN_ALIGN_2048BYTES
#undef IMAGE_SCN_ALIGN_4096BYTES
#undef IMAGE_SCN_ALIGN_8192BYTES
#undef IMAGE_SCN_ALIGN_MASK
#undef IMAGE_SCN_LNK_NRELOC_OVFL
#undef IMAGE_SCN_MEM_DISCARDABLE
#undef IMAGE_SCN_MEM_NOT_CACHED
#undef IMAGE_SCN_MEM_NOT_PAGED
#undef IMAGE_SCN_MEM_SHARED
#undef IMAGE_SCN_MEM_EXECUTE
#undef IMAGE_SCN_MEM_READ
#undef IMAGE_SCN_MEM_WRITE
#undef IMAGE_SCN_SCALE_INDEX
#undef IMAGE_SIZEOF_SYMBOL
#undef IMAGE_SYM_UNDEFINED
#undef IMAGE_SYM_ABSOLUTE
#undef IMAGE_SYM_DEBUG
#undef IMAGE_SYM_SECTION_MAX
#undef IMAGE_SYM_SECTION_MAX_EX
#undef IMAGE_SYM_TYPE_NULL
#undef IMAGE_SYM_TYPE_VOID
#undef IMAGE_SYM_TYPE_CHAR
#undef IMAGE_SYM_TYPE_SHORT
#undef IMAGE_SYM_TYPE_INT
#undef IMAGE_SYM_TYPE_LONG
#undef IMAGE_SYM_TYPE_FLOAT
#undef IMAGE_SYM_TYPE_DOUBLE
#undef IMAGE_SYM_TYPE_STRUCT
#undef IMAGE_SYM_TYPE_UNION
#undef IMAGE_SYM_TYPE_ENUM
#undef IMAGE_SYM_TYPE_MOE
#undef IMAGE_SYM_TYPE_BYTE
#undef IMAGE_SYM_TYPE_WORD
#undef IMAGE_SYM_TYPE_UINT
#undef IMAGE_SYM_TYPE_DWORD
#undef IMAGE_SYM_TYPE_PCODE
#undef IMAGE_SYM_DTYPE_NULL
#undef IMAGE_SYM_DTYPE_POINTER
#undef IMAGE_SYM_DTYPE_FUNCTION
#undef IMAGE_SYM_DTYPE_ARRAY
#undef IMAGE_SYM_CLASS_END_OF_FUNCTION
#undef IMAGE_SYM_CLASS_NULL
#undef IMAGE_SYM_CLASS_AUTOMATIC
#undef IMAGE_SYM_CLASS_EXTERNAL
#undef IMAGE_SYM_CLASS_STATIC
#undef IMAGE_SYM_CLASS_REGISTER
#undef IMAGE_SYM_CLASS_EXTERNAL_DEF
#undef IMAGE_SYM_CLASS_LABEL
#undef IMAGE_SYM_CLASS_UNDEFINED_LABEL
#undef IMAGE_SYM_CLASS_MEMBER_OF_STRUCT
#undef IMAGE_SYM_CLASS_ARGUMENT
#undef IMAGE_SYM_CLASS_STRUCT_TAG
#undef IMAGE_SYM_CLASS_MEMBER_OF_UNION
#undef IMAGE_SYM_CLASS_UNION_TAG
#undef IMAGE_SYM_CLASS_TYPE_DEFINITION
#undef IMAGE_SYM_CLASS_UNDEFINED_STATIC
#undef IMAGE_SYM_CLASS_ENUM_TAG
#undef IMAGE_SYM_CLASS_MEMBER_OF_ENUM
#undef IMAGE_SYM_CLASS_REGISTER_PARAM
#undef IMAGE_SYM_CLASS_BIT_FIELD
#undef IMAGE_SYM_CLASS_FAR_EXTERNAL
#undef IMAGE_SYM_CLASS_BLOCK
#undef IMAGE_SYM_CLASS_FUNCTION
#undef IMAGE_SYM_CLASS_END_OF_STRUCT
#undef IMAGE_SYM_CLASS_FILE
#undef IMAGE_SYM_CLASS_SECTION
#undef IMAGE_SYM_CLASS_WEAK_EXTERNAL
#undef IMAGE_SYM_CLASS_CLR_TOKEN
#undef IMAGE_SIZEOF_AUX_SYMBOL
#undef IMAGE_COMDAT_SELECT_NODUPLICATES
#undef IMAGE_COMDAT_SELECT_ANY
#undef IMAGE_COMDAT_SELECT_SAME_SIZE
#undef IMAGE_COMDAT_SELECT_EXACT_MATCH
#undef IMAGE_COMDAT_SELECT_ASSOCIATIVE
#undef IMAGE_COMDAT_SELECT_LARGEST
#undef IMAGE_COMDAT_SELECT_NEWEST
#undef IMAGE_WEAK_EXTERN_SEARCH_NOLIBRARY
#undef IMAGE_WEAK_EXTERN_SEARCH_LIBRARY
#undef IMAGE_WEAK_EXTERN_SEARCH_ALIAS
#undef IMAGE_SIZEOF_RELOCATION
#undef IMAGE_REL_I386_ABSOLUTE
#undef IMAGE_REL_I386_DIR16
#undef IMAGE_REL_I386_REL16
#undef IMAGE_REL_I386_DIR32
#undef IMAGE_REL_I386_DIR32NB
#undef IMAGE_REL_I386_SEG12
#undef IMAGE_REL_I386_SECTION
#undef IMAGE_REL_I386_SECREL
#undef IMAGE_REL_I386_TOKEN
#undef IMAGE_REL_I386_SECREL7
#undef IMAGE_REL_I386_REL32
#undef IMAGE_REL_MIPS_ABSOLUTE
#undef IMAGE_REL_MIPS_REFHALF
#undef IMAGE_REL_MIPS_REFWORD
#undef IMAGE_REL_MIPS_JMPADDR
#undef IMAGE_REL_MIPS_REFHI
#undef IMAGE_REL_MIPS_REFLO
#undef IMAGE_REL_MIPS_GPREL
#undef IMAGE_REL_MIPS_LITERAL
#undef IMAGE_REL_MIPS_SECTION
#undef IMAGE_REL_MIPS_SECREL
#undef IMAGE_REL_MIPS_SECRELLO
#undef IMAGE_REL_MIPS_SECRELHI
#undef IMAGE_REL_MIPS_TOKEN
#undef IMAGE_REL_MIPS_JMPADDR16
#undef IMAGE_REL_MIPS_REFWORDNB
#undef IMAGE_REL_MIPS_PAIR
#undef IMAGE_REL_ALPHA_ABSOLUTE
#undef IMAGE_REL_ALPHA_REFLONG
#undef IMAGE_REL_ALPHA_REFQUAD
#undef IMAGE_REL_ALPHA_GPREL32
#undef IMAGE_REL_ALPHA_LITERAL
#undef IMAGE_REL_ALPHA_LITUSE
#undef IMAGE_REL_ALPHA_GPDISP
#undef IMAGE_REL_ALPHA_BRADDR
#undef IMAGE_REL_ALPHA_HINT
#undef IMAGE_REL_ALPHA_INLINE_REFLONG
#undef IMAGE_REL_ALPHA_REFHI
#undef IMAGE_REL_ALPHA_REFLO
#undef IMAGE_REL_ALPHA_PAIR
#undef IMAGE_REL_ALPHA_MATCH
#undef IMAGE_REL_ALPHA_SECTION
#undef IMAGE_REL_ALPHA_SECREL
#undef IMAGE_REL_ALPHA_REFLONGNB
#undef IMAGE_REL_ALPHA_SECRELLO
#undef IMAGE_REL_ALPHA_SECRELHI
#undef IMAGE_REL_ALPHA_REFQ3
#undef IMAGE_REL_ALPHA_REFQ2
#undef IMAGE_REL_ALPHA_REFQ1
#undef IMAGE_REL_ALPHA_GPRELLO
#undef IMAGE_REL_ALPHA_GPRELHI
#undef IMAGE_REL_PPC_ABSOLUTE
#undef IMAGE_REL_PPC_ADDR64
#undef IMAGE_REL_PPC_ADDR32
#undef IMAGE_REL_PPC_ADDR24
#undef IMAGE_REL_PPC_ADDR16
#undef IMAGE_REL_PPC_ADDR14
#undef IMAGE_REL_PPC_REL24
#undef IMAGE_REL_PPC_REL14
#undef IMAGE_REL_PPC_TOCREL16
#undef IMAGE_REL_PPC_TOCREL14
#undef IMAGE_REL_PPC_ADDR32NB
#undef IMAGE_REL_PPC_SECREL
#undef IMAGE_REL_PPC_SECTION
#undef IMAGE_REL_PPC_IFGLUE
#undef IMAGE_REL_PPC_IMGLUE
#undef IMAGE_REL_PPC_SECREL16
#undef IMAGE_REL_PPC_REFHI
#undef IMAGE_REL_PPC_REFLO
#undef IMAGE_REL_PPC_PAIR
#undef IMAGE_REL_PPC_SECRELLO
#undef IMAGE_REL_PPC_SECRELHI
#undef IMAGE_REL_PPC_GPREL
#undef IMAGE_REL_PPC_TOKEN
#undef IMAGE_REL_PPC_TYPEMASK
#undef IMAGE_REL_PPC_NEG
#undef IMAGE_REL_PPC_BRTAKEN
#undef IMAGE_REL_PPC_BRNTAKEN
#undef IMAGE_REL_PPC_TOCDEFN
#undef IMAGE_REL_SH3_ABSOLUTE
#undef IMAGE_REL_SH3_DIRECT16
#undef IMAGE_REL_SH3_DIRECT32
#undef IMAGE_REL_SH3_DIRECT8
#undef IMAGE_REL_SH3_DIRECT8_WORD
#undef IMAGE_REL_SH3_DIRECT8_LONG
#undef IMAGE_REL_SH3_DIRECT4
#undef IMAGE_REL_SH3_DIRECT4_WORD
#undef IMAGE_REL_SH3_DIRECT4_LONG
#undef IMAGE_REL_SH3_PCREL8_WORD
#undef IMAGE_REL_SH3_PCREL8_LONG
#undef IMAGE_REL_SH3_PCREL12_WORD
#undef IMAGE_REL_SH3_STARTOF_SECTION
#undef IMAGE_REL_SH3_SIZEOF_SECTION
#undef IMAGE_REL_SH3_SECTION
#undef IMAGE_REL_SH3_SECREL
#undef IMAGE_REL_SH3_DIRECT32_NB
#undef IMAGE_REL_SH3_GPREL4_LONG
#undef IMAGE_REL_SH3_TOKEN
#undef IMAGE_REL_SHM_PCRELPT
#undef IMAGE_REL_SHM_REFLO
#undef IMAGE_REL_SHM_REFHALF
#undef IMAGE_REL_SHM_RELLO
#undef IMAGE_REL_SHM_RELHALF
#undef IMAGE_REL_SHM_PAIR
#undef IMAGE_REL_SH_NOMODE
#undef IMAGE_REL_ARM_ABSOLUTE
#undef IMAGE_REL_ARM_ADDR32
#undef IMAGE_REL_ARM_ADDR32NB
#undef IMAGE_REL_ARM_BRANCH24
#undef IMAGE_REL_ARM_BRANCH11
#undef IMAGE_REL_ARM_TOKEN
#undef IMAGE_REL_ARM_GPREL12
#undef IMAGE_REL_ARM_GPREL7
#undef IMAGE_REL_ARM_BLX24
#undef IMAGE_REL_ARM_BLX11
#undef IMAGE_REL_ARM_SECTION
#undef IMAGE_REL_ARM_SECREL
#undef IMAGE_REL_ARM_MOV32A
#undef IMAGE_REL_ARM_MOV32
#undef IMAGE_REL_ARM_MOV32T
#undef IMAGE_REL_THUMB_MOV32
#undef IMAGE_REL_ARM_BRANCH20T
#undef IMAGE_REL_THUMB_BRANCH20
#undef IMAGE_REL_ARM_BRANCH24T
#undef IMAGE_REL_THUMB_BRANCH24
#undef IMAGE_REL_ARM_BLX23T
#undef IMAGE_REL_THUMB_BLX23
#undef IMAGE_REL_AM_ABSOLUTE
#undef IMAGE_REL_AM_ADDR32
#undef IMAGE_REL_AM_ADDR32NB
#undef IMAGE_REL_AM_CALL32
#undef IMAGE_REL_AM_FUNCINFO
#undef IMAGE_REL_AM_REL32_1
#undef IMAGE_REL_AM_REL32_2
#undef IMAGE_REL_AM_SECREL
#undef IMAGE_REL_AM_SECTION
#undef IMAGE_REL_AM_TOKEN
#undef IMAGE_REL_AMD64_ABSOLUTE
#undef IMAGE_REL_AMD64_ADDR64
#undef IMAGE_REL_AMD64_ADDR32
#undef IMAGE_REL_AMD64_ADDR32NB
#undef IMAGE_REL_AMD64_REL32
#undef IMAGE_REL_AMD64_REL32_1
#undef IMAGE_REL_AMD64_REL32_2
#undef IMAGE_REL_AMD64_REL32_3
#undef IMAGE_REL_AMD64_REL32_4
#undef IMAGE_REL_AMD64_REL32_5
#undef IMAGE_REL_AMD64_SECTION
#undef IMAGE_REL_AMD64_SECREL
#undef IMAGE_REL_AMD64_SECREL7
#undef IMAGE_REL_AMD64_TOKEN
#undef IMAGE_REL_AMD64_SREL32
#undef IMAGE_REL_AMD64_PAIR
#undef IMAGE_REL_AMD64_SSPAN32
#undef IMAGE_REL_IA64_ABSOLUTE
#undef IMAGE_REL_IA64_IMM14
#undef IMAGE_REL_IA64_IMM22
#undef IMAGE_REL_IA64_IMM64
#undef IMAGE_REL_IA64_DIR32
#undef IMAGE_REL_IA64_DIR64
#undef IMAGE_REL_IA64_PCREL21B
#undef IMAGE_REL_IA64_PCREL21M
#undef IMAGE_REL_IA64_PCREL21F
#undef IMAGE_REL_IA64_GPREL22
#undef IMAGE_REL_IA64_LTOFF22
#undef IMAGE_REL_IA64_SECTION
#undef IMAGE_REL_IA64_SECREL22
#undef IMAGE_REL_IA64_SECREL64I
#undef IMAGE_REL_IA64_SECREL32
#undef IMAGE_REL_IA64_DIR32NB
#undef IMAGE_REL_IA64_SREL14
#undef IMAGE_REL_IA64_SREL22
#undef IMAGE_REL_IA64_SREL32
#undef IMAGE_REL_IA64_UREL32
#undef IMAGE_REL_IA64_PCREL60X
#undef IMAGE_REL_IA64_PCREL60B
#undef IMAGE_REL_IA64_PCREL60F
#undef IMAGE_REL_IA64_PCREL60I
#undef IMAGE_REL_IA64_PCREL60M
#undef IMAGE_REL_IA64_IMMGPREL64
#undef IMAGE_REL_IA64_TOKEN
#undef IMAGE_REL_IA64_GPREL32
#undef IMAGE_REL_IA64_ADDEND
#undef IMAGE_REL_CEF_ABSOLUTE
#undef IMAGE_REL_CEF_ADDR32
#undef IMAGE_REL_CEF_ADDR64
#undef IMAGE_REL_CEF_ADDR32NB
#undef IMAGE_REL_CEF_SECTION
#undef IMAGE_REL_CEF_SECREL
#undef IMAGE_REL_CEF_TOKEN
#undef IMAGE_REL_CEE_ABSOLUTE
#undef IMAGE_REL_CEE_ADDR32
#undef IMAGE_REL_CEE_ADDR64
#undef IMAGE_REL_CEE_ADDR32NB
#undef IMAGE_REL_CEE_SECTION
#undef IMAGE_REL_CEE_SECREL
#undef IMAGE_REL_CEE_TOKEN
#undef IMAGE_REL_M32R_ABSOLUTE
#undef IMAGE_REL_M32R_ADDR32
#undef IMAGE_REL_M32R_ADDR32NB
#undef IMAGE_REL_M32R_ADDR24
#undef IMAGE_REL_M32R_GPREL16
#undef IMAGE_REL_M32R_PCREL24
#undef IMAGE_REL_M32R_PCREL16
#undef IMAGE_REL_M32R_PCREL8
#undef IMAGE_REL_M32R_REFHALF
#undef IMAGE_REL_M32R_REFHI
#undef IMAGE_REL_M32R_REFLO
#undef IMAGE_REL_M32R_PAIR
#undef IMAGE_REL_M32R_SECTION
#undef IMAGE_REL_M32R_SECREL32
#undef IMAGE_REL_M32R_TOKEN
#undef IMAGE_REL_EBC_ABSOLUTE
#undef IMAGE_REL_EBC_ADDR32NB
#undef IMAGE_REL_EBC_REL32
#undef IMAGE_REL_EBC_SECTION
#undef IMAGE_REL_EBC_SECREL
#undef IMAGE_SIZEOF_BASE_RELOCATION
#undef IMAGE_REL_BASED_ABSOLUTE
#undef IMAGE_REL_BASED_HIGH
#undef IMAGE_REL_BASED_LOW
#undef IMAGE_REL_BASED_HIGHLOW
#undef IMAGE_REL_BASED_HIGHADJ
#undef IMAGE_REL_BASED_MIPS_JMPADDR
#undef IMAGE_REL_BASED_ARM_MOV32
#undef IMAGE_REL_BASED_THUMB_MOV32
#undef IMAGE_REL_BASED_MIPS_JMPADDR16
#undef IMAGE_REL_BASED_IA64_IMM64
#undef IMAGE_REL_BASED_DIR64
#undef IMAGE_ARCHIVE_START_SIZE
#undef IMAGE_ARCHIVE_START
#undef IMAGE_ARCHIVE_END
#undef IMAGE_ARCHIVE_PAD
#undef IMAGE_ARCHIVE_LINKER_MEMBER
#undef IMAGE_ARCHIVE_LONGNAMES_MEMBER
#undef IMAGE_SIZEOF_ARCHIVE_MEMBER_HDR
#undef IMAGE_ORDINAL_FLAG64
#undef IMAGE_ORDINAL_FLAG32
#undef IMAGE_ORDINAL64
#undef IMAGE_ORDINAL32
#undef IMAGE_SNAP_BY_ORDINAL64
#undef IMAGE_SNAP_BY_ORDINAL32
#undef IMAGE_ORDINAL_FLAG
#undef IMAGE_ORDINAL
#undef IMAGE_SNAP_BY_ORDINAL
#undef IMAGE_ORDINAL_FLAG
#undef IMAGE_ORDINAL
#undef IMAGE_SNAP_BY_ORDINAL
#undef IMAGE_RESOURCE_NAME_IS_STRING
#undef IMAGE_RESOURCE_DATA_IS_DIRECTORY
#undef IMAGE_DEBUG_TYPE_UNKNOWN
#undef IMAGE_DEBUG_TYPE_COFF
#undef IMAGE_DEBUG_TYPE_CODEVIEW
#undef IMAGE_DEBUG_TYPE_FPO
#undef IMAGE_DEBUG_TYPE_MISC
#undef IMAGE_DEBUG_TYPE_EXCEPTION
#undef IMAGE_DEBUG_TYPE_FIXUP
#undef IMAGE_DEBUG_TYPE_OMAP_TO_SRC
#undef IMAGE_DEBUG_TYPE_OMAP_FROM_SRC
#undef IMAGE_DEBUG_TYPE_BORLAND
#undef IMAGE_DEBUG_TYPE_RESERVED10
#undef IMAGE_DEBUG_TYPE_CLSID
#undef IMAGE_DEBUG_MISC_EXENAME
#undef IMAGE_SEPARATE_DEBUG_SIGNATURE
#undef IMAGE_SEPARATE_DEBUG_FLAGS_MASK
#undef IMAGE_SEPARATE_DEBUG_MISMATCH

#include "dxc/config.h"

#define _ATL_DECLSPEC_ALLOCATOR

#define STRSAFE_NO_DEPRECATE
#define _Maybenull_
#define __in_range(x, y)
#define __in_ecount_opt(e)
#define Int32ToUInt32 IntToUInt
#define UInt32Add UIntAdd
#define Int32ToUInt32 IntToUInt
#define ATLASSERT assert

#define OutputDebugStringW(msg) fputws(msg, stderr)

#define OutputDebugStringA(msg) fputs(msg, stderr)
#define OutputDebugFormatA(...) fprintf(stderr, __VA_ARGS__)

HRESULT UInt32Mult(UINT a, UINT b, UINT *out);

// Patches because MinGW direct3d headers are not as up-to-date
//-------------------------------------------------------------
#define D3D12_SHVER_GET_TYPE(_Version) \
    (((_Version) >> 16) & 0xffff)
#define D3D12_SHVER_GET_MAJOR(_Version) \
    (((_Version) >> 4) & 0xf)
#define D3D12_SHVER_GET_MINOR(_Version) \
    (((_Version) >> 0) & 0xf)

// TODO: #ifndef?
// #define D3D_NAME_STENCIL_REF ((D3D_NAME)69)
// #define D3D_NAME_INNER_COVERAGE	((D3D_NAME)70)

#define D3D_SHADER_REQUIRES_DOUBLES                                                         0x00000001
#define D3D_SHADER_REQUIRES_EARLY_DEPTH_STENCIL                                             0x00000002
#define D3D_SHADER_REQUIRES_UAVS_AT_EVERY_STAGE                                             0x00000004
#define D3D_SHADER_REQUIRES_64_UAVS                                                         0x00000008
#define D3D_SHADER_REQUIRES_MINIMUM_PRECISION                                               0x00000010
#define D3D_SHADER_REQUIRES_11_1_DOUBLE_EXTENSIONS                                          0x00000020
#define D3D_SHADER_REQUIRES_11_1_SHADER_EXTENSIONS                                          0x00000040
#define D3D_SHADER_REQUIRES_LEVEL_9_COMPARISON_FILTERING                                    0x00000080
#define D3D_SHADER_REQUIRES_TILED_RESOURCES                                                 0x00000100
#define D3D_SHADER_REQUIRES_STENCIL_REF                                                     0x00000200
#define D3D_SHADER_REQUIRES_INNER_COVERAGE                                                  0x00000400
#define D3D_SHADER_REQUIRES_TYPED_UAV_LOAD_ADDITIONAL_FORMATS                               0x00000800
#define D3D_SHADER_REQUIRES_ROVS                                                            0x00001000
#define D3D_SHADER_REQUIRES_VIEWPORT_AND_RT_ARRAY_INDEX_FROM_ANY_SHADER_FEEDING_RASTERIZER  0x00002000
#define D3D_SHADER_REQUIRES_WAVE_OPS                                                        0x00004000
#define D3D_SHADER_REQUIRES_INT64_OPS                                                       0x00008000
#define D3D_SHADER_REQUIRES_VIEW_ID                                                         0x00010000
#define D3D_SHADER_REQUIRES_BARYCENTRICS                                                    0x00020000
#define D3D_SHADER_REQUIRES_NATIVE_16BIT_OPS                                                0x00040000
#define D3D_SHADER_REQUIRES_SHADING_RATE                                                    0x00080000
#define D3D_SHADER_REQUIRES_RAYTRACING_TIER_1_1                                             0x00100000
#define D3D_SHADER_REQUIRES_SAMPLER_FEEDBACK                                                0x00200000
#define D3D_SHADER_REQUIRES_ATOMIC_INT64_ON_TYPED_RESOURCE                                  0x00400000
#define D3D_SHADER_REQUIRES_ATOMIC_INT64_ON_GROUP_SHARED                                    0x00800000
#define D3D_SHADER_REQUIRES_DERIVATIVES_IN_MESH_AND_AMPLIFICATION_SHADERS                   0x01000000
#define D3D_SHADER_REQUIRES_RESOURCE_DESCRIPTOR_HEAP_INDEXING                               0x02000000
#define D3D_SHADER_REQUIRES_SAMPLER_DESCRIPTOR_HEAP_INDEXING                                0x04000000
#define D3D_SHADER_REQUIRES_WAVE_MMA                                                        0x08000000
#define D3D_SHADER_REQUIRES_ATOMIC_INT64_ON_DESCRIPTOR_HEAP_RESOURCE                        0x10000000
#define D3D_SHADER_FEATURE_ADVANCED_TEXTURE_OPS                                             0x20000000
#define D3D_SHADER_FEATURE_WRITEABLE_MSAA_TEXTURES                                          0x40000000

// ETW tracing shims, because we do not use ETW (requires codegen tool)
//
// Event Tracing for Windows (ETW) provides application programmers the ability
// to start and stop event tracing sessions, instrument an application to
// provide trace events, and consume trace events.
//---------------------------------------------------------------------
#define DxcEtw_DXCompilerShutdown_Start()
#define DxcEtw_DXCompilerShutdown_Stop(e)
#define DxcEtw_DXCompilerCreateInstance_Start()
#define DxcEtw_DXCompilerCreateInstance_Stop(hr)
#define DxcEtw_DXCompilerCompile_Start()
#define DxcEtw_DXCompilerCompile_Stop(hr)
#define DxcEtw_DXCompilerDisassemble_Start()
#define DxcEtw_DXCompilerDisassemble_Stop(hr)
#define DxcEtw_DXCompilerPreprocess_Start()
#define DxcEtw_DXCompilerPreprocess_Stop(hr)
#define DxcEtw_DxcValidation_Start()
#define DxcEtw_DxcValidation_Stop(hr)

#define DxcEtw_DXCompilerInitialization_Start()
#define DxcEtw_DXCompilerInitialization_Stop(e)
#define EventRegisterMicrosoft_Windows_DXCompiler_API()
#define EventUnregisterMicrosoft_Windows_DXCompiler_API()

//===--------------------- HRESULT Related Macros -------------------------===//

#define E_BOUNDS (HRESULT)0x8000000B
#define E_NOT_VALID_STATE (HRESULT)0x8007139F

#define DXC_FAILED(hr) (((HRESULT)(hr)) < 0)

//===--------------------- COM Pointer Types ------------------------------===//
#ifdef __cplusplus
#include <atomic>
#include <cassert>
#include <climits>
#include <cstring>
#include <cwchar>
#include <fstream>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <string>
#include <typeindex>
#include <typeinfo>
#include <vector>

class CAllocator {
public:
  static void *Reallocate(void *p, size_t nBytes) throw();
  static void *Allocate(size_t nBytes) throw();
  static void Free(void *p) throw();
};

template <class T> class CComPtrBase {
protected:
  CComPtrBase() throw() { p = nullptr; }
  CComPtrBase(T *lp) throw() {
    p = lp;
    if (p != nullptr)
      p->AddRef();
  }
  void Swap(CComPtrBase &other) {
    T *pTemp = p;
    p = other.p;
    other.p = pTemp;
  }

public:
  ~CComPtrBase() throw() {
    if (p) {
      p->Release();
      p = nullptr;
    }
  }
  operator T *() const throw() { return p; }
  T &operator*() const { return *p; }
  T *operator->() const { return p; }
  T **operator&() throw() {
    assert(p == nullptr);
    return &p;
  }
  bool operator!() const throw() { return (p == nullptr); }
  bool operator<(T *pT) const throw() { return p < pT; }
  bool operator!=(T *pT) const { return !operator==(pT); }
  bool operator==(T *pT) const throw() { return p == pT; }

  // Release the interface and set to nullptr
  void Release() throw() {
    T *pTemp = p;
    if (pTemp) {
      p = nullptr;
      pTemp->Release();
    }
  }

  // Attach to an existing interface (does not AddRef)
  void Attach(T *p2) throw() {
    if (p) {
      ULONG ref = p->Release();
      (void)(ref);
      // Attaching to the same object only works if duplicate references are
      // being coalesced.  Otherwise re-attaching will cause the pointer to be
      // released and may cause a crash on a subsequent dereference.
      assert(ref != 0 || p2 != p);
    }
    p = p2;
  }

  // Detach the interface (does not Release)
  T *Detach() throw() {
    T *pt = p;
    p = nullptr;
    return pt;
  }

  HRESULT CopyTo(T **ppT) throw() {
    assert(ppT != nullptr);
    if (ppT == nullptr)
      return E_POINTER;
    *ppT = p;
    if (p)
      p->AddRef();
    return S_OK;
  }

  template <class Q> HRESULT QueryInterface(Q **pp) const throw() {
    assert(pp != nullptr);
    return p->QueryInterface(__uuidof(Q), (void **)pp);
  }

  T *p;
};

template <class T> class CComPtr : public CComPtrBase<T> {
public:
  CComPtr() throw() {}
  CComPtr(T *lp) throw() : CComPtrBase<T>(lp) {}
  CComPtr(const CComPtr<T> &lp) throw() : CComPtrBase<T>(lp.p) {}
  T *operator=(T *lp) throw() {
    if (*this != lp) {
      CComPtr(lp).Swap(*this);
    }
    return *this;
  }

  inline bool IsEqualObject(IUnknown *pOther) throw() {
    if (this->p == nullptr && pOther == nullptr)
      return true; // They are both NULL objects

    if (this->p == nullptr || pOther == nullptr)
      return false; // One is NULL the other is not

    CComPtr<IUnknown> punk1;
    CComPtr<IUnknown> punk2;
    this->p->QueryInterface(__uuidof(IUnknown), (void **)&punk1);
    pOther->QueryInterface(__uuidof(IUnknown), (void **)&punk2);
    return punk1 == punk2;
  }

  void ComPtrAssign(IUnknown **pp, IUnknown *lp, REFIID riid) {
    IUnknown *pTemp = *pp; // takes ownership
    if (lp == nullptr || FAILED(lp->QueryInterface(riid, (void **)pp)))
      *pp = nullptr;
    if (pTemp)
      pTemp->Release();
  }

  template <typename Q> T *operator=(const CComPtr<Q> &lp) throw() {
    if (!this->IsEqualObject(lp)) {
      ComPtrAssign((IUnknown **)&this->p, lp, __uuidof(T));
    }
    return *this;
  }

  // NOTE: This conversion constructor is not part of the official CComPtr spec;
  // however, it is needed to convert CComPtr<Q> to CComPtr<T> where T derives
  // from Q on Clang. MSVC compiles this conversion as first a call to
  // CComPtr<Q>::operator T*, followed by CComPtr<T>(T*), but Clang fails to
  // compile with error: no viable conversion from 'CComPtr<Q>' to 'CComPtr<T>'.
  template <typename Q>
  CComPtr(const CComPtr<Q> &lp) throw() : CComPtrBase<T>(lp.p) {}

  T *operator=(const CComPtr<T> &lp) throw() {
    if (*this != lp) {
      CComPtr(lp).Swap(*this);
    }
    return *this;
  }

  CComPtr(CComPtr<T> &&lp) throw() : CComPtrBase<T>() { lp.Swap(*this); }

  T *operator=(CComPtr<T> &&lp) throw() {
    if (*this != lp) {
      CComPtr(static_cast<CComPtr &&>(lp)).Swap(*this);
    }
    return *this;
  }
};

template <class T> class CSimpleArray : public std::vector<T> {
public:
  bool Add(const T &t) {
    this->push_back(t);
    return true;
  }
  int GetSize() { return this->size(); }
  T *GetData() { return this->data(); }
  void RemoveAll() { this->clear(); }
};

template <class T, class Allocator = CAllocator> class CHeapPtrBase {
protected:
  CHeapPtrBase() throw() : m_pData(NULL) {}
  CHeapPtrBase(CHeapPtrBase<T, Allocator> &p) throw() {
    m_pData = p.Detach(); // Transfer ownership
  }
  explicit CHeapPtrBase(T *pData) throw() : m_pData(pData) {}

public:
  ~CHeapPtrBase() throw() { Free(); }

protected:
  CHeapPtrBase<T, Allocator> &operator=(CHeapPtrBase<T, Allocator> &p) throw() {
    if (m_pData != p.m_pData)
      Attach(p.Detach()); // Transfer ownership
    return *this;
  }

public:
  operator T *() const throw() { return m_pData; }
  T *operator->() const throw() {
    assert(m_pData != NULL);
    return m_pData;
  }

  T **operator&() throw() {
    assert(m_pData == NULL);
    return &m_pData;
  }

  // Allocate a buffer with the given number of bytes
  bool AllocateBytes(size_t nBytes) throw() {
    assert(m_pData == NULL);
    m_pData = static_cast<T *>(Allocator::Allocate(nBytes * sizeof(char)));
    if (m_pData == NULL)
      return false;

    return true;
  }

  // Attach to an existing pointer (takes ownership)
  void Attach(T *pData) throw() {
    Allocator::Free(m_pData);
    m_pData = pData;
  }

  // Detach the pointer (releases ownership)
  T *Detach() throw() {
    T *pTemp = m_pData;
    m_pData = NULL;
    return pTemp;
  }

  // Free the memory pointed to, and set the pointer to NULL
  void Free() throw() {
    Allocator::Free(m_pData);
    m_pData = NULL;
  }

  // Reallocate the buffer to hold a given number of bytes
  bool ReallocateBytes(size_t nBytes) throw() {
    T *pNew;
    pNew =
        static_cast<T *>(Allocator::Reallocate(m_pData, nBytes * sizeof(char)));
    if (pNew == NULL)
      return false;
    m_pData = pNew;

    return true;
  }

public:
  T *m_pData;
};

template <typename T, class Allocator = CAllocator>
class CHeapPtr : public CHeapPtrBase<T, Allocator> {
public:
  CHeapPtr() throw() {}
  CHeapPtr(CHeapPtr<T, Allocator> &p) throw() : CHeapPtrBase<T, Allocator>(p) {}
  explicit CHeapPtr(T *p) throw() : CHeapPtrBase<T, Allocator>(p) {}
  CHeapPtr<T> &operator=(CHeapPtr<T, Allocator> &p) throw() {
    CHeapPtrBase<T, Allocator>::operator=(p);
    return *this;
  }

  // Allocate a buffer with the given number of elements
  bool Allocate(size_t nElements = 1) throw() {
    size_t nBytes = nElements * sizeof(T);
    return this->AllocateBytes(nBytes);
  }

  // Reallocate the buffer to hold a given number of elements
  bool Reallocate(size_t nElements) throw() {
    size_t nBytes = nElements * sizeof(T);
    return this->ReallocateBytes(nBytes);
  }
};

#define CComHeapPtr CHeapPtr

//===--------------------- UTF-8 Related Types ----------------------------===//

// Code Page
#define CP_ACP 0
#define CP_UTF8 65001 // UTF-8 translation.

// Convert Windows codepage value to locale string
const char *CPToLocale(uint32_t CodePage);

// The t_nBufferLength parameter is part of the published interface, but not
// used here.
template <int t_nBufferLength = 128> class CW2AEX {
public:
  CW2AEX(LPCWSTR psz, UINT nCodePage = CP_UTF8) {
    const char *locale = CPToLocale(nCodePage);
    if (locale == nullptr) {
      // Current Implementation only supports CP_UTF8, and CP_ACP
      assert(false && "CW2AEX implementation for Linux only handles "
                      "UTF8 and ACP code pages");
      return;
    }

    if (!psz) {
      m_psz = NULL;
      return;
    }

    locale = setlocale(LC_ALL, locale);
    int len = (wcslen(psz) + 1) * 4;
    m_psz = new char[len];
    std::wcstombs(m_psz, psz, len);
    setlocale(LC_ALL, locale);
  }

  ~CW2AEX() { delete[] m_psz; }

  operator LPSTR() const { return m_psz; }

  char *m_psz;
};
typedef CW2AEX<> CW2A;

// The t_nBufferLength parameter is part of the published interface, but not
// used here.
template <int t_nBufferLength = 128> class CA2WEX {
public:
  CA2WEX(LPCSTR psz, UINT nCodePage = CP_UTF8) {
    const char *locale = CPToLocale(nCodePage);
    if (locale == nullptr) {
      // Current Implementation only supports CP_UTF8, and CP_ACP
      assert(false && "CA2WEX implementation for Linux only handles "
                      "UTF8 and ACP code pages");
      return;
    }

    if (!psz) {
      m_psz = NULL;
      return;
    }

    locale = setlocale(LC_ALL, locale);
    int len = strlen(psz) + 1;
    m_psz = new wchar_t[len];
    std::mbstowcs(m_psz, psz, len);
    setlocale(LC_ALL, locale);
  }

  ~CA2WEX() { delete[] m_psz; }

  operator LPWSTR() const { return m_psz; }

  wchar_t *m_psz;
};

typedef CA2WEX<> CA2W;

//===--------- File IO Related Types ----------------===//

class CHandle {
public:
  CHandle(HANDLE h);
  ~CHandle();
  operator HANDLE() const throw();

private:
  HANDLE m_h;
};

/////////////////////////////////////////////////////////////////////////////
// CComBSTR

class CComBSTR {
public:
  BSTR m_str;
  CComBSTR() : m_str(nullptr){};
  CComBSTR(int nSize, LPCWSTR sz);
  ~CComBSTR() throw() { SysFreeString(m_str); }

  operator BSTR() const throw() { return m_str; }

  bool operator==(const CComBSTR &bstrSrc) const throw();

  BSTR *operator&() throw() { return &m_str; }

  BSTR Detach() throw() {
    BSTR s = m_str;
    m_str = NULL;
    return s;
  }
};

//===--------- Convert argv to wchar ----------------===//
class WArgV {
  std::vector<std::wstring> WStringVector;
  std::vector<const wchar_t *> WCharPtrVector;

public:
  WArgV(int argc, const char **argv);
  const wchar_t **argv() { return WCharPtrVector.data(); }
};



#ifdef ZIG_MINGW_DECLARE_SPECIALIZATIONS
#include "dxc/dxcapi.h"
#include "dxc/dxcapi.internal.h"
#include "dxc/dxcisense.h"
#include "dxc/dxctools.h"
CROSS_PLATFORM_UUIDOF(IDiaDataSource, "79F1BB5F-B66E-48e5-B6A9-1545C323CA3D")
CROSS_PLATFORM_UUIDOF(ID3D12LibraryReflection, "8E349D19-54DB-4A56-9DC9-119D87BDB804")
CROSS_PLATFORM_UUIDOF(ID3D12ShaderReflection, "5A58797D-A72C-478D-8BA2-EFC6B0EFE88E")
CROSS_PLATFORM_UUIDOF(IDxcPixDxilDebugInfoFactory, "9c2a040d-8068-44ec-8c68-8bfef1b43789")
#endif // ZIG_MINGW_DECLARE_SPECIALIZATIONS

#endif // __cplusplus

#undef ReplaceText

#endif // defined(__clang__) && !defined(_MSC_VER) && defined(_WIN32) // Zig windows-gnu target
#endif // LLVM_SUPPORT_ZIG_GNU_WIN_ADAPTER_H
