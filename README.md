<p align="center" style="font-size:16px; font-family:Arial, sans-serif;">
  <a href="https://agelapse.com" style="text-decoration:none; font-weight:bold;">DOWNLOAD</a> •
  <a href="https://agelapse.com/docs/intro/" style="text-decoration:none; font-weight:bold;">DOCS</a> •
  <a href="https://agelapse.com/docs/support-and-feedback/" style="text-decoration:none; font-weight:bold;">CONTACT</a>
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

### Installation

Download AgeLapse: [https://agelapse.com](https://agelapse.com)

### How Does It Work? 

AgeLapse takes a raw photo, detects a set of landmarks on the person (eyes for face), and applies affine transformations (scale, rotate, translate) so that those anchors land on fixed “goal” coordinates inside a fixed-size canvas.

## What's New / Changelog

### v2.7.0 (June 2026)

#### New Features
- Recently Deleted
  - Deleted photos remain in Recently Deleted for 30 days before being purged.
  - Restore or permanently delete individual photos, selected photos, or the entire trash.

#### Improvements
- ~1.3x faster stabilization on all platforms with identical output
- Manual stabilization edits are now saved and re-used
  - Hand-tuned alignments from the Manual Stabilization page (horizontal/vertical offset, scale, and rotation) now survive a full re-stabilization. Previously they were discarded whenever a settings change re-ran stabilization across every photo.
  - A saved manual edit takes precedence over the automatic alignment and is re-applied on every subsequent re-stabilization, so your adjustments stick.
  - "Stabilize on Other Faces" is remembered too: the specific face you pick is stored per photo and automatically re-selected on every later re-stabilization, at any resolution.
  - Changing the output resolution rescales saved manual edits proportionally instead of throwing them away. They are only recomputed from scratch when a change would invalidate them (aspect ratio, eye offsets, or project orientation).
- New Inspection Mode setting: images-per-row control (1-4)
  - Previously, Inspection Mode locked the grid at 2 images per row. The user can now select between 1-4.
  - Available both in the inspection toolbar and as a synced Gallery setting
- Maintain a shared scroll position across stabilized and raw tabs

#### Bug Fixes
- Fix re-importing a previously deleted photo being blocked by duplicate fingerprint checks.
- Fix inspection guidelines and thumbnails being cropped or misaligned for custom (WIDTH×HEIGHT) resolutions.
- Fix several crashes and memory leaks (video player teardown, concurrent re-stabilization, and disposed-widget callbacks).
- Fix macOS window traffic-light buttons sitting too high until the window was focused.

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

- **Documentation:** https://agelapse.com/docs/intro/
- **Demo Video:** [https://www.youtube.com/watch?v=vMOWSAHdwhA](https://www.youtube.com/watch?v=vMOWSAHdwhA)
- **Contact:** For suggestions, feature requests or bug reports: 
  - Email **agelapse@gmail.com**, or open an [issue](https://github.com/hugocornellier/agelapse/issues) on GitHub.

## Contributions

Contributions to AgeLapse are welcome. Please follow these steps:

1. Fork the repository
2. Create a new branch for your feature or bug fix
3. Make your changes with descriptive commit messages
4. Push your changes to your forked repository
5. Open a pull request explaining your changes
