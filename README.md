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

## What's New

### v2.1.3

- Fixes #20. Thanks @Syumza.

### v2.1.2

- Fixed a bug where the "adjust output position" functionality would fail 

### v2.1.1

- Smoother experience across the app, improving responsiveness/reduced stutter during stabilization.

### v2.1.0

- Fix several bugs 

### v2.0.1

- Update documentation URL 

### v2.0.0

- Provide full MacOS, Windows & Linux support to the AgeLapse flutter build.
- Further improvements to the "manual stabilization" option for when AgeLapse fails to detect landmarks (eg: if the user is wearing sunglasses, the eyes are partially obstructed, etc.)
- Massive improvements to the [AgeLapse Documentation](https://agelapse.com/docs/intro/) 

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

- **Documentation**: https://agelapse.com/docs/intro/
- **Demo Video:** [https://www.youtube.com/watch?v=vMOWSAHdwhA](https://www.youtube.com/watch?v=vMOWSAHdwhA)
- **Support:** For suggestions, feature requests or bugs, please contact agelapse@gmail.com

## Contributions

Contributions to AgeLapse are welcome. Please follow these steps:

1. Fork the repository
2. Create a new branch for your feature or bug fix
3. Make your changes with descriptive commit messages
4. Push your changes to your forked repository
5. Open a pull request explaining your changes
