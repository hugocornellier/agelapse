//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <camera_desktop/camera_desktop_plugin.h>
#include <cat_detection/cat_detection_plugin.h>
#include <desktop_drop/desktop_drop_plugin.h>
#include <dog_detection/dog_detection_plugin.h>
#include <face_detection_tflite/face_detection_tflite_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <flutter_avif_linux/flutter_avif_linux_plugin.h>
#include <flutter_timezone/flutter_timezone_plugin.h>
#include <heic2png/heic2png_plugin.h>
#include <media_kit_libs_linux/media_kit_libs_linux_plugin.h>
#include <media_kit_video/media_kit_video_plugin.h>
#include <pose_detection/pose_detection_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <sqlite3_flutter_libs/sqlite3_flutter_libs_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) camera_desktop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CameraDesktopPlugin");
  camera_desktop_plugin_register_with_registrar(camera_desktop_registrar);
  g_autoptr(FlPluginRegistrar) cat_detection_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CatDetectionPlugin");
  cat_detection_plugin_register_with_registrar(cat_detection_registrar);
  g_autoptr(FlPluginRegistrar) desktop_drop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DesktopDropPlugin");
  desktop_drop_plugin_register_with_registrar(desktop_drop_registrar);
  g_autoptr(FlPluginRegistrar) dog_detection_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DogDetectionPlugin");
  dog_detection_plugin_register_with_registrar(dog_detection_registrar);
  g_autoptr(FlPluginRegistrar) face_detection_tflite_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FaceDetectionTflitePlugin");
  face_detection_tflite_plugin_register_with_registrar(face_detection_tflite_registrar);
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_avif_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterAvifLinuxPlugin");
  flutter_avif_linux_plugin_register_with_registrar(flutter_avif_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_timezone_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterTimezonePlugin");
  flutter_timezone_plugin_register_with_registrar(flutter_timezone_registrar);
  g_autoptr(FlPluginRegistrar) heic2png_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Heic2pngPlugin");
  heic2png_plugin_register_with_registrar(heic2png_registrar);
  g_autoptr(FlPluginRegistrar) media_kit_libs_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MediaKitLibsLinuxPlugin");
  media_kit_libs_linux_plugin_register_with_registrar(media_kit_libs_linux_registrar);
  g_autoptr(FlPluginRegistrar) media_kit_video_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MediaKitVideoPlugin");
  media_kit_video_plugin_register_with_registrar(media_kit_video_registrar);
  g_autoptr(FlPluginRegistrar) pose_detection_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PoseDetectionPlugin");
  pose_detection_plugin_register_with_registrar(pose_detection_registrar);
  g_autoptr(FlPluginRegistrar) screen_retriever_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ScreenRetrieverLinuxPlugin");
  screen_retriever_linux_plugin_register_with_registrar(screen_retriever_linux_registrar);
  g_autoptr(FlPluginRegistrar) sqlite3_flutter_libs_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Sqlite3FlutterLibsPlugin");
  sqlite3_flutter_libs_plugin_register_with_registrar(sqlite3_flutter_libs_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
  g_autoptr(FlPluginRegistrar) window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(window_manager_registrar);
}
