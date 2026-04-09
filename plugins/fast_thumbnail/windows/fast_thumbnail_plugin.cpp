#include "fast_thumbnail_plugin.h"

#define NOMINMAX
#include <windows.h>
#include <wincodec.h>
#include <wincodecsdk.h>
#include <propvarutil.h>
#include <commctrl.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <sstream>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "propsys.lib")

namespace fast_thumbnail {

namespace {

std::wstring Utf8ToWide(const std::string &str) {
  if (str.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(),
                                 static_cast<int>(str.size()), nullptr, 0);
  if (size == 0) return std::wstring();
  std::wstring result(size, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()),
                      &result[0], size);
  return result;
}

// Read EXIF orientation from WIC metadata. Returns 1 (normal) on failure.
UINT16 ReadExifOrientation(IWICBitmapFrameDecode *frame) {
  IWICMetadataQueryReader *reader = nullptr;
  if (FAILED(frame->GetMetadataQueryReader(&reader))) return 1;

  PROPVARIANT var;
  PropVariantInit(&var);
  UINT16 orientation = 1;

  // Try App1/IFD0 EXIF path first (JPEG), then bare /ifd path
  const wchar_t *paths[] = {
    L"/app1/ifd/{ushort=274}",
    L"/ifd/{ushort=274}",
  };
  for (auto path : paths) {
    if (SUCCEEDED(reader->GetMetadataByName(path, &var))) {
      if (var.vt == VT_UI2) {
        orientation = var.uiVal;
        PropVariantClear(&var);
        break;
      }
      PropVariantClear(&var);
    }
  }

  reader->Release();
  return orientation;
}

}  // namespace

// static
void FastThumbnailPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "fast_thumbnail",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FastThumbnailPlugin>();

  // Grab the Flutter window handle for main-thread result posting.
  plugin->flutter_window_ = registrar->GetView()->GetNativeWindow();

  SetWindowSubclass(plugin->flutter_window_, ResultSubclassProc,
                    reinterpret_cast<UINT_PTR>(plugin.get()),
                    reinterpret_cast<DWORD_PTR>(plugin.get()));

  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FastThumbnailPlugin::FastThumbnailPlugin() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  worker_thread_ = std::thread(&FastThumbnailPlugin::WorkerLoop, this);
}

FastThumbnailPlugin::~FastThumbnailPlugin() {
  {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    shutting_down_ = true;
  }
  queue_cv_.notify_all();
  if (worker_thread_.joinable()) worker_thread_.join();

  if (flutter_window_) {
    RemoveWindowSubclass(flutter_window_, ResultSubclassProc,
                         reinterpret_cast<UINT_PTR>(this));
  }
  CoUninitialize();
}

void FastThumbnailPlugin::WorkerLoop() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  while (true) {
    std::function<void()> task;
    {
      std::unique_lock<std::mutex> lock(queue_mutex_);
      queue_cv_.wait(lock, [this] {
        return !work_queue_.empty() || shutting_down_;
      });
      if (shutting_down_ && work_queue_.empty()) break;
      task = std::move(work_queue_.front());
      work_queue_.pop();
    }
    task();
  }
  CoUninitialize();
}

void FastThumbnailPlugin::PostResultToMainThread(std::function<void()> callback) {
  {
    std::unique_lock<std::mutex> lock(result_mutex_);
    result_queue_.push(std::move(callback));
  }
  if (flutter_window_) {
    PostMessage(flutter_window_, WM_FAST_THUMBNAIL_RESULT, 0, 0);
  }
}

