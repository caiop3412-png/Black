# armv7 (32-bit) fixes for the SDK's portable runtime, applied in place after the SDK is found. Safe to run again:
# a file that no longer has the original text is left alone.
#
# clang has no unsigned __int128 on 32-bit targets. The SDK uses it twice, both for the high half of a 64 x 64 bit
# multiply; both are rewritten with four 32 x 32 -> 64 bit products (same result).

set(_SDK32_DIR "${CMAKE_CURRENT_LIST_DIR}")

# replace `from` by `to` exactly once in the text held by variable `var` (caller's scope); fatal if `from` is missing
function(_sdk32_replace var from to what)
    string(FIND "${${var}}" "${from}" at)
    if(at EQUAL -1)
        message(FATAL_ERROR "patch_sdk32: '${from}' not found in ${what}; the SDK changed")
    endif()
    string(REPLACE "${from}" "${to}" out "${${var}}")
    set(${var} "${out}" PARENT_SCOPE)
endfunction()

# the high 64 bits of x * y, as statements that define `hi` (needs x, y as uint64_t)
set(_MULHI_BODY "uint64_t a0 = uint32_t(@X@), a1 = @X@ >> 32, b0 = uint32_t(@Y@), b1 = @Y@ >> 32;
    uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
    uint64_t mid = (p00 >> 32) + uint32_t(p01) + uint32_t(p10);
    uint64_t lo = (mid << 32) | uint32_t(p00);
    uint64_t hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);")

function(_patch_sdk32_file file old new what)
    if(NOT EXISTS "${file}")
        message(WARNING "patch_sdk32: ${file} not found, the SDK layout changed")
        return()
    endif()
    file(READ "${file}" text)
    if(NOT text MATCHES "__int128")
        return()   # already patched
    endif()
    string(FIND "${text}" "${old}" pos)
    if(pos EQUAL -1)
        message(FATAL_ERROR "patch_sdk32: the __int128 in ${file} is not the code this patch knows; look at ${what}")
    endif()
    string(REPLACE "${old}" "${new}" patched "${text}")
    file(WRITE "${file}" "${patched}")
    message(STATUS "patch_sdk32: ${what} without __int128")
endfunction()

