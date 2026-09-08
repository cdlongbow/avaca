cmake_minimum_required(VERSION 3.14)
project(avaca_remote_core LANGUAGES CXX)

add_library(avaca_remote_core INTERFACE)
target_include_directories(avaca_remote_core INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}")

add_library(avaca_remote_discovery STATIC
  "avaca_windows_discovery.cpp"
  "include/avaca_remote_core/avaca_windows_discovery.h")
target_compile_features(avaca_remote_discovery PRIVATE cxx_std_17)
target_compile_definitions(avaca_remote_discovery PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(avaca_remote_discovery PRIVATE /W4 /WX /EHsc /wd4100)
target_include_directories(avaca_remote_discovery PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(avaca_remote_discovery PRIVATE dnsapi.lib)
target_link_libraries(avaca_remote_core INTERFACE avaca_remote_discovery)

if(AVACA_REMOTE_QUIC_ENABLED)
  if(NOT MSVC)
    message(FATAL_ERROR "AVACA MsQuic remote core requires MSVC on Windows")
  endif()
  add_library(avaca_remote_quic_core SHARED
    "remote_quic_bridge.cpp"
  )
  target_compile_features(avaca_remote_quic_core PRIVATE cxx_std_17)
  target_compile_definitions(avaca_remote_quic_core PRIVATE
    NOMINMAX QUIC_API_ENABLE_PREVIEW_FEATURES _HAS_EXCEPTIONS=0)
  target_compile_options(avaca_remote_quic_core PRIVATE
    /W4 /WX /EHsc /wd4100 /wd4201 /wd4214)
  target_include_directories(avaca_remote_quic_core PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${AVACA_MSQUIC_ROOT}/src/inc")
  target_link_libraries(avaca_remote_quic_core PRIVATE
    bcrypt.lib crypt32.lib ncrypt.lib ole32.lib ws2_32.lib)
endif()
