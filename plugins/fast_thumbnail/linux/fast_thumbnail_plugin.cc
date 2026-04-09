#include "include/fast_thumbnail/fast_thumbnail_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

// libjpeg-turbo for fast JPEG decode + encode
#include <turbojpeg.h>

#define FAST_THUMBNAIL_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), fast_thumbnail_plugin_get_type(), \
                              FastThumbnailPlugin))

struct _FastThumbnailPlugin {
  GObject parent_instance;
  GAsyncQueue* work_queue;
  GThread* worker_thread;
  gboolean disposed;
};

G_DEFINE_TYPE(FastThumbnailPlugin, fast_thumbnail_plugin, g_object_get_type())

// Work item passed to background thread.
struct WorkItem {
  char* input_path;
  char* output_path;
  int max_width;
  int quality;
  FlMethodCall* method_call;
  bool shutdown;
};

// Result posted back to main thread via g_idle_add.
struct ResultDelivery {
  FlMethodCall* method_call;
  FlMethodResponse* response;
  FastThumbnailPlugin* plugin;
};

static gboolean deliver_result_idle(gpointer data) {
  auto* d = reinterpret_cast<ResultDelivery*>(data);
  if (!d->plugin->disposed) {
    fl_method_call_respond(d->method_call, d->response, nullptr);
  }
  g_object_unref(d->method_call);
  g_object_unref(d->response);
  g_object_unref(d->plugin);
  delete d;
  return G_SOURCE_REMOVE;
}

// Read EXIF orientation tag (0x0112) from JPEG file header.
// Returns 1 (normal) on failure.
static int read_jpeg_exif_orientation(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) return 1;

  // Read enough of the file to find APP1/EXIF
  uint8_t buf[65536];
  size_t n = fread(buf, 1, sizeof(buf), f);
  fclose(f);
  if (n < 4) return 1;

  // Must start with JPEG SOI marker FF D8
  if (buf[0] != 0xFF || buf[1] != 0xD8) return 1;

  size_t pos = 2;
  while (pos + 4 <= n) {
    if (buf[pos] != 0xFF) break;
    uint8_t marker = buf[pos + 1];
    if (marker == 0xDA) break;  // SOS — image data starts
    uint16_t seg_len = (static_cast<uint16_t>(buf[pos + 2]) << 8) | buf[pos + 3];
    if (seg_len < 2) break;

    // APP1 marker = 0xE1, contains Exif or XMP
    if (marker == 0xE1 && pos + 4 + 6 <= n) {
      const uint8_t* seg = buf + pos + 4;
      size_t seg_data_len = seg_len - 2;
      // Check for "Exif\0\0"
      if (seg_data_len >= 6 && memcmp(seg, "Exif\0\0", 6) == 0) {
        const uint8_t* tiff = seg + 6;
        size_t tiff_len = seg_data_len - 6;
        if (tiff_len < 8) { pos += 2 + seg_len; continue; }

        bool little_endian = (tiff[0] == 'I' && tiff[1] == 'I');
        auto read16 = [&](size_t off) -> uint16_t {
          if (off + 2 > tiff_len) return 0;
          if (little_endian)
            return static_cast<uint16_t>(tiff[off]) | (static_cast<uint16_t>(tiff[off+1]) << 8);
          else
            return (static_cast<uint16_t>(tiff[off]) << 8) | static_cast<uint16_t>(tiff[off+1]);
        };
        auto read32 = [&](size_t off) -> uint32_t {
          if (off + 4 > tiff_len) return 0;
          if (little_endian)
            return static_cast<uint32_t>(tiff[off]) |
                   (static_cast<uint32_t>(tiff[off+1]) << 8) |
                   (static_cast<uint32_t>(tiff[off+2]) << 16) |
                   (static_cast<uint32_t>(tiff[off+3]) << 24);
          else
            return (static_cast<uint32_t>(tiff[off]) << 24) |
                   (static_cast<uint32_t>(tiff[off+1]) << 16) |
                   (static_cast<uint32_t>(tiff[off+2]) << 8) |
                   static_cast<uint32_t>(tiff[off+3]);
        };

        uint32_t ifd0_offset = read32(4);
        if (ifd0_offset + 2 > tiff_len) { pos += 2 + seg_len; continue; }

        uint16_t entry_count = read16(ifd0_offset);
        for (uint16_t i = 0; i < entry_count; ++i) {
          size_t entry_off = ifd0_offset + 2 + i * 12;
          if (entry_off + 12 > tiff_len) break;
          uint16_t tag = read16(entry_off);
          if (tag == 0x0112) {
            // Orientation tag, type SHORT (3), count 1, value in next 2 bytes
            uint16_t val = read16(entry_off + 8);
            return static_cast<int>(val);
          }
        }
      }
    }
    pos += 2 + seg_len;
  }
  return 1;
}

