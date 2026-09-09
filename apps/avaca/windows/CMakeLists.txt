# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
# The installed Visual Studio FileTracker cannot create its .tlog files in
# this workspace. Apply the MSBuild workaround before project generation.
set(CMAKE_VS_GLOBALS "TrackFileAccess=false")

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()
project(avaca LANGUAGES CXX)

# Keep the debug CRT consistent with Flutter's `_DEBUG` runner definitions.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "avaca")
set(AVACA_BUILD_ROLE "avaca" CACHE STRING "Application composition")
set(AVACA_WINDOWS_PLAYER_DEPS_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../windows/engine" CACHE PATH
  "Pinned AVACA Windows player dependency root" FORCE)
set(AVACA_MSQUIC_ROOT "" CACHE PATH
  "Validated MsQuic source root containing src/inc/msquic.h")
set(AVACA_MSQUIC_DLL "" CACHE FILEPATH
  "Validated MsQuic runtime DLL built from AVACA_MSQUIC_ROOT")
set(AVACA_REMOTE_QUIC_ENABLED OFF)
if(AVACA_MSQUIC_ROOT OR AVACA_MSQUIC_DLL)
  if(NOT AVACA_MSQUIC_ROOT OR NOT AVACA_MSQUIC_DLL)
    message(FATAL_ERROR "AVACA QUIC requires both AVACA_MSQUIC_ROOT and AVACA_MSQUIC_DLL")
  endif()
  if(NOT EXISTS "${AVACA_MSQUIC_ROOT}/src/inc/msquic.h" OR
     NOT EXISTS "${AVACA_MSQUIC_DLL}")
    message(FATAL_ERROR "AVACA QUIC dependency closure is incomplete")
  endif()
  set(AVACA_REMOTE_QUIC_ENABLED ON)
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  if(MSVC)
    set_property(TARGET ${TARGET} PROPERTY MSVC_RUNTIME_LIBRARY
      "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
  endif()
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Keep the separated AVACA client on the same pinned Flutter Windows engine as
# the root portable bundle.  The stock engine can build successfully while
# silently reintroducing the unsupported ANGLE swap-chain path, so copy the
# verified engine and import library into the generated bundle explicitly.
set(AVACA_PINNED_FLUTTER_ENGINE_DLL
  "${AVACA_WINDOWS_PLAYER_DEPS_ROOT}/flutter_windows.dll")
set(AVACA_PINNED_FLUTTER_ENGINE_IMPORT_LIB
  "${AVACA_WINDOWS_PLAYER_DEPS_ROOT}/flutter_windows.dll.lib")
if(NOT EXISTS "${AVACA_PINNED_FLUTTER_ENGINE_DLL}" OR
   NOT EXISTS "${AVACA_PINNED_FLUTTER_ENGINE_IMPORT_LIB}")
  message(FATAL_ERROR
    "AVACA pinned Flutter engine requires both flutter_windows.dll and "
    "flutter_windows.dll.lib")
endif()

add_custom_target(avaca_pinned_flutter_engine ALL
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${AVACA_PINNED_FLUTTER_ENGINE_DLL}" "${FLUTTER_LIBRARY}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${AVACA_PINNED_FLUTTER_ENGINE_IMPORT_LIB}" "${FLUTTER_LIBRARY}.lib"
  DEPENDS flutter_assemble
          "${AVACA_PINNED_FLUTTER_ENGINE_DLL}"
          "${AVACA_PINNED_FLUTTER_ENGINE_IMPORT_LIB}"
  VERBATIM)
add_dependencies(flutter_wrapper_app avaca_pinned_flutter_engine)
add_dependencies(flutter_wrapper_plugin avaca_pinned_flutter_engine)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../../packages/avaca_remote_core/windows"
  "avaca_remote_core_build")
add_subdirectory("runner")

# The player plugin's runtime DLLs are part of the AVACA client closure and
# must be copied beside avaca.exe (Flutter does not know about this plugin-local
# post-build list when it performs the install step).
foreach(runtime_name
    libmpv-2.dll
    libEGL.dll
    libGLESv2.dll
    d3dcompiler_47.dll
    vk_swiftshader.dll
    vulkan-1.dll)
  set(runtime_path "${AVACA_WINDOWS_PLAYER_DEPS_ROOT}/${runtime_name}")
  if(NOT EXISTS "${runtime_path}")
    message(FATAL_ERROR "Missing pinned AVACA player runtime file: ${runtime_path}")
  endif()
endforeach()


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
# Flutter may pre-seed CMake with the machine-wide `C:/Program Files` prefix.
# An application bundle must always install beside its runner instead.
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

foreach(runtime_name
    libmpv-2.dll
    libEGL.dll
    libGLESv2.dll
    d3dcompiler_47.dll
    vk_swiftshader.dll
    vulkan-1.dll)
  install(FILES "${AVACA_WINDOWS_PLAYER_DEPS_ROOT}/${runtime_name}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endforeach()

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

if(AVACA_REMOTE_QUIC_ENABLED)
  install(TARGETS avaca_remote_quic_core
    RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
  install(FILES "${AVACA_MSQUIC_DLL}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
endif()

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
