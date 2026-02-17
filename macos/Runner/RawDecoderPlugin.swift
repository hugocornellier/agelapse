import Cocoa
import FlutterMacOS
import CoreImage

/// Native RAW/DNG decoder using Apple's CIRAWFilter.
/// Registered via MethodChannel "com.agelapse/raw_decoder".
class RawDecoderPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.agelapse/raw_decoder",
            binaryMessenger: registrar.messenger
        )
        channel.setMethodCallHandler { call, result in
            guard call.method == "decodeRaw",
                  let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String,
                  let outputPath = args["outputPath"] as? String,
                  let sixteenBit = args["sixteenBit"] as? Bool
            else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                return
            }
            if #available(macOS 12.0, *) {
                decodeRaw(inputPath: inputPath, outputPath: outputPath, sixteenBit: sixteenBit, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "RAW decoding requires macOS 12.0+", details: nil))
            }
        }
    }

    @available(macOS 12.0, *)
    private static func decodeRaw(inputPath: String, outputPath: String, sixteenBit: Bool, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let inputURL = URL(fileURLWithPath: inputPath)
            let outputURL = URL(fileURLWithPath: outputPath)

            guard let rawFilter = CIRAWFilter(imageURL: inputURL) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_FAILED", message: "CIRAWFilter failed to open file", details: nil))
                }
                return
            }

            guard let outputImage = rawFilter.outputImage else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_FAILED", message: "CIRAWFilter produced no output", details: nil))
                }
                return
            }

            let context = CIContext()
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

            do {
                if sixteenBit {
                    // 16-bit PNG output
                    let options: [CIImageRepresentationOption: Any] = [:]
                    guard let pngData = context.pngRepresentation(of: outputImage, format: .RGBA16, colorSpace: colorSpace, options: options) else {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "ENCODE_FAILED", message: "Failed to create 16-bit PNG", details: nil))
                        }
                        return
                    }
                    try pngData.write(to: outputURL)
                } else {
                    // 8-bit PNG output
                    guard let pngData = context.pngRepresentation(of: outputImage, format: .RGBA8, colorSpace: colorSpace, options: [:]) else {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "ENCODE_FAILED", message: "Failed to create 8-bit PNG", details: nil))
                        }
                        return
                    }
                    try pngData.write(to: outputURL)
                }

                DispatchQueue.main.async {
                    result(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
}