static void post_null_result(FastThumbnailPlugin* plugin, FlMethodCall* method_call) {
  FlValue* null_val = fl_value_new_null();
  FlMethodResponse* resp = FL_METHOD_RESPONSE(fl_method_success_response_new(null_val));
  fl_value_unref(null_val);

  auto* d = new ResultDelivery{
    .method_call = FL_METHOD_CALL(g_object_ref(method_call)),
    .response = resp,
    .plugin = FAST_THUMBNAIL_PLUGIN(g_object_ref(plugin)),
  };
  g_idle_add(deliver_result_idle, d);
}

static void process_work_item(FastThumbnailPlugin* plugin, WorkItem* item) {
  const char* input_path = item->input_path;
  const char* output_path = item->output_path;
  int max_width = item->max_width;
  int quality = item->quality;

  int orientation = read_jpeg_exif_orientation(input_path);
  bool is_rotated = (orientation >= 5 && orientation <= 8);

  tjhandle tj_dec = tjInitDecompress();
  if (!tj_dec) { post_null_result(plugin, item->method_call); return; }

  // Read file
  FILE* f = fopen(input_path, "rb");
  if (!f) { tjDestroy(tj_dec); post_null_result(plugin, item->method_call); return; }
  fseek(f, 0, SEEK_END);
  long file_size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (file_size <= 0) { fclose(f); tjDestroy(tj_dec); post_null_result(plugin, item->method_call); return; }

  std::vector<uint8_t> jpeg_buf(file_size);
  if (fread(jpeg_buf.data(), 1, file_size, f) != static_cast<size_t>(file_size)) {
    fclose(f); tjDestroy(tj_dec); post_null_result(plugin, item->method_call); return;
  }
  fclose(f);

  int raw_w = 0, raw_h = 0, subsamp = 0, colorspace = 0;
  if (tjDecompressHeader3(tj_dec, jpeg_buf.data(), jpeg_buf.size(),
                           &raw_w, &raw_h, &subsamp, &colorspace) < 0) {
    tjDestroy(tj_dec); post_null_result(plugin, item->method_call); return;
  }

  int orig_w = is_rotated ? raw_h : raw_w;
  int orig_h = is_rotated ? raw_w : raw_h;

  // Choose scaled size using libjpeg-turbo's built-in JPEG scaling (DCT domain)
  // Available scales: 1/1, 7/8, 3/4, 5/8, 1/2, 3/8, 1/4, 1/8
  tjscalingfactor best_sf = {1, 1};
  int num_sf = 0;
  tjscalingfactor* sfs = tjGetScalingFactors(&num_sf);
  int dec_w = raw_w, dec_h = raw_h;
  if (sfs && num_sf > 0) {
    for (int si = 0; si < num_sf; ++si) {
      int sw = TJSCALED(raw_w, sfs[si]);
      int sh = TJSCALED(raw_h, sfs[si]);
      if (sw >= max_width || si == num_sf - 1) {
        best_sf = sfs[si];
        dec_w = sw;
        dec_h = sh;
        break;
      }
    }
  }

  std::vector<uint8_t> rgb(dec_w * dec_h * 3);
  if (tjDecompress2(tj_dec, jpeg_buf.data(), jpeg_buf.size(),
                     rgb.data(), dec_w, 0, dec_h, TJPF_RGB,
                     TJFLAG_FASTDCT) < 0) {
    tjDestroy(tj_dec); post_null_result(plugin, item->method_call); return;
  }
  tjDestroy(tj_dec);
  jpeg_buf.clear();

  // Apply EXIF rotation manually
  int out_w = dec_w, out_h = dec_h;
  std::vector<uint8_t> rotated;

  auto pixel = [&](const std::vector<uint8_t>& src, int x, int y, int w) -> const uint8_t* {
    return src.data() + (y * w + x) * 3;
  };

  auto rotate_cw90 = [&]() {
    // CW 90: new[x][y] = old[height-1-y][x]
    rotated.resize(dec_h * dec_w * 3);
    out_w = dec_h; out_h = dec_w;
    for (int y = 0; y < dec_h; ++y)
      for (int x = 0; x < dec_w; ++x) {
        const uint8_t* src_px = pixel(rgb, x, dec_h - 1 - y, dec_w);
        uint8_t* dst_px = rotated.data() + (x * out_w + y) * 3;
        dst_px[0] = src_px[0]; dst_px[1] = src_px[1]; dst_px[2] = src_px[2];
      }
  };

  auto rotate_ccw90 = [&]() {
    // CCW 90: new[x][y] = old[y][width-1-x]
    rotated.resize(dec_h * dec_w * 3);
    out_w = dec_h; out_h = dec_w;
    for (int y = 0; y < dec_h; ++y)
      for (int x = 0; x < dec_w; ++x) {
        const uint8_t* src_px = pixel(rgb, dec_w - 1 - x, y, dec_w);
        uint8_t* dst_px = rotated.data() + (x * out_w + (out_h - 1 - y)) * 3;
        dst_px[0] = src_px[0]; dst_px[1] = src_px[1]; dst_px[2] = src_px[2];
      }
  };

  auto rotate_180 = [&]() {
    rotated.resize(dec_w * dec_h * 3);
    out_w = dec_w; out_h = dec_h;
    for (int y = 0; y < dec_h; ++y)
      for (int x = 0; x < dec_w; ++x) {
        const uint8_t* src_px = pixel(rgb, dec_w - 1 - x, dec_h - 1 - y, dec_w);
        uint8_t* dst_px = rotated.data() + (y * out_w + x) * 3;
        dst_px[0] = src_px[0]; dst_px[1] = src_px[1]; dst_px[2] = src_px[2];
      }
  };

  auto flip_horiz = [&]() {
    rotated.resize(dec_w * dec_h * 3);
    out_w = dec_w; out_h = dec_h;
    for (int y = 0; y < dec_h; ++y)
      for (int x = 0; x < dec_w; ++x) {
        const uint8_t* src_px = pixel(rgb, dec_w - 1 - x, y, dec_w);
        uint8_t* dst_px = rotated.data() + (y * out_w + x) * 3;
        dst_px[0] = src_px[0]; dst_px[1] = src_px[1]; dst_px[2] = src_px[2];
      }
  };

  switch (orientation) {
    case 2: flip_horiz(); break;
    case 3: rotate_180(); break;
    case 4: { rotate_180(); std::swap(rgb, rotated); dec_w = out_w; dec_h = out_h; flip_horiz(); } break;
    case 5: { rotate_cw90(); std::swap(rgb, rotated); dec_w = out_w; dec_h = out_h; flip_horiz(); } break;
    case 6: rotate_cw90(); break;
    case 7: { rotate_ccw90(); std::swap(rgb, rotated); dec_w = out_w; dec_h = out_h; flip_horiz(); } break;
    case 8: rotate_ccw90(); break;
    default: break;
  }

  const uint8_t* final_data = rotated.empty() ? rgb.data() : rotated.data();
  int final_w = out_w, final_h = out_h;

  // Scale to max_width if needed (simple bilinear would be ideal; use nearest for speed)
  std::vector<uint8_t> scaled;
  if (final_w > max_width) {
    int scaled_w = max_width;
    int scaled_h = static_cast<int>(static_cast<double>(final_h) * max_width / final_w + 0.5);
    if (scaled_h < 1) scaled_h = 1;
    scaled.resize(scaled_w * scaled_h * 3);
    for (int y = 0; y < scaled_h; ++y) {
      int src_y = static_cast<int>(static_cast<double>(y) * final_h / scaled_h);
      if (src_y >= final_h) src_y = final_h - 1;
      for (int x = 0; x < scaled_w; ++x) {
        int src_x = static_cast<int>(static_cast<double>(x) * final_w / scaled_w);
        if (src_x >= final_w) src_x = final_w - 1;
        const uint8_t* s = final_data + (src_y * final_w + src_x) * 3;
        uint8_t* d = scaled.data() + (y * scaled_w + x) * 3;
        d[0] = s[0]; d[1] = s[1]; d[2] = s[2];
      }
    }
    final_data = scaled.data();
    final_w = scaled_w;
    final_h = scaled_h;
  }

  // Encode to JPEG
  tjhandle tj_enc = tjInitCompress();
  if (!tj_enc) { post_null_result(plugin, item->method_call); return; }

  uint8_t* out_buf = nullptr;
  unsigned long out_size = 0;
  int rc = tjCompress2(tj_enc, final_data, final_w, 0, final_h, TJPF_RGB,
                        &out_buf, &out_size, TJSAMP_420, quality, TJFLAG_FASTDCT);
  tjDestroy(tj_enc);

  if (rc < 0 || !out_buf) { post_null_result(plugin, item->method_call); return; }

  FILE* out_f = fopen(output_path, "wb");
  if (!out_f) { tjFree(out_buf); post_null_result(plugin, item->method_call); return; }
  fwrite(out_buf, 1, out_size, out_f);
  fclose(out_f);
  tjFree(out_buf);

  // Build success response
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "originalWidth", fl_value_new_int(orig_w));
  fl_value_set_string_take(map, "originalHeight", fl_value_new_int(orig_h));
  FlMethodResponse* resp = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  fl_value_unref(map);

  auto* d = new ResultDelivery{
    .method_call = FL_METHOD_CALL(g_object_ref(item->method_call)),
    .response = resp,
    .plugin = FAST_THUMBNAIL_PLUGIN(g_object_ref(plugin)),
  };
  g_idle_add(deliver_result_idle, d);
}

