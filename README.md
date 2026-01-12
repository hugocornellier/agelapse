<p align="center" style="font-size:16px; font-family:Arial, sans-serif;">
  <a href="https://agelapse.com" style="text-decoration:none; font-weight:bold;">DOWNLOAD</a> |
  <a href="https://agelapse.com/docs/intro/" style="text-decoration:none; font-weight:bold;">DOCS</a> |
  <a href="https://agelapse.com/docs/support-and-feedback/" style="text-decoration:none; font-weight:bold;">SUPPORT</a>
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

### v2.3.0
- Date stamps on photos, thumbnails and output video (optional)
  - Display capture dates on gallery thumbnails and/or burn them into exported photos and output video
  - Customize format (e.g., `Jan 1, 2024`, `2024-01-01`, `01/01/24`)
  - Configure in the new "Date Stamp" section in Settings

### v2.2.1
- 8K + custom resolution output support
- Performance optimizations & improvements
- Minor bug fixes

### v2.2.0

#### Improvements
- Massive performance improvements. Stabilization pipeline is 2-4x faster (platform-dependent).

#### New Features
- .HEIC support on Windows devices. Thanks to the user who wrote in and suggested this.
- Bulk image selection in the gallery. 3-dot menu in the upper right -> Select.

#### Bug Fixes
- Fixes #11: deleted photos could remain stuck in the generated video. Thanks @agnosticlines.
- Fixes #16 + #20: incorrect timezone and date metadata, could result in incorrectly broken streaks. Thanks @thelittlekatie
and @Syumza.
- Fixes #23: the built-in camera could fail to initialize on Windows. Thanks @COHEJH.

## Platform Support

| Platforms | Status     |
|-----------|------------|
| Windows   | Available  |
| MacOS     | Available  |
| Linux     | Available  |
| iOS       | Available  |
| Android   | Available  |

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