function(patch_sdk32 SDK_DIR)
    # runtime/gpu/shaders.cpp Hash(): xor of the two halves of a * b
    string(REPLACE "@X@" "a" body "${_MULHI_BODY}")
    string(REPLACE "@Y@" "b" body "${body}")
    _patch_sdk32_file("${SDK_DIR}/runtime/gpu/shaders.cpp"
        "unsigned __int128 r = static_cast<unsigned __int128>(a) * b;
        return uint64_t(r) ^ uint64_t(r >> 64);"
        "${body}
        return lo ^ hi;"
        "Hash() in shaders.cpp")

    # runtime/kernel/rtl.cpp RtlExtendedMagicDivide: (u * m) >> 64, then >> shift
    string(REPLACE "@X@" "u" body "${_MULHI_BODY}")
    string(REPLACE "@Y@" "m" body "${body}")
    _patch_sdk32_file("${SDK_DIR}/runtime/kernel/rtl.cpp"
        "uint64_t q = uint64_t((unsigned __int128)u * m >> 64) >> (a[4] & 0xFF);"
        "${body}
    uint64_t q = hi >> (a[4] & 0xFF);"
        "RtlExtendedMagicDivide in rtl.cpp")

    # harness/compat/winsock2.h: SOCKET is int, and on 32-bit bionic socklen_t is int too, so the shims below have the
    # same signature as the libc functions they wrap (getsockname, getpeername, accept, getsockopt) and call
    # themselves forever, or (recvfrom) make the call ambiguous. Give them their own names, like select().
    set(ws "${SDK_DIR}/harness/compat/winsock2.h")
    if(EXISTS "${ws}")
        file(READ "${ws}" wtext)
        if(NOT wtext MATCHES "ws_getsockname")
            set(wnew "${wtext}")
            foreach(pair
                    "inline int getsockname(SOCKET|inline int ws_getsockname(SOCKET"
                    "inline int getpeername(SOCKET|inline int ws_getpeername(SOCKET"
                    "inline ssize_t recvfrom(SOCKET|inline ssize_t ws_recvfrom(SOCKET"
                    "inline SOCKET accept(SOCKET|inline SOCKET ws_accept(SOCKET"
                    "inline int getsockopt(SOCKET|inline int ws_getsockopt(SOCKET")
                string(REPLACE "|" ";" pair "${pair}")
                list(GET pair 0 from)
                list(GET pair 1 to)
                string(FIND "${wnew}" "${from}" at)
                if(at EQUAL -1)
                    message(FATAL_ERROR "patch_sdk32: '${from}' not found in ${ws}; look at the socket shims")
                endif()
                string(REPLACE "${from}" "${to}" wnew "${wnew}")
            endforeach()
            string(APPEND wnew "\n// armv7: the shims above keep their own names; callers in the runtime get them through these\n"
                "#define getsockname ws_getsockname\n#define getpeername ws_getpeername\n#define recvfrom ws_recvfrom\n"
                "#define accept ws_accept\n#define getsockopt ws_getsockopt\n")
            file(WRITE "${ws}" "${wnew}")
            message(STATUS "patch_sdk32: Winsock shims renamed in winsock2.h")
        endif()
    else()
        message(WARNING "patch_sdk32: ${ws} not found, the SDK layout changed")
    endif()

    # kernel/memory.cpp + memory.h: the guest address space is one flat 4 GB mmap at host base + guest address, which a
    # 32-bit process cannot hold (size_t(1 << 32) is 0 here). The guest only uses five ranges, so map just those: a host
    # base is searched where all five land on free addresses (guest address + base wraps modulo 2^32 on a 32-bit host).
    # The user range, the system pool and the stacks are cut down to what a 64 MB console needs.
    set(memh "${SDK_DIR}/runtime/kernel/memory.h")
    set(memc "${SDK_DIR}/runtime/kernel/memory.cpp")
    if(EXISTS "${memh}" AND EXISTS "${memc}")
        file(READ "${memc}" ctext)
        if(NOT ctext MATCHES "ReserveGuestSpace")
            file(READ "${memh}" htext)
            _sdk32_replace(htext "kUserHigh = 0x7FFE0000" "kUserHigh = 0x10000000" "memory.h")
            _sdk32_replace(htext "kSystemSize = 0x10000000" "kSystemSize = 0x04000000" "memory.h")
            _sdk32_replace(htext "kStackSize = 0x10000000" "kStackSize = 0x04000000" "memory.h")
            file(WRITE "${memh}" "${htext}")

            _sdk32_replace(ctext
                "void* p = mmap(reinterpret_cast<void*>(0x100000000ull), size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);"
                "void* p = ReserveGuestSpace(size);" "memory.cpp")
            file(READ "${_SDK32_DIR}/guest_space32.inc" reserve)
            _sdk32_replace(ctext "bool Init() {" "${reserve}\nbool Init() {" "memory.cpp")
            file(WRITE "${memc}" "${ctext}")
            message(STATUS "patch_sdk32: guest memory mapped in five ranges")
        endif()
    else()
        message(WARNING "patch_sdk32: kernel/memory.{h,cpp} not found, the SDK layout changed")
    endif()

    # anything else in the SDK that needs 128 bits fails to build on its own; say where
    file(GLOB_RECURSE others "${SDK_DIR}/runtime/*.cpp" "${SDK_DIR}/runtime/*.h")
    foreach(f IN LISTS others)
        file(READ "${f}" t)
        if(t MATCHES "__int128")
            message(WARNING "patch_sdk32: __int128 still in ${f}")
        endif()
    endforeach()
endfunction()
