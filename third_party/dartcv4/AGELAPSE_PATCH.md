# AgeLapse patch

This directory is a minimal vendoring of `dartcv4` 2.3.1 from pub.dev
(archive SHA-256
`e78c39ea09decc04ee70be9684eb63c092e0cb006b37615d214a08b6e098d5a9`).
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
