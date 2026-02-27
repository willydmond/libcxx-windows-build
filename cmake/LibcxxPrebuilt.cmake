include_guard(GLOBAL)

include(CMakeParseArguments)

function(_libcxx_prebuilt_detect_host_arch out_host_os out_arch)
  if(WIN32)
    set(_host_os "windows")
  elseif(UNIX)
    set(_host_os "linux")
  else()
    message(FATAL_ERROR "Unsupported host OS for libcxx prebuilt import")
  endif()

  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)
  if(_proc MATCHES "^(x86_64|amd64)$")
    set(_arch "x64")
  elseif(_proc MATCHES "^(aarch64|arm64)$")
    set(_arch "arm64")
  else()
    message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
  endif()

  set(${out_host_os} "${_host_os}" PARENT_SCOPE)
  set(${out_arch} "${_arch}" PARENT_SCOPE)
endfunction()

function(libcxx_prebuilt_import)
  set(options FORCE_DOWNLOAD)
  set(oneValueArgs TARGET OWNER REPO LLVM_TAG ABI_NAMESPACE HOST_OS ARCH CONFIG RELEASE_TAG DOWNLOAD_DIR EXTRACT_DIR)
  cmake_parse_arguments(LPX "${options}" "${oneValueArgs}" "" ${ARGN})

  if(NOT LPX_TARGET)
    set(LPX_TARGET "libcxx_prebuilt::runtime")
  endif()
  if(NOT LPX_OWNER)
    set(LPX_OWNER "willydmond")
  endif()
  if(NOT LPX_REPO)
    set(LPX_REPO "libcxx-windows-build")
  endif()
  if(NOT LPX_ABI_NAMESPACE)
    set(LPX_ABI_NAMESPACE "__Cr")
  endif()
  if(NOT LPX_CONFIG)
    set(LPX_CONFIG "Release")
  endif()

  if(NOT LPX_HOST_OS OR NOT LPX_ARCH)
    _libcxx_prebuilt_detect_host_arch(_detected_os _detected_arch)
    if(NOT LPX_HOST_OS)
      set(LPX_HOST_OS "${_detected_os}")
    endif()
    if(NOT LPX_ARCH)
      set(LPX_ARCH "${_detected_arch}")
    endif()
  endif()

  if(NOT LPX_LLVM_TAG)
    message(FATAL_ERROR "libcxx_prebuilt_import requires LLVM_TAG, e.g. llvmorg-22.1.0")
  endif()

  if(NOT LPX_RELEASE_TAG)
    set(LPX_RELEASE_TAG "libcxx-${LPX_LLVM_TAG}")
  endif()

  set(_asset "libcxx-prebuilt-${LPX_HOST_OS}-${LPX_ARCH}-${LPX_CONFIG}-${LPX_LLVM_TAG}-${LPX_ABI_NAMESPACE}.zip")

  if(NOT LPX_DOWNLOAD_DIR)
    set(LPX_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_deps/libcxx-prebuilt/downloads")
  endif()
  if(NOT LPX_EXTRACT_DIR)
    set(LPX_EXTRACT_DIR "${CMAKE_BINARY_DIR}/_deps/libcxx-prebuilt/${LPX_HOST_OS}-${LPX_ARCH}-${LPX_CONFIG}-${LPX_LLVM_TAG}")
  endif()

  file(MAKE_DIRECTORY "${LPX_DOWNLOAD_DIR}")
  file(MAKE_DIRECTORY "${LPX_EXTRACT_DIR}")

  set(_zip "${LPX_DOWNLOAD_DIR}/${_asset}")
  set(_url "https://github.com/${LPX_OWNER}/${LPX_REPO}/releases/download/${LPX_RELEASE_TAG}/${_asset}")

  if(LPX_FORCE_DOWNLOAD OR NOT EXISTS "${_zip}")
    message(STATUS "Downloading ${_url}")
    file(DOWNLOAD
      "${_url}"
      "${_zip}"
      SHOW_PROGRESS
      TLS_VERIFY ON
      STATUS _dl_status
    )
    list(GET _dl_status 0 _dl_code)
    if(NOT _dl_code EQUAL 0)
      list(GET _dl_status 1 _dl_msg)
      message(FATAL_ERROR "Failed to download ${_url}: ${_dl_msg}")
    endif()
  endif()

  set(_marker "${LPX_EXTRACT_DIR}/.extract_done")
  if(LPX_FORCE_DOWNLOAD OR NOT EXISTS "${_marker}")
    file(REMOVE_RECURSE "${LPX_EXTRACT_DIR}")
    file(MAKE_DIRECTORY "${LPX_EXTRACT_DIR}")
    file(ARCHIVE_EXTRACT INPUT "${_zip}" DESTINATION "${LPX_EXTRACT_DIR}")
    file(WRITE "${_marker}" "ok\n")
  endif()

  set(_include_dir "${LPX_EXTRACT_DIR}/include/c++/v1")
  set(_lib_dir "${LPX_EXTRACT_DIR}/lib")
  if(NOT EXISTS "${_include_dir}")
    message(FATAL_ERROR "Invalid prebuilt package: missing ${_include_dir}")
  endif()

  set(_libs)
  if(LPX_HOST_OS STREQUAL "windows")
    foreach(_cand c++.lib libc++.lib)
      if(EXISTS "${_lib_dir}/${_cand}")
        list(APPEND _libs "${_lib_dir}/${_cand}")
      endif()
    endforeach()
  else()
    foreach(_cand libc++.a libc++.so libc++.so.1 libc++abi.a libunwind.a)
      if(EXISTS "${_lib_dir}/${_cand}")
        list(APPEND _libs "${_lib_dir}/${_cand}")
      endif()
    endforeach()
  endif()

  if(TARGET ${LPX_TARGET})
    message(STATUS "Target ${LPX_TARGET} already exists; reusing it")
  else()
    add_library(${LPX_TARGET} INTERFACE IMPORTED GLOBAL)
  endif()

  if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    set_target_properties(${LPX_TARGET} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES ""
    )
    set_property(TARGET ${LPX_TARGET} PROPERTY _LIBCXX_PREBUILT_INCLUDE_DIR "${_include_dir}")
  else()
    set_target_properties(${LPX_TARGET} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${_include_dir}"
    )
  endif()

  if(_libs)
    set_property(TARGET ${LPX_TARGET} APPEND PROPERTY INTERFACE_LINK_LIBRARIES "${_libs}")
  else()
    message(WARNING "No runtime library found under ${_lib_dir}; only headers are configured")
  endif()

  set(LIBCXX_PREBUILT_ROOT "${LPX_EXTRACT_DIR}" PARENT_SCOPE)
  set(LIBCXX_PREBUILT_INCLUDE_DIR "${_include_dir}" PARENT_SCOPE)
  set(LIBCXX_PREBUILT_LIB_DIR "${_lib_dir}" PARENT_SCOPE)
endfunction()

function(libcxx_prebuilt_enable_for_target target imported_target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "Target '${target}' does not exist")
  endif()
  if(NOT TARGET ${imported_target})
    message(FATAL_ERROR "Imported target '${imported_target}' does not exist")
  endif()

  target_link_libraries(${target} PRIVATE ${imported_target})

  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
      get_target_property(_libcxx_inc ${imported_target} _LIBCXX_PREBUILT_INCLUDE_DIR)
      if(_libcxx_inc)
        target_compile_options(${target} PRIVATE
          "SHELL:/clang:-isystem /clang:${_libcxx_inc}"
        )
      endif()
    else()
      target_compile_options(${target} PRIVATE -nostdinc++)
      target_link_options(${target} PRIVATE -nostdlib++)
    endif()
  endif()
endfunction()
