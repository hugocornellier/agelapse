#!/usr/bin/env python3
"""Decode a HEIC through libheif the way the packaged Linux app resolves it.

The libraries named with --lib are loaded in order with RTLD_GLOBAL. For an
AgeLapse bundle that is libflutter_linux_gtk.so first (the executable has it
loaded before any plugin), then libheic_native_plugin.so. The dynamic loader
then resolves the plugin's libheif.so.1 exactly as it does for the app:
LD_LIBRARY_PATH, the plugin's own RUNPATH, then the system directories. The
decode below runs through whichever libheif ended up in the process, and the
report says which file that was.

Outcomes:
  load-fail    a library could not be loaded (the app would abort at startup)
  decode-fail  libheif loaded but could not decode the image
  ok           the image decoded

The exit status is 0 only when the outcome matches --expect (and, when given,
the loaded libheif lives under --expect-libheif-under).
"""

import argparse
import ctypes
import os
import sys

HEIF_COLORSPACE_RGB = 1
HEIF_CHROMA_INTERLEAVED_RGB = 10


class HeifError(ctypes.Structure):
    _fields_ = [
        ("code", ctypes.c_int),
        ("subcode", ctypes.c_int),
        ("message", ctypes.c_char_p),
    ]

    def ok(self):
        return self.code == 0

    def text(self):
        msg = self.message.decode(errors="replace") if self.message else ""
        return f"{msg} (code {self.code}, subcode {self.subcode})"


def loaded_paths(*needles):
    found = []
    with open("/proc/self/maps") as maps:
        for line in maps:
            parts = line.split(None, 5)
            if len(parts) < 6:
                continue
            path = parts[5].strip()
            if any(n in os.path.basename(path) for n in needles) and path not in found:
                found.append(path)
    return found


def finish(outcome, detail, args, libheif_path):
    print(f"RESULT outcome={outcome} libheif={libheif_path or '-'} detail={detail}")
    if outcome != args.expect:
        print(f"MISMATCH: expected {args.expect}, got {outcome}")
        return 1
    if args.expect_libheif_under:
        want = os.path.realpath(args.expect_libheif_under)
        have = os.path.realpath(libheif_path) if libheif_path else ""
        if not have.startswith(want + os.sep):
            print(f"MISMATCH: libheif was loaded from {have or 'nowhere'}, not from under {want}")
            return 1
    print(f"as expected: {outcome}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lib", action="append", required=True,
                    help="library to load with RTLD_GLOBAL, in order; repeatable")
    ap.add_argument("--heic", required=True, help="HEIC file to decode")
    ap.add_argument("--init", action="store_true",
                    help="call heif_init() before decoding, as the fixed plugin does")
    ap.add_argument("--expect", required=True, choices=["ok", "decode-fail", "load-fail"])
    ap.add_argument("--expect-libheif-under",
                    help="directory the loaded libheif.so.1 must live under")
    args = ap.parse_args()

    for lib in args.lib:
        try:
            ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
            print(f"loaded {lib}")
        except OSError as e:
            print(f"load failed: {e}")
            return finish("load-fail", str(e), args, None)

    heif_paths = loaded_paths("libheif.so")
    de265_paths = loaded_paths("libde265.so")
    libheif_path = heif_paths[0] if heif_paths else None
    print(f"libheif in process: {heif_paths or 'none'}")
    print(f"libde265 in process: {de265_paths or 'none'}")

    g = ctypes.CDLL(None)
    try:
        g.heif_get_version.restype = ctypes.c_char_p
        g.heif_init.restype = HeifError
        g.heif_init.argtypes = [ctypes.c_void_p]
        g.heif_context_alloc.restype = ctypes.c_void_p
        g.heif_context_read_from_file.restype = HeifError
        g.heif_context_read_from_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p]
        g.heif_context_get_primary_image_handle.restype = HeifError
        g.heif_context_get_primary_image_handle.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        g.heif_decode_image.restype = HeifError
        g.heif_decode_image.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                                        ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
        g.heif_image_get_primary_width.restype = ctypes.c_int
        g.heif_image_get_primary_width.argtypes = [ctypes.c_void_p]
        g.heif_image_get_primary_height.restype = ctypes.c_int
        g.heif_image_get_primary_height.argtypes = [ctypes.c_void_p]
        g.heif_image_release.argtypes = [ctypes.c_void_p]
        g.heif_image_handle_release.argtypes = [ctypes.c_void_p]
        g.heif_context_free.argtypes = [ctypes.c_void_p]
    except AttributeError as e:
        print(f"libheif symbols not found in the process: {e}")
        return finish("load-fail", f"no libheif symbols: {e}", args, libheif_path)

    version = g.heif_get_version().decode()
    print(f"libheif version: {version}")

    if args.init:
        err = g.heif_init(None)
        print(f"heif_init(): {'ok' if err.ok() else err.text()}")

    ctx = g.heif_context_alloc()
    err = g.heif_context_read_from_file(ctx, args.heic.encode(), None)
    if not err.ok():
        g.heif_context_free(ctx)
        return finish("decode-fail", f"read_from_file: {err.text()}", args, libheif_path)
    print("container parsed")

    handle = ctypes.c_void_p()
    err = g.heif_context_get_primary_image_handle(ctx, ctypes.byref(handle))
    if not err.ok():
        g.heif_context_free(ctx)
        return finish("decode-fail", f"primary_image_handle: {err.text()}", args, libheif_path)

    img = ctypes.c_void_p()
    err = g.heif_decode_image(handle, ctypes.byref(img), HEIF_COLORSPACE_RGB,
                              HEIF_CHROMA_INTERLEAVED_RGB, None)
    if not err.ok():
        g.heif_image_handle_release(handle)
        g.heif_context_free(ctx)
        return finish("decode-fail", f"decode_image: {err.text()}", args, libheif_path)

    w = g.heif_image_get_primary_width(img)
    h = g.heif_image_get_primary_height(img)
    g.heif_image_release(img)
    g.heif_image_handle_release(handle)
    g.heif_context_free(ctx)
    if w <= 0 or h <= 0:
        return finish("decode-fail", f"decoded image has size {w}x{h}", args, libheif_path)
    return finish("ok", f"decoded {w}x{h} with libheif {version}", args, libheif_path)


if __name__ == "__main__":
    sys.exit(main())
