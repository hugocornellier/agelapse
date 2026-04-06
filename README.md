<p align="center" style="font-size:16px; font-family:Arial, sans-serif;">
  <a href="https://agelapse.com" style="text-decoration:none; font-weight:bold;">DOWNLOAD</a> |
  <a href="https://agelapse.com/docs/intro/" style="text-decoration:none; font-weight:bold;">DOCS</a> |
  <a href="https://agelapse.com/docs/support-and-feedback/" style="text-decoration:none; font-weight:bold;">SUPPORT</a>
</p>

<p align="center">
<a href="https://github.com/hugocornellier/agelapse/actions/workflows/build.yml"><img src="https://github.com/hugocornellier/agelapse/actions/workflows/build.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/hugocornellier/agelapse/actions/workflows/integration.yml"><img src="https://github.com/hugocornellier/agelapse/actions/workflows/integration.yml/badge.svg" alt="Tests"></a>
</p>

<p align="center">
  <img
    src="https://i.imgur.com/CmsixvW.png"
    alt="Demo animation"
  />
</p>

<p align="center">
  <img
    src="/assets/demo.gif"
    alt="Demo animation"
    width="540"
  />
</p> 

## Overview

**AgeLapse** automates the process of aligning face pictures and creating stabilized aging time-lapses, i.e. "photo-a-day" videos. The application runs natively on desktop (MacOS, Windows, Linux) and on mobile (iOS and Android).

## Installation

Download AgeLapse: [https://agelapse.com](https://agelapse.com)

**Mobile Import Note:** To easily import a large number of photos into the mobile version, create a .zip file containing all files.

## How Does It Work? 

AgeLapse takes a raw photo, detects a set of landmarks on the person (eyes for face), and applies affine transformations (scale, rotate, translate) so that those anchors land on fixed “goal” coordinates inside a fixed-size canvas.

The face detection model used by AgeLapse is platform-dependent. On Mobile, Google MLKit is used. On MacOS, Apple Vision is used.

## What's New / Changelog

### v2.5.1 (Apr 2026)

#### Improvements
- Reduced bundled FFmpeg binary size (macOS: 76 MB → 5.5 MB, Windows: 95 MB → 13 MB)

#### Bug Fixes
- Fix image preview exit button UI issue

### v2.5.0 (Apr 2026)

#### New Features
- Light theme (auto-reads system settings OR toggle in Settings -> Appearance)
- Video codec selection (H.264, HEVC, ProRes 422, ProRes 422 HQ, ProRes 4444, VP9)
- Transparent video background support with ProRes 4444 and VP9 alpha
- Blurred video background option
- RAW image support
- Dog and cat project types for pet timelapses
- Linked source folders
- Preserve original files on import (metadata, filenames, byte for byte)
- Date stamp font size setting
- Inspection mode for gallery and image preview (overlay stabilization grid to verify alignment)

#### Improvements
- Consolidate app colours and theme
- Improved import flow with preview dialog and clearer date extraction
- Reduced Android APK size

#### Bug Fixes
- Fixes #25: bug causing .zip exports to fail on certain devices
- Fix photos taken before 2001 sorting incorrectly
- Fix date stamps not syncing correctly in rare cases
- Fix layout overflow on manual stabilization page on mobile
- Fix theme toggle failing to open
- Fix Cmd+A not working in file picker

For previous releases, see the [full changelog](https://agelapse.com/docs/changelog/).

## Platform Support

| Platform | x86_64 | arm64 | Package              |
|----------|--------|-------|----------------------|
| Windows  | ✅     |       | `.exe`               |
| macOS    | ✅     | ✅    | `.app`               |
| Linux    | ✅     |       | `.deb` or `.flatpak` |
| iOS      |        | ✅    | App Store            |
| Android  | ✅     | ✅    | `.apk`               |

## Development Setup

- To run the application in a development environment, refer to the [AgeLapse Documentation (Dev Setup)](https://agelapse.com/docs/dev-setup/).

## Resources

- **Documentation** - https://agelapse.com/docs/intro/
- **Demo Video** - [https://www.youtube.com/watch?v=vMOWSAHdwhA](https://www.youtube.com/watch?v=vMOWSAHdwhA)
- **Contact** - For suggestions, feature requests or bug reports: 
  - Email **agelapse@gmail.com**, or open an [issue](https://github.com/hugocornellier/agelapse/issues) on GitHub.

## Contributions

Contributions to AgeLapse are welcome. Please follow these steps:

1. Fork the repository
2. Create a new branch for your feature or bug fix
3. Make your changes with descriptive commit messages
4. Push your changes to your forked repository
5. Open a pull request explaining your changes
