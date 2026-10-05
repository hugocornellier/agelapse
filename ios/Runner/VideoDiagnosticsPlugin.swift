import AVFoundation
import Flutter
import UIKit

/// Playback diagnostics for the in-app video player.
/// Registered via MethodChannel "com.agelapse/video_diagnostics".
///
/// Added for a report of a black video on iPhone 17 / iOS 27, where the player
/// ran normally (clock advancing, no error) but showed no picture. Together the
/// methods let the log tell a black file, a decode failure and a rendering
/// failure apart.
class VideoDiagnosticsPlugin {
    /// Players kept alive while a frame probe runs.
    private static var activeProbes: [AVPlayer] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.agelapse/video_diagnostics",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any]
            switch call.method {
            case "describeVideo":
                guard let path = args?["path"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                    return
                }
                describeVideo(path: path, result: result)
            case "probeFrames":
                guard let path = args?["path"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                    return
                }
                probeFrames(path: path, seconds: args?["seconds"] as? Double ?? 2.5, result: result)
            case "decodeAllFrames":
                guard let path = args?["path"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                    return
                }
                decodeAllFrames(path: path, result: result)
            case "measureScreenRegion":
                guard let left = args?["left"] as? Double,
                      let top = args?["top"] as? Double,
                      let width = args?["width"] as? Double,
                      let height = args?["height"] as? Double
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing region", details: nil))
                    return
                }
                result(measureScreenRegion(CGRect(x: left, y: top, width: width, height: height)))
            case "playerLayers":
                result(playerLayers())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// What AVFoundation sees in [path]: duration and, per track, codec, size,
    /// frame rate, bit depth, color tags, transform and whether it can play
    /// and decode the track.
    private static func describeVideo(path: String, result: @escaping FlutterResult) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task {
            do {
                let duration = try await asset.load(.duration)
                var tracks: [[String: Any]] = []
                for track in try await asset.load(.tracks) {
                    let (formats, size, fps, bitrate, transform, playable, decodable) =
                        try await track.load(
                            .formatDescriptions, .naturalSize, .nominalFrameRate,
                            .estimatedDataRate, .preferredTransform, .isPlayable, .isDecodable
                        )
                    var info: [String: Any] = [
                        "type": track.mediaType.rawValue,
                        "width": Double(size.width),
                        "height": Double(size.height),
                        "fps": Double(fps),
                        "bitrate": Double(bitrate),
                        "transform": [transform.a, transform.b, transform.c, transform.d].map { Double($0) },
                        "playable": playable,
                        "decodable": decodable,
                    ]
                    if let format = formats.first {
                        let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
                        info["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(format))
                        info["depth"] = ext[kCMFormatDescriptionExtension_Depth as String] as? Int ?? 0
                        info["fullRange"] = ext[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool ?? false
                        info["primaries"] = ext[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String ?? ""
                        info["transfer"] = ext[kCMFormatDescriptionExtension_TransferFunction as String] as? String ?? ""
                        info["matrix"] = ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String ?? ""
                    }
                    tracks.append(info)
                }
                let description: [String: Any] = ["duration": duration.seconds, "tracks": tracks]
                await MainActor.run { result(description) }
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "DESCRIBE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// Plays [path] muted through an AVPlayerItemVideoOutput configured exactly
    /// like video_player_avfoundation's (FVPVideoPlayer.m), and reports how many
    /// frames came out and how bright they were.
    private static func probeFrames(path: String, seconds: Double, result: @escaping FlutterResult) {
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        let outputSettings: [String: Any] = [
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let output = AVPlayerItemVideoOutput(outputSettings: outputSettings)
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        activeProbes.append(player)
        player.play()

        var frames = 0
        var lumaSum = 0.0
        var width = 0
        var height = 0
        var pixelFormat = ""
        let deadline = CACurrentMediaTime() + seconds
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: itemTime),
               let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                frames += 1
                lumaSum += meanLuma(buffer)
                width = CVPixelBufferGetWidth(buffer)
                height = CVPixelBufferGetHeight(buffer)
                pixelFormat = fourCC(CVPixelBufferGetPixelFormatType(buffer))
            }
            guard CACurrentMediaTime() >= deadline else { return }
            timer.invalidate()
            player.pause()
            activeProbes.removeAll { $0 === player }
            result([
                "framesReceived": frames,
                "meanLuma": frames > 0 ? lumaSum / Double(frames) : 0.0,
                "width": width,
                "height": height,
                "pixelFormat": pixelFormat,
                "itemStatus": item.status.rawValue,
                "error": item.error?.localizedDescription ?? "",
            ])
        }
    }

    /// Decodes every frame of [path] with AVAssetReader and reports each frame's
    /// mean luma, so black or undecodable stretches can be located. The reader
    /// stops early (status failed) if it hits data it cannot decode.
    private static func decodeAllFrames(path: String, result: @escaping FlutterResult) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task.detached(priority: .userInitiated) {
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw NSError(
                        domain: "VideoDiagnostics", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No video track"]
                    )
                }
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                ])
                output.alwaysCopiesSampleData = false
                reader.add(output)
                reader.startReading()
                var lumas: [Double] = []
                while let sample = output.copyNextSampleBuffer() {
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    lumas.append((VideoDiagnosticsPlugin.meanLuma(buffer) * 10).rounded() / 10)
                }
                let summary: [String: Any] = [
                    "lumas": lumas,
                    "status": reader.status.rawValue,
                    "error": reader.error?.localizedDescription ?? "",
                ]
                await MainActor.run { result(summary) }
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "DECODE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// Mean luma and colorfulness (0-255) of [rect], in window points, from a
    /// snapshot of the key window. Captures Flutter's own rendering (including
    /// texture-based video) but not native AVPlayerLayer content on devices.
    private static func measureScreenRegion(_ rect: CGRect) -> Any {
        guard let window = keyWindow() else {
            return FlutterError(code: "NO_WINDOW", message: "No key window", details: nil)
        }
        let region = rect.intersection(window.bounds)
        guard !region.isNull, region.width >= 1, region.height >= 1 else {
            return FlutterError(code: "EMPTY_REGION", message: "Region is off screen", details: nil)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: region.size, format: format).image { _ in
            window.drawHierarchy(
                in: CGRect(origin: CGPoint(x: -region.minX, y: -region.minY), size: window.bounds.size),
                afterScreenUpdates: true
            )
        }
        // Downsample into a fixed RGBA8 layout so the pixels can be read directly.
        let side = 48
        guard let cgImage = snapshot.cgImage,
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return FlutterError(code: "SNAPSHOT_FAILED", message: "Could not read snapshot", details: nil)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else {
            return FlutterError(code: "SNAPSHOT_FAILED", message: "Snapshot has no pixels", details: nil)
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var luma = 0.0
        var chroma = 0.0
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
            chroma += max(r, g, b) - min(r, g, b)
        }
        let count = Double(side * side)
        return ["luma": luma / count, "chroma": chroma / count]
    }

    /// Every AVPlayerLayer on screen. The platform-view player draws through
    /// one; the texture player adds a zero-size helper layer.
    private static func playerLayers() -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ layer: CALayer) {
            if let playerLayer = layer as? AVPlayerLayer {
                found.append([
                    "width": Double(playerLayer.bounds.width),
                    "height": Double(playerLayer.bounds.height),
                    "readyForDisplay": playerLayer.isReadyForDisplay,
                ])
            }
            layer.sublayers?.forEach(walk)
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.windows.forEach { walk($0.layer) }
        }
        return found
    }

    private static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    /// Mean Rec. 709 luma (0-255) of a BGRA buffer, sampled on a 16 px grid.
    private static func meanLuma(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              let base = CVPixelBufferGetBaseAddress(buffer)
        else { return -1 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: 16) {
            for x in stride(from: 0, to: width, by: 16) {
                let p = pixels + y * rowBytes + x * 4
                sum += 0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : -1
    }

    private static func fourCC(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }
}