static gpointer worker_thread_func(gpointer user_data) {
  FastThumbnailPlugin* plugin = FAST_THUMBNAIL_PLUGIN(user_data);
  while (true) {
    WorkItem* item = reinterpret_cast<WorkItem*>(g_async_queue_pop(plugin->work_queue));
    if (item->shutdown) {
      g_object_unref(plugin);
      delete item;
      break;
    }
    process_work_item(plugin, item);
    g_object_unref(item->method_call);
    g_free(item->input_path);
    g_free(item->output_path);
    delete item;
  }
  return nullptr;
}

static void fast_thumbnail_plugin_dispose(GObject* object) {
  FastThumbnailPlugin* self = FAST_THUMBNAIL_PLUGIN(object);
  self->disposed = TRUE;

  WorkItem* shutdown_item = new WorkItem{};
  shutdown_item->shutdown = true;
  g_object_ref(self);
  g_async_queue_push(self->work_queue, shutdown_item);

  if (self->worker_thread) {
    g_thread_join(self->worker_thread);
    self->worker_thread = nullptr;
  }
  g_async_queue_unref(self->work_queue);
  G_OBJECT_CLASS(fast_thumbnail_plugin_parent_class)->dispose(object);
}

static void fast_thumbnail_plugin_class_init(FastThumbnailPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = fast_thumbnail_plugin_dispose;
}