// static
LRESULT CALLBACK FastThumbnailPlugin::ResultSubclassProc(
    HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR ref_data) {
  if (msg == WM_FAST_THUMBNAIL_RESULT) {
    auto *plugin = reinterpret_cast<FastThumbnailPlugin *>(ref_data);
    std::queue<std::function<void()>> pending;
    {
      std::unique_lock<std::mutex> lock(plugin->result_mutex_);
      std::swap(pending, plugin->result_queue_);
    }
    while (!pending.empty()) {
      pending.front()();
      pending.pop();
    }
    return 0;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

void FastThumbnailPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() != "generate") {
    result->NotImplemented();
    return;
  }

  const auto *args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("INVALID_ARGS", "Expected map arguments");
    return;
  }

  auto get_string = [&](const std::string &key) -> std::string {
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return "";
    const auto *s = std::get_if<std::string>(&it->second);
    return s ? *s : "";
  };
  auto get_int = [&](const std::string &key, int def) -> int {
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return def;
    const auto *v = std::get_if<int32_t>(&it->second);
    return v ? static_cast<int>(*v) : def;
  };

  std::string input_path = get_string("inputPath");
  std::string output_path = get_string("outputPath");
  int max_width = get_int("maxWidth", 500);
  int quality = get_int("quality", 90);

  if (input_path.empty() || output_path.empty()) {
    result->Error("INVALID_ARGS", "Missing inputPath or outputPath");
    return;
  }

  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));

  {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    work_queue_.push([this, input_path, output_path, max_width, quality,
                      shared_result]() {
      int orig_w = 0, orig_h = 0;
      bool ok = GenerateThumbnail(input_path, output_path, max_width, quality,
                                  orig_w, orig_h);
      PostResultToMainThread([ok, orig_w, orig_h, shared_result]() {
        if (ok) {
          flutter::EncodableMap map;
          map[flutter::EncodableValue("originalWidth")] =
              flutter::EncodableValue(orig_w);
          map[flutter::EncodableValue("originalHeight")] =
              flutter::EncodableValue(orig_h);
          shared_result->Success(flutter::EncodableValue(map));
        } else {
          shared_result->Success(flutter::EncodableValue());  // null
        }
      });
    });
  }
  queue_cv_.notify_one();
}

