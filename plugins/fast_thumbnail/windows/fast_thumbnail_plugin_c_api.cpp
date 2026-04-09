#include "include/fast_thumbnail/fast_thumbnail_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fast_thumbnail_plugin.h"

void FastThumbnailPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fast_thumbnail::FastThumbnailPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
