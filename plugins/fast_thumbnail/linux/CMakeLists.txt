cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "fast_thumbnail")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "fast_thumbnail_plugin")

# libjpeg-turbo for fast JPEG decode/encode
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBJPEG_TURBO REQUIRED IMPORTED_TARGET libturbojpeg)

list(APPEND PLUGIN_SOURCES
  "fast_thumbnail_plugin.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::LIBJPEG_TURBO)

set(fast_thumbnail_bundled_libraries
  ""
  PARENT_SCOPE
)
