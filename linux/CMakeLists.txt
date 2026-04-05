cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

set(BINARY_NAME "agelapse")
set(APPLICATION_ID "com.hugocornellier.agelapse")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib:$ORIGIN/../lib:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/lib/aarch64-linux-gnu")

if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
endif()

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
add_subdirectory("runner")

add_dependencies(${BINARY_NAME} flutter_assemble)

set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)

include(flutter/generated_plugins.cmake)

set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

install(CODE "file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")" COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")
set(INSTALL_BUNDLE_BLOBS_DIR "${CMAKE_INSTALL_PREFIX}/blobs")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endforeach()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}/native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

install(CODE "file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")" COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Strip unused TFLite models and sample images from plugin assets.
# These files are bundled by pub.dev plugins but never loaded at runtime
# for AgeLapse's specific configuration. Removing them saves ~24 MB.
# See strip-savings.md for the full audit.
set(_STRIP_FLUTTER_ASSETS_DIR "${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}")
set(_STRIP_FILES
  # face_detection_tflite: unused detection model variants (AgeLapse only uses backCamera)
  "packages/face_detection_tflite/assets/models/selfie_multiclass.tflite"
  "packages/face_detection_tflite/assets/models/face_detection_full_range.tflite"
  "packages/face_detection_tflite/assets/models/face_detection_full_range_sparse.tflite"
  "packages/face_detection_tflite/assets/models/selfie_segmenter_landscape.tflite"
  "packages/face_detection_tflite/assets/models/selfie_segmenter.tflite"
  "packages/face_detection_tflite/assets/models/face_detection_front.tflite"
  "packages/face_detection_tflite/assets/models/face_detection_short_range.tflite"
  # pose_detection: unused landmark variant (AgeLapse only uses heavy)
  "packages/pose_detection/assets/models/pose_landmark_full.tflite"
)
install(CODE "
  foreach(_f ${_STRIP_FILES})
    set(_path \"${_STRIP_FLUTTER_ASSETS_DIR}/\${_f}\")
    if(EXISTS \"\${_path}\")
      file(SIZE \"\${_path}\" _sz)
      math(EXPR _kb \"\${_sz} / 1024\")
      message(STATUS \"Stripping unused asset: \${_f} (\${_kb} KB)\")
      file(REMOVE \"\${_path}\")
    endif()
  endforeach()
  # Strip plugin sample images (not used by AgeLapse)
  foreach(_dir
    \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/pose_detection/assets/samples\"
    \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/dog_detection/assets/samples\"
    \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/animal_detection/assets/samples\"
  )
    if(IS_DIRECTORY \"\${_dir}\")
      message(STATUS \"Stripping unused sample dir: \${_dir}\")
      file(REMOVE_RECURSE \"\${_dir}\")
    endif()
  endforeach()
  # Strip web-only plugin assets (never loaded on native platforms)
  foreach(_dir
    \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/flutter_avif_web\"
    \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/media_kit/assets/web\"
  )
    if(IS_DIRECTORY \"\${_dir}\")
      message(STATUS \"Stripping web-only asset dir: \${_dir}\")
      file(REMOVE_RECURSE \"\${_dir}\")
    endif()
  endforeach()
  foreach(_wf \"${_STRIP_FLUTTER_ASSETS_DIR}/packages/wakelock_plus/assets/no_sleep.js\")
    if(EXISTS \"\${_wf}\")
      file(REMOVE \"\${_wf}\")
    endif()
  endforeach()
  " COMPONENT Runtime)

if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()
