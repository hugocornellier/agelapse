cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_custom_command(
  TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>/blobs"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${TFLITE_SO_FROM_ASSET}" "$<TARGET_FILE_DIR:${BINARY_NAME}>/blobs/libtensorflowlite_c-linux.so"
)