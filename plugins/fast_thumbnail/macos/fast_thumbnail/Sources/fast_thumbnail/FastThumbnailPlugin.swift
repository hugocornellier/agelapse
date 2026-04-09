import AppKit
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

public class FastThumbnailPlugin: NSObject, FlutterPlugin {
  private let workerQueue = DispatchQueue(label: "com.hugocornellier.fast_thumbnail.worker", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "fast_thumbnail", binaryMessenger: registrar.messenger)
    let instance = FastThumbnailPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "generate" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any],
          let inputPath = args["inputPath"] as? String,
          let outputPath = args["outputPath"] as? String,
          let maxWidth = args["maxWidth"] as? Int,
          let quality = args["quality"] as? Int else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
      return
    }

    workerQueue.async {
      let generateResult = self.generateThumbnail(inputPath: inputPath, outputPath: outputPath, maxWidth: maxWidth, quality: quality)
      DispatchQueue.main.async {
        result(generateResult)
      }
    }
  }

  private func generateThumbnail(inputPath: String, outputPath: String, maxWidth: Int, quality: Int) -> Any? {
    let url = URL(fileURLWithPath: inputPath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

    // Get original dimensions (after EXIF rotation)
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1

    // Swap dimensions for rotated orientations (5,6,7,8)
    let isRotated = orientation >= 5 && orientation <= 8
    let originalWidth = isRotated ? pixelHeight : pixelWidth
    let originalHeight = isRotated ? pixelWidth : pixelHeight

    // Generate thumbnail with EXIF transform applied
    let options: [CFString: Any] = [
      kCGImageSourceThumbnailMaxPixelSize: maxWidth,
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]

    guard let thumbnailRef = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

    // Write JPEG
    let outputURL = URL(fileURLWithPath: outputPath)
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }

    let jpegOptions: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
    ]
    CGImageDestinationAddImage(destination, thumbnailRef, jpegOptions as CFDictionary)

    guard CGImageDestinationFinalize(destination) else { return nil }

    return [
      "originalWidth": originalWidth,
      "originalHeight": originalHeight,
    ]
  }
}
