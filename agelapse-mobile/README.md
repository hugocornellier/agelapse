![AgeLapse Logo](https://i.imgur.com/CmsixvW.png)

# Overview

**AgeLapse** is a cross-platform, native application for automatically stabilizing & compiling aging timelapses, i.e. "photo a day" projects.  

AgeLapse uses pre-trained TensorFlow models to perform landmark recognition, then uses the detected positions to stabilize the image sequence.

This is the mobile build (Flutter) of AgeLapse. Google MLKit is used for landmark detection, while all alignment is done using built-in libraries and the Canvas object.

## Installation

### iOS

App Store download: [https://apps.apple.com/ca/app/agelapse/id6503668205](https://apps.apple.com/ca/app/agelapse/id6503668205)

### Android

.apk download: [https://archive.org/download/agelapse-apk/agelapse-apk.zip](https://archive.org/download/agelapse-apk/agelapse-apk.zip)

## Features

| Feature                      | Status         |
|------------------------------|----------------|
| Auto-stabilization           | ✔️             |
| Import/export photos         | ✔️             |
| Camera guide tools (Ghost, grid)     | ✔️             |
| Compile and export videos    | ✔️             |
| Customizable output settings | ✔️             |
| Automatic backups            | ⏳ Coming Soon |


## Development Installation

### Prerequisites

- iOS 13.0+ or Android 5.0+
- Flutter SDK (for development)

1. **Clone the repository**:
   ```sh
   git clone https://github.com/hugocornellier/agelapse.git
   cd agelapse
   ```

2. **Install Dependencies**:
   ```flutter pub get```

3. **Run app**:
   ```flutter run```
