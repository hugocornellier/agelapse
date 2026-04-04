cmake_minimum_required(VERSION 3.14)
project(agelapse LANGUAGES CXX)

set(BINARY_NAME "agelapse")

cmake_policy(VERSION 3.14...3.25)

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

set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

add_definitions(-DUNICODE -D_UNICODE)

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

add_subdirectory("runner")

include(flutter/generated_plugins.cmake)

set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

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
  " COMPONENT Runtime)

install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
