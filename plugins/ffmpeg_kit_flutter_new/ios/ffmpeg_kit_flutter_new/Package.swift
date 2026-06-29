// swift-tools-version: 5.9
// Swift Package Manager manifest for the ffmpeg_kit_flutter_new iOS plugin.
//
// The prebuilt FFmpegKit binaries are vendored as .xcframeworks under
// Frameworks/ (generated from the upstream fat .frameworks by
// scripts/make_xcframeworks.sh). SwiftPM embeds and signs these dynamic
// frameworks into the host app automatically via binaryTarget.

import PackageDescription

let package = Package(
  name: "ffmpeg_kit_flutter_new",
  platforms: [
    .iOS("14.0")
  ],
  products: [
    .library(name: "ffmpeg-kit-flutter-new", targets: ["ffmpeg_kit_flutter_new"])
  ],
  targets: [
    .target(
      name: "ffmpeg_kit_flutter_new",
      dependencies: [
        "ffmpegkit",
        "libavcodec",
        "libavdevice",
        "libavfilter",
        "libavformat",
        "libavutil",
        "libswresample",
        "libswscale",
      ],
      cSettings: [
        // The plugin sources are written for ARC (matches the podspec's
        // requires_arc); SwiftPM compiles Objective-C without ARC by default.
        .unsafeFlags(["-fobjc-arc"])
      ],
      linkerSettings: [
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreMedia"),
        .linkedLibrary("z"),
        .linkedLibrary("bz2"),
        .linkedLibrary("c++"),
        .linkedLibrary("iconv"),
      ]
    ),
    .binaryTarget(name: "ffmpegkit", path: "Frameworks/ffmpegkit.xcframework"),
    .binaryTarget(name: "libavcodec", path: "Frameworks/libavcodec.xcframework"),
    .binaryTarget(name: "libavdevice", path: "Frameworks/libavdevice.xcframework"),
    .binaryTarget(name: "libavfilter", path: "Frameworks/libavfilter.xcframework"),
    .binaryTarget(name: "libavformat", path: "Frameworks/libavformat.xcframework"),
    .binaryTarget(name: "libavutil", path: "Frameworks/libavutil.xcframework"),
    .binaryTarget(name: "libswresample", path: "Frameworks/libswresample.xcframework"),
    .binaryTarget(name: "libswscale", path: "Frameworks/libswscale.xcframework"),
  ]
)
