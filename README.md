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

### v2.5.0 (Feb 2026)

#### New Features
- Light theme (auto-reads system settings OR toggle in Settings -> Appearance)

#### Improvements
- Consolidate app colours and theme

#### Bug Fixes
- 

For previous releases, see the [full changelog](https://agelapse.com/docs/changelog/).

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
