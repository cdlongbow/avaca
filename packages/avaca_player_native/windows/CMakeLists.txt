cmake_minimum_required(VERSION 3.14)
project(avaca_player_native_plugin LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.28)

set(PLUGIN_NAME "avaca_player_native_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/avaca_player_native/avaca_player_native_plugin.h"
  "avaca_player_native_plugin.cpp"
  "avaca_windows_player_contract.cc"
  "avaca_windows_player_session.cpp"
  "avaca_windows_player_session.h"
  "angle_abi.h"
  "mpv_abi.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  NOMINMAX
  WIN32_LEAN_AND_MEAN
)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  d3d11.lib
  dxgi.lib
  ole32.lib
  user32.lib
)

# The Windows player is a shipped product path, not a source-only contract.
# The release workflow stages the pinned LGPL libmpv archive into this same
# engine directory before configuring Flutter.  Keeping the default here
# makes a local release build and CI use the identical adjacent-DLL closure.
if(DEFINED AVACA_WINDOWS_PLAYER_DEPS_ROOT)
  set(_avaca_default_player_deps_root "${AVACA_WINDOWS_PLAYER_DEPS_ROOT}")
else()
  set(_avaca_default_player_deps_root
      "${CMAKE_CURRENT_SOURCE_DIR}/../../../windows/engine")
endif()
set(AVACA_PLAYER_NATIVE_DEPS_ROOT
    "${_avaca_default_player_deps_root}" CACHE PATH
    "Pinned AVACA Windows player dependency root" FORCE)
set(AVACA_PLAYER_NATIVE_STRICT_DEPS ON CACHE BOOL
    "Fail configuration when the pinned AVACA player runtime is absent" FORCE)
set(AVACA_PLAYER_NATIVE_MPV_DEV_ROOT "" CACHE PATH
    "Optional local libmpv development root for diagnostics")

if(AVACA_PLAYER_NATIVE_STRICT_DEPS AND
   NOT EXISTS "${AVACA_PLAYER_NATIVE_DEPS_ROOT}")
  message(FATAL_ERROR
    "AVACA_PLAYER_NATIVE_STRICT_DEPS requires AVACA_PLAYER_NATIVE_DEPS_ROOT")
endif()

if(AVACA_PLAYER_NATIVE_DEPS_ROOT)
  foreach(runtime_name
      libmpv-2.dll
      libEGL.dll
      libGLESv2.dll
      d3dcompiler_47.dll
      vk_swiftshader.dll
      vulkan-1.dll)
    if(EXISTS "${AVACA_PLAYER_NATIVE_DEPS_ROOT}/${runtime_name}")
      add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${AVACA_PLAYER_NATIVE_DEPS_ROOT}/${runtime_name}"
          "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/${runtime_name}")
    elseif(AVACA_PLAYER_NATIVE_STRICT_DEPS)
      message(FATAL_ERROR
        "Missing AVACA player runtime file: ${runtime_name}")
    endif()
  endforeach()
endif()

if(AVACA_PLAYER_NATIVE_MPV_DEV_ROOT)
  if(EXISTS "${AVACA_PLAYER_NATIVE_MPV_DEV_ROOT}/libmpv-2.dll")
    add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${AVACA_PLAYER_NATIVE_MPV_DEV_ROOT}/libmpv-2.dll"
        "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libmpv-2.dll")
  endif()
endif()

set(avaca_player_native_bundled_libraries
  ""
  PARENT_SCOPE
)
