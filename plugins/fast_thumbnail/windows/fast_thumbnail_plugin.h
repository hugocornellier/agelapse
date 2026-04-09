#ifndef FLUTTER_PLUGIN_FAST_THUMBNAIL_PLUGIN_H_
#define FLUTTER_PLUGIN_FAST_THUMBNAIL_PLUGIN_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <functional>
#include <atomic>

namespace fast_thumbnail {

class FastThumbnailPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FastThumbnailPlugin();

  virtual ~FastThumbnailPlugin();

  FastThumbnailPlugin(const FastThumbnailPlugin&) = delete;
  FastThumbnailPlugin& operator=(const FastThumbnailPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  bool GenerateThumbnail(const std::string &input_path,
                         const std::string &output_path,
                         int max_width, int quality,
                         int &out_orig_width, int &out_orig_height);

  std::thread worker_thread_;
  std::mutex queue_mutex_;
  std::condition_variable queue_cv_;
  std::queue<std::function<void()>> work_queue_;
  std::atomic<bool> shutting_down_{false};

  HWND flutter_window_{nullptr};
  static constexpr UINT WM_FAST_THUMBNAIL_RESULT = WM_APP + 1;
  std::mutex result_mutex_;
  std::queue<std::function<void()>> result_queue_;

  void WorkerLoop();
  void PostResultToMainThread(std::function<void()> callback);
  static LRESULT CALLBACK ResultSubclassProc(HWND, UINT, WPARAM, LPARAM,
                                              UINT_PTR, DWORD_PTR);
};

}  // namespace fast_thumbnail

#endif  // FLUTTER_PLUGIN_FAST_THUMBNAIL_PLUGIN_H_