static void fast_thumbnail_plugin_init(FastThumbnailPlugin* self) {
  self->disposed = FALSE;
  self->work_queue = g_async_queue_new();
  g_object_ref(self);
  self->worker_thread = g_thread_new("fast_thumbnail_worker", worker_thread_func, self);
}

static void method_call_handler(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  FastThumbnailPlugin* plugin = FAST_THUMBNAIL_PLUGIN(user_data);

  if (strcmp(fl_method_call_get_name(method_call), "generate") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    FlValue* err = fl_value_new_string("Missing arguments");
    FlMethodResponse* resp = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS", "Missing arguments", err));
    fl_value_unref(err);
    fl_method_call_respond(method_call, resp, nullptr);
    g_object_unref(resp);
    return;
  }

  FlValue* input_v = fl_value_lookup_string(args, "inputPath");
  FlValue* output_v = fl_value_lookup_string(args, "outputPath");
  FlValue* maxw_v = fl_value_lookup_string(args, "maxWidth");
  FlValue* qual_v = fl_value_lookup_string(args, "quality");

  if (!input_v || !output_v) {
    FlValue* err = fl_value_new_string("Missing inputPath or outputPath");
    FlMethodResponse* resp = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS", "Missing paths", err));
    fl_value_unref(err);
    fl_method_call_respond(method_call, resp, nullptr);
    g_object_unref(resp);
    return;
  }

  WorkItem* item = new WorkItem{};
  item->input_path = g_strdup(fl_value_get_string(input_v));
  item->output_path = g_strdup(fl_value_get_string(output_v));
  item->max_width = maxw_v ? static_cast<int>(fl_value_get_int(maxw_v)) : 500;
  item->quality = qual_v ? static_cast<int>(fl_value_get_int(qual_v)) : 90;
  item->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  item->shutdown = false;

  g_async_queue_push(plugin->work_queue, item);
}

void fast_thumbnail_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FastThumbnailPlugin* plugin = FAST_THUMBNAIL_PLUGIN(
      g_object_new(fast_thumbnail_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "fast_thumbnail", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_handler,
                                             g_object_ref(plugin),
                                             g_object_unref);
  g_object_unref(plugin);
}