bool FastThumbnailPlugin::GenerateThumbnail(
    const std::string &input_path, const std::string &output_path,
    int max_width, int quality,
    int &out_orig_width, int &out_orig_height) {

  IWICImagingFactory *factory = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_IWICImagingFactory,
                                reinterpret_cast<void **>(&factory));
  if (FAILED(hr)) return false;

  std::wstring wide_input = Utf8ToWide(input_path);
  IWICBitmapDecoder *decoder = nullptr;
  hr = factory->CreateDecoderFromFilename(wide_input.c_str(), nullptr,
                                          GENERIC_READ,
                                          WICDecodeMetadataCacheOnLoad,
                                          &decoder);
  if (FAILED(hr)) { factory->Release(); return false; }

  IWICBitmapFrameDecode *frame = nullptr;
  hr = decoder->GetFrame(0, &frame);
  if (FAILED(hr)) { decoder->Release(); factory->Release(); return false; }

  UINT raw_w = 0, raw_h = 0;
  frame->GetSize(&raw_w, &raw_h);

  UINT16 orientation = ReadExifOrientation(frame);
  bool is_rotated = (orientation >= 5 && orientation <= 8);
  out_orig_width = static_cast<int>(is_rotated ? raw_h : raw_w);
  out_orig_height = static_cast<int>(is_rotated ? raw_w : raw_h);

  // Build the transform chain: auto-rotate then scale
  IWICBitmapSource *source = frame;
  source->AddRef();

  // Apply EXIF orientation via WICBitmapTransformOptions
  WICBitmapTransformOptions transform = WICBitmapTransformRotate0;
  switch (orientation) {
    case 2: transform = WICBitmapTransformFlipHorizontal; break;
    case 3: transform = WICBitmapTransformRotate180; break;
    case 4: transform = WICBitmapTransformFlipVertical; break;
    case 5: transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal); break;
    case 6: transform = WICBitmapTransformRotate90; break;
    case 7: transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal); break;
    case 8: transform = WICBitmapTransformRotate270; break;
    default: transform = WICBitmapTransformRotate0; break;
  }

  IWICBitmapFlipRotator *rotator = nullptr;
  if (transform != WICBitmapTransformRotate0) {
    factory->CreateBitmapFlipRotator(&rotator);
    if (rotator) {
      rotator->Initialize(source, transform);
      source->Release();
      source = rotator;
      rotator = nullptr;
    }
  }

  // Get post-rotation size
  UINT rot_w = 0, rot_h = 0;
  source->GetSize(&rot_w, &rot_h);

  // Scale so width <= max_width, preserving aspect ratio
  UINT target_w = rot_w, target_h = rot_h;
  if (rot_w > static_cast<UINT>(max_width)) {
    target_w = static_cast<UINT>(max_width);
    target_h = static_cast<UINT>(static_cast<double>(rot_h) * max_width / rot_w + 0.5);
    if (target_h == 0) target_h = 1;
  }

  IWICBitmapScaler *scaler = nullptr;
  factory->CreateBitmapScaler(&scaler);
  if (!scaler) { source->Release(); decoder->Release(); factory->Release(); return false; }
  hr = scaler->Initialize(source, target_w, target_h, WICBitmapInterpolationModeFant);
  source->Release();
  if (FAILED(hr)) { scaler->Release(); decoder->Release(); factory->Release(); return false; }

  // Convert to 24bpp BGR for JPEG encoding
  IWICFormatConverter *converter = nullptr;
  factory->CreateFormatConverter(&converter);
  if (!converter) { scaler->Release(); decoder->Release(); factory->Release(); return false; }
  hr = converter->Initialize(scaler, GUID_WICPixelFormat24bppBGR,
                              WICBitmapDitherTypeNone, nullptr, 0.0,
                              WICBitmapPaletteTypeCustom);
  scaler->Release();
  if (FAILED(hr)) { converter->Release(); decoder->Release(); factory->Release(); return false; }

  // Encode to JPEG
  std::wstring wide_output = Utf8ToWide(output_path);
  IWICStream *out_stream = nullptr;
  factory->CreateStream(&out_stream);
  if (!out_stream) { converter->Release(); decoder->Release(); factory->Release(); return false; }
  out_stream->InitializeFromFilename(wide_output.c_str(), GENERIC_WRITE);

  IWICBitmapEncoder *encoder = nullptr;
  factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder);
  if (!encoder) { out_stream->Release(); converter->Release(); decoder->Release(); factory->Release(); return false; }
  hr = encoder->Initialize(out_stream, WICBitmapEncoderNoCache);
  if (FAILED(hr)) { encoder->Release(); out_stream->Release(); converter->Release(); decoder->Release(); factory->Release(); return false; }

  IWICBitmapFrameEncode *enc_frame = nullptr;
  IPropertyBag2 *props = nullptr;
  encoder->CreateNewFrame(&enc_frame, &props);

  if (enc_frame && props) {
    // Set JPEG quality
    PROPBAG2 opt = {};
    opt.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
    VARIANT val;
    VariantInit(&val);
    val.vt = VT_R4;
    val.fltVal = static_cast<float>(quality) / 100.0f;
    props->Write(1, &opt, &val);
    VariantClear(&val);

    enc_frame->Initialize(props);
    enc_frame->SetSize(target_w, target_h);
    WICPixelFormatGUID fmt = GUID_WICPixelFormat24bppBGR;
    enc_frame->SetPixelFormat(&fmt);
    enc_frame->WriteSource(converter, nullptr);
    enc_frame->Commit();
    encoder->Commit();
  }

  if (props) props->Release();
  if (enc_frame) enc_frame->Release();
  encoder->Release();
  out_stream->Release();
  converter->Release();
  frame->Release();
  decoder->Release();
  factory->Release();

  return true;
}

}  // namespace fast_thumbnail
