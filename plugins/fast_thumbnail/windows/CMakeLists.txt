cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "fast_thumbnail")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "fast_thumbnail_plugin")

list(APPEND PLUGIN_SOURCES
  "fast_thumbnail_plugin.cpp"
  "fast_thumbnail_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/fast_thumbnail/fast_thumbnail_plugin_c_api.h"
  "fast_thumbnail_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL _CRT_SECURE_NO_WARNINGS)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  windowscodecs
  comctl32
  propsys
)

set(fast_thumbnail_bundled_libraries
  ""
  PARENT_SCOPE
)
