import Flutter
import Photos

/// Flutter plugin that bridges the `LightCompressor` Swift library to Dart.
public class SwiftLightCompressorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Properties

    private var eventSink: FlutterEventSink?
    private var compression: Compression?

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "light_compressor",
            binaryMessenger: registrar.messenger())
        let instance = SwiftLightCompressorPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(
            name: "compression/stream",
            binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCompression":
            startCompression(call: call, result: result)
        case "cancelCompression":
            compression?.cancel = true
        case "clearCache":
            clearCache(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Private

    private func startCompression(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let args                  = call.arguments as? [String: Any?],
            let path                  = args["path"]                  as? String,
            let videoName             = args["videoName"]             as? String,
            let isMinBitrateEnabled   = args["isMinBitrateCheckEnabled"] as? Bool,
            let disableAudio          = args["disableAudio"]          as? Bool,
            let saveInGallery         = args["saveInGallery"]         as? Bool,
            let keepOriginalResolution = args["keepOriginalResolution"] as? Bool,
            let videoQuality          = args["videoQuality"]          as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "One or more required arguments are missing or have an invalid type.",
                details: nil))
            return
        }

        // Optional arguments
        let videoBitrateInMbps = args["videoBitrateInMbps"] as? Int
        let videoHeight        = args["videoHeight"]        as? Int
        let videoWidth         = args["videoWidth"]         as? Int

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(videoName).mp4")
        try? FileManager.default.removeItem(at: destinationURL)

        let videoSize: CGSize? = videoWidth != nil && videoHeight != nil
            ? CGSize(width: videoWidth!, height: videoHeight!)
            : nil

        compression = LightCompressor().compressVideo(
            videos: [
                .init(
                    source: URL(fileURLWithPath: path),
                    destination: destinationURL,
                    configuration: .init(
                        quality: getVideoQuality(quality: videoQuality),
                        isMinBitrateCheckEnabled: isMinBitrateEnabled,
                        videoBitrateInMbps: videoBitrateInMbps,
                        disableAudio: disableAudio,
                        keepOriginalResolution: keepOriginalResolution,
                        videoSize: videoSize))
            ],
            progressQueue: .main,
            progressHandler: { [weak self] progress in
                guard let self else { return }
                let percent = Float(progress.fractionCompleted * 100)
                if let eventSink, percent <= 100 {
                    eventSink(percent)
                }
            },
            completion: { compressionResult in
                // completion is already dispatched to main in LightCompressor
                switch compressionResult {
                case .onStart:
                    break

                case .onSuccess(let index, let url, let duration):
                    if saveInGallery {
                        PHPhotoLibrary.shared().performChanges {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }
                    }
                    let originalSize = (try? FileManager.default
                        .attributesOfItem(atPath: path))?[.size] as? Int ?? 0
                    let compressedSize = (try? FileManager.default
                        .attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                    struct SuccessResponse: Encodable {
                        let onSuccess: String
                        let index: String
                        let duration: Double
                        let originalSize: Int
                        let compressedSize: Int
                    }
                    let response = SuccessResponse(
                        onSuccess: url.path,
                        index: String(index),
                        duration: duration,
                        originalSize: originalSize,
                        compressedSize: compressedSize
                    )
                    result(response.toJson)

                case .onFailure(let index, let error):
                    let response: [String: String] = [
                        "onFailure": error.title,
                        "index": String(index),
                        "failureType": error.type.rawValue,
                    ]
                    result(response.toJson)

                case .onCancelled:
                    let response: [String: Bool] = ["onCancelled": true]
                    result(response.toJson)
                }
            }
        )
    }

    /// Maps a quality string received from Dart to a `VideoQuality` enum value.
    private func getVideoQuality(quality: String) -> VideoQuality {
        switch quality {
        case "very_low":  return .very_low
        case "low":       return .low
        case "medium":    return .medium
        case "high":      return .high
        case "very_high": return .very_high
        default:          return .medium
        }
    }

    private func clearCache(result: @escaping FlutterResult) {
        do {
            try LightCompressor.clearCache()
            result(true)
        } catch {
            result(FlutterError(code: "CLEAR_CACHE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
}