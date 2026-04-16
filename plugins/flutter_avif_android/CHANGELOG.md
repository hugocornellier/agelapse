## 3.1.0

* Update android binaries to support 16KB page size
* Add accept header by default
* Increase protobuf decoding size limit
* Fix animation caching (Thanks @tahirdevelop)

## 3.0.0

* Require Dart >= 3.4.0 and Flutter >= 3.22.0
* Migrate to package:web to support wasm compilation
* Remove flutter_rust_bridge dependency

## 2.5.0

* Add CachedNetworkAvifImage and CachedNetworkAvifImageProvider
* Fix AssetAvifImage caching (Thanks @Tosuj-work)
* Fix macos build warnings
* Fix exif orientation correction on web (Thanks @michaelnew)

## 2.4.1

* Fix multiple script loading on web (Thanks @hsbijarniya)

## 2.4.0

* Option to keep exif data while encoding
* Switch to http package for loading network requests

## 2.3.0

* Add decodeAvif
* Fix asset path resolution on web

## 2.2.0

* Web support

## 2.1.1

* Fix pub.dev build

## 2.1.0

* Custom animation controller support
* Gradle 8+ support

## 2.0.0

* Update dart sdk to use 3.0.0+
* Update flutter_avif_platform_interface to 1.5.0
* Update flutter_lints to 2.0.3

## 1.4.0

* Add missing constructor arguments to match flutter image api
* Add support for asset variants

## 1.3.0

* Enable dav1d decoder
* Enable rav1e encoder
* Add single frame decoder to lower the memory footprint of static images
* Fix skipping first frame of animated images
* Fix alpha channel rendering

## 1.2.0

* Macos ARM support

## 1.1.0

* Update flutter_rust_bridge to 1.72.0
* Add errorBuilder to AvifImage

## 1.0.1

* Constrain flutter_rust_bridge version

## 1.0.0

* Initial release.
