# AgeLapse patch

This directory is a minimal vendoring of `dartcv4` 2.2.1+4 from pub.dev
(archive SHA-256
`5764d13550055da3bb35ca28e6866b837579dfb4b594582b7a7753785ca5dfef`).
Examples and upstream tests are omitted because this copy is used only as a
dependency.

AgeLapse adds one CMake setting in `src/cmake/opencv_options.cmake`:

```cmake
set(WITH_JASPER OFF CACHE BOOL "Use JASPER" FORCE)
```

Upstream disables building Jasper but leaves Jasper discovery enabled. On a
macOS developer machine with Homebrew Jasper installed, OpenCV consequently
links the host's architecture-specific library into `dartcv.framework`. That
breaks universal release builds and makes otherwise successful app bundles
depend on an absolute `/opt/homebrew` path.

When updating `opencv_dart`/`dartcv4`, replace this directory from the matching
pub.dev archive, reapply the setting only if upstream still needs it, and verify
the packaged framework with:

```sh
otool -L AgeLapse.app/Contents/Frameworks/dartcv.framework/Versions/A/dartcv
```
