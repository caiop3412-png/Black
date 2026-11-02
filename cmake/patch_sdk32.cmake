# armv7 (32-bit) fixes for the SDK's portable runtime, applied in place after the SDK is found. Safe to run again:
# a file that no longer has the original text is left alone.
#
# runtime/gpu/shaders.cpp Hash(): a 64 x 64 -> 128 bit multiply through unsigned __int128, which clang has only on
# 64-bit targets. Same result, from four 32 x 32 -> 64 bit products.
function(patch_sdk32 SDK_DIR)
    set(file "${SDK_DIR}/runtime/gpu/shaders.cpp")
    if(NOT EXISTS "${file}")
        message(WARNING "patch_sdk32: ${file} not found, the SDK layout changed")
        return()
    endif()
    file(READ "${file}" text)
    if(NOT text MATCHES "unsigned __int128")
        return()
    endif()
    set(new "uint64_t a0 = uint32_t(a), a1 = a >> 32, b0 = uint32_t(b), b1 = b >> 32;
        uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
        uint64_t mid = (p00 >> 32) + uint32_t(p01) + uint32_t(p10);
        uint64_t lo = (mid << 32) | uint32_t(p00);
        uint64_t hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);
        return lo ^ hi;")
    string(REGEX REPLACE
        "unsigned __int128 r = static_cast<unsigned __int128>\\(a\\) \\* b;[ \t\r\n]*return uint64_t\\(r\\) \\^ uint64_t\\(r >> 64\\);"
        "${new}" patched "${text}")
    if(patched STREQUAL text)
        message(FATAL_ERROR "patch_sdk32: the __int128 in ${file} is not the code this patch knows; look at Hash()")
    endif()
    file(WRITE "${file}" "${patched}")
    message(STATUS "patch_sdk32: shaders.cpp Hash() without __int128")
    # anything else in the SDK that needs 128 bits fails to build on its own; say where
    file(GLOB_RECURSE others "${SDK_DIR}/runtime/*.cpp" "${SDK_DIR}/runtime/*.h")
    foreach(f IN LISTS others)
        file(READ "${f}" t)
        if(t MATCHES "__int128")
            message(WARNING "patch_sdk32: __int128 still in ${f}")
        endif()
    endforeach()
endfunction()
