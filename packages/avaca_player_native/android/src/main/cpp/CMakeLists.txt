cmake_minimum_required(VERSION 3.22.1)
project(avaca_player_native_android LANGUAGES C CXX)

set(AVACA_MSQUIC_ROOT "" CACHE PATH
    "Pinned MsQuic v2.6.0 source checkout used by the Android player")
if(NOT AVACA_MSQUIC_ROOT OR NOT EXISTS "${AVACA_MSQUIC_ROOT}/src/inc/msquic.h")
  message(FATAL_ERROR
    "AVACA_MSQUIC_ROOT must point at the pinned MsQuic source checkout")
endif()

# This is the only supported Android transport build: official MsQuic with
# bundled quictls, no Java/Kotlin HTTP or socket fallback.
set(QUIC_TLS_LIB quictls CACHE STRING "" FORCE)
set(QUIC_BUILD_SHARED ON CACHE BOOL "" FORCE)
set(QUIC_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(QUIC_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(QUIC_BUILD_PERF OFF CACHE BOOL "" FORCE)
set(QUIC_ENABLE_LOGGING OFF CACHE BOOL "" FORCE)
set(QUIC_LIBRARY_NAME msquic CACHE STRING "" FORCE)

# MsQuic's Android quictls Configure step is a POSIX-style command.  When an
# Android target is configured on Windows, the upstream CMake emits
# `SYSTEM=Windows ...` directly to cmd.exe.  Keep the pinned checkout intact
# and patch only a build-tree overlay to use CMake's portable environment
# launcher plus the Git-for-Windows Perl that runs Configure.
set(_avaca_msquic_source "${AVACA_MSQUIC_ROOT}")
  if(CMAKE_HOST_WIN32 AND ANDROID)
    find_program(AVACA_PERL_EXECUTABLE perl
      PATHS "$ENV{ProgramFiles}/Git/usr/bin"
      "$ENV{ProgramW6432}/Git/usr/bin")
    if(NOT AVACA_PERL_EXECUTABLE)
    message(FATAL_ERROR
        "Android MsQuic/quictls build on Windows requires Git-for-Windows Perl")
    endif()
    find_program(AVACA_MAKE_EXECUTABLE make
      PATHS "$ENV{ProgramFiles}/Git/usr/bin"
      "$ENV{ProgramW6432}/Git/usr/bin"
      "${CMAKE_ANDROID_NDK}/prebuilt/windows-x86_64/bin")
    if(NOT AVACA_MAKE_EXECUTABLE)
      message(FATAL_ERROR
        "Android MsQuic/quictls build on Windows requires GNU make")
    endif()
    if(NOT CMAKE_ANDROID_NDK)
      message(FATAL_ERROR
        "Android MsQuic/quictls build on Windows requires CMAKE_ANDROID_NDK")
    endif()
    set(_avaca_ndk_toolchain_bin
      "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/windows-x86_64/bin")
    set(_avaca_msquic_overlay "${CMAKE_BINARY_DIR}/avaca-msquic-source")
  if(NOT EXISTS "${_avaca_msquic_overlay}/.avaca-windows-overlay")
    file(REMOVE_RECURSE "${_avaca_msquic_overlay}")
    file(COPY "${AVACA_MSQUIC_ROOT}/"
      DESTINATION "${_avaca_msquic_overlay}"
      PATTERN ".git" EXCLUDE
      PATTERN "build" EXCLUDE
      PATTERN "artifacts" EXCLUDE)
    file(MAKE_DIRECTORY
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/Locale/Maketext")
    file(MAKE_DIRECTORY
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/ExtUtils")
    file(MAKE_DIRECTORY
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/Pod")
    file(COPY
      "${CMAKE_CURRENT_LIST_DIR}/perl/Locale/Maketext/Simple.pm"
      DESTINATION
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/Locale/Maketext")
    file(COPY
      "${CMAKE_CURRENT_LIST_DIR}/perl/ExtUtils/MakeMaker.pm"
      DESTINATION
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/ExtUtils")
    file(COPY
      "${CMAKE_CURRENT_LIST_DIR}/perl/Pod/Usage.pm"
      DESTINATION
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl/Pod")
    file(COPY
      "${CMAKE_CURRENT_LIST_DIR}/normalize_openssl_makefile.cmake"
      DESTINATION "${_avaca_msquic_overlay}/submodules")
    file(READ
      "${_avaca_msquic_overlay}/submodules/quictls/Configurations/15-android.conf"
      _avaca_android_config)
    string(REPLACE
      [=[$ndk = canonpath($ndk);]=]
      [=[$ndk = canonpath($ndk);
    # Git-for-Windows Perl exposes Windows PATH entries as /d/... paths.
    # Normalize the NDK root before matching clang/llvm-ar returned by which().
    $ndk =~ s|^([A-Za-z]):|"/".lc($1)|e;]=]
      _avaca_android_config "${_avaca_android_config}")
    file(WRITE
      "${_avaca_msquic_overlay}/submodules/quictls/Configurations/15-android.conf"
      "${_avaca_android_config}")
    file(READ
      "${_avaca_msquic_overlay}/src/platform/selfsign_openssl.c"
      _avaca_selfsign_openssl)
    string(REPLACE
      [=[#include "platform_internal.h"]=]
      [=[#include "platform_internal.h"

#if defined(__ANDROID__) && __ANDROID_API__ < 28
static int
avaca_android_glob(
    const char* Pattern,
    int Flags,
    int (*ErrorFunction)(const char*, int),
    glob_t* Result
    )
{
    (void)Pattern;
    (void)Flags;
    (void)ErrorFunction;
    (void)Result;
    return GLOB_NOMATCH;
}

static void
avaca_android_globfree(
    glob_t* Result
    )
{
    (void)Result;
}

#define glob avaca_android_glob
#define globfree avaca_android_globfree
#endif]=]
      _avaca_selfsign_openssl "${_avaca_selfsign_openssl}")
    file(WRITE
      "${_avaca_msquic_overlay}/src/platform/selfsign_openssl.c"
      "${_avaca_selfsign_openssl}")
    set(_avaca_quictls_perl_dir
      "${_avaca_msquic_overlay}/submodules/quictls/util/perl")
    string(SUBSTRING "${_avaca_quictls_perl_dir}" 0 1
      _avaca_perl_drive_letter)
    string(TOLOWER "${_avaca_perl_drive_letter}" _avaca_perl_drive_lower)
    string(SUBSTRING "${_avaca_quictls_perl_dir}" 2 -1
      _avaca_perl_path_rest)
    set(_avaca_perl5lib "/${_avaca_perl_drive_lower}${_avaca_perl_path_rest}")
    set(_avaca_perl_for_make "${AVACA_PERL_EXECUTABLE}")
    string(REPLACE
      "C:/Program Files/"
      "C:/PROGRA~1/"
      _avaca_perl_for_make "${_avaca_perl_for_make}")
    set(_avaca_make_path
      "${_avaca_ndk_toolchain_bin}\\;C:/PROGRA~1/Git/usr/bin")
    file(WRITE "${_avaca_msquic_overlay}/avaca-make-export.mk"
      "export SHELL\n")
    file(READ "${_avaca_msquic_overlay}/submodules/CMakeLists.txt"
      _avaca_msquic_submodules)
    string(REPLACE
      "COMMAND SYSTEM=\${CMAKE_HOST_SYSTEM_NAME}\n            \${OPENSSL_CONFIG_CMD} \${OPENSSL_CONFIG_FLAGS}"
      "COMMAND ${CMAKE_COMMAND} -E env SYSTEM=${CMAKE_HOST_SYSTEM_NAME} ANDROID_NDK_ROOT=${CMAKE_ANDROID_NDK} PATH=${_avaca_make_path} PERL5LIB=${_avaca_perl5lib} ${AVACA_PERL_EXECUTABLE} \${OPENSSL_CONFIG_CMD} \${OPENSSL_CONFIG_FLAGS}\n        COMMAND ${CMAKE_COMMAND} -DOPENSSL_MAKEFILE=\${QUIC_BUILD_DIR}/submodules/\${QUIC_OPENSSL}/Makefile -DOPENSSL_SOURCE=\${CMAKE_CURRENT_SOURCE_DIR}/\${QUIC_OPENSSL} -DOPENSSL_BUILD=\${QUIC_BUILD_DIR}/submodules/\${QUIC_OPENSSL} -P \${CMAKE_CURRENT_LIST_DIR}/normalize_openssl_makefile.cmake"
      _avaca_msquic_submodules "${_avaca_msquic_submodules}")
    string(REPLACE
      "COMMAND make install_dev -j\${NPROCS}"
      "COMMAND ${CMAKE_COMMAND} -E env SHELL=C:/PROGRA~1/Git/usr/bin/sh.exe MAKEFILES=${_avaca_msquic_overlay}/avaca-make-export.mk PATH=${_avaca_make_path} PERL=${_avaca_perl_for_make} PERL5LIB=${_avaca_perl5lib} PERL5OPT=-Moids_to_c ${AVACA_MAKE_EXECUTABLE} PERL=${_avaca_perl_for_make} PERL5LIB=${_avaca_perl5lib} PERL5OPT=-Moids_to_c install_dev -j\${NPROCS}"
      _avaca_msquic_submodules "${_avaca_msquic_submodules}")
    file(WRITE "${_avaca_msquic_overlay}/submodules/CMakeLists.txt"
      "${_avaca_msquic_submodules}")
    file(TOUCH "${_avaca_msquic_overlay}/.avaca-windows-overlay")
  endif()
  file(COPY
    "${_avaca_msquic_overlay}/submodules/quictls/providers/common/der/oids_to_c.pm"
    DESTINATION "${_avaca_msquic_overlay}/submodules/quictls/util/perl")
  set(_avaca_msquic_source "${_avaca_msquic_overlay}")
endif()
add_subdirectory("${_avaca_msquic_source}" "${CMAKE_BINARY_DIR}/msquic")

add_library(avaca_remote_android SHARED avaca_android_remote_quic.cpp)
target_compile_features(avaca_remote_android PRIVATE cxx_std_17)
target_compile_definitions(avaca_remote_android PRIVATE
  QUIC_API_ENABLE_PREVIEW_FEATURES)
target_include_directories(avaca_remote_android PRIVATE
  "${AVACA_MSQUIC_ROOT}/src/inc")
target_link_libraries(avaca_remote_android PRIVATE msquic log android)

# JNI handles and protocol buffers are kept in the native module; the Dart
# isolate never receives media bytes.
set_target_properties(avaca_remote_android PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES)
