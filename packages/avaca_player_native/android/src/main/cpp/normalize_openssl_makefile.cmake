if(NOT DEFINED OPENSSL_MAKEFILE OR NOT DEFINED OPENSSL_SOURCE OR NOT DEFINED OPENSSL_BUILD)
  message(FATAL_ERROR
    "normalize_openssl_makefile.cmake requires OPENSSL_MAKEFILE, OPENSSL_SOURCE, and OPENSSL_BUILD")
endif()

file(TO_CMAKE_PATH "${OPENSSL_SOURCE}" _openssl_source)
file(TO_CMAKE_PATH "${OPENSSL_BUILD}" _openssl_build)
file(RELATIVE_PATH _openssl_relative_source
  "${_openssl_build}"
  "${_openssl_source}")
file(TO_CMAKE_PATH "${_openssl_relative_source}" _openssl_relative_source)

file(READ "${OPENSSL_MAKEFILE}" _openssl_makefile)
string(FIND "${_openssl_makefile}" "${_openssl_relative_source}" _source_index)
if(_source_index LESS 0)
  message(FATAL_ERROR
    "Generated OpenSSL Makefile does not contain its expected source prefix: ${_openssl_relative_source}")
endif()

string(REPLACE
  "${_openssl_relative_source}"
  "${_openssl_source}"
  _openssl_makefile
  "${_openssl_makefile}")
file(WRITE "${OPENSSL_MAKEFILE}" "${_openssl_makefile}")
message(STATUS
  "Normalized OpenSSL Makefile source prefix to ${_openssl_source}")
