import FlutterMacOS
import Photos 

public class LightCompressorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    private var eventSink: FlutterEventSink?
    private var compression: Compression? = nil
    private let batchStreamHandler = BatchStreamHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "light_compressor", binaryMessenger: registrar.messenger)
        let instance = LightCompressorPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(name: "compression/stream", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance.self)

        let batchChannel = FlutterEventChannel(name: "compression/batch-stream", binaryMessenger: registrar.messenger)
        batchChannel.setStreamHandler(instance.batchStreamHandler)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCompression":
            if let myArgs = call.arguments as? [String: Any?],
               let path : String = myArgs["path"] as? String,
               let videoName : String = myArgs["videoName"] as? String,
               let isMinBitrateCheckEnabled : Bool = myArgs["isMinBitrateCheckEnabled"] as? Bool,
               let videoBitrateInMbps : Int? = myArgs["videoBitrateInMbps"] as? Int?,
               let disableAudio : Bool = myArgs["disableAudio"] as? Bool,
               let saveInGallery : Bool = myArgs["saveInGallery"] as? Bool,
               let keepOriginalResolution : Bool = myArgs["keepOriginalResolution"] as? Bool,
               let videoHeight : Int? = myArgs["videoHeight"] as? Int?,
               let videoWidth : Int? = myArgs["videoWidth"] as? Int?,
               let videoQuality : String = myArgs["videoQuality"] as? String {
                
                var desPath: URL
                
                desPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(videoName).mp4")
                try? FileManager.default.removeItem(at: desPath)
                
                let videoCompressor = LightCompressor()
                
                // A FlutterResult may be delivered only once. Cancellation can
                // race with completion, so funnel every terminal reply through
                // this guard on the main thread.
                var didReply = false
                let replyOnce: (Any?) -> Void = { payload in
                    DispatchQueue.main.async {
                        guard !didReply else { return }
                        didReply = true
                        result(payload)
                    }
                }

                compression = videoCompressor.compressVideo(
                    videos: [.init(
                        source: URL(fileURLWithPath: path),
                        destination: desPath,
                        configuration: .init(
                            quality: getVideoQuality(quality: videoQuality),
                            isMinBitrateCheckEnabled: isMinBitrateCheckEnabled,
                            videoBitrateInMbps: videoBitrateInMbps,
                            disableAudio: disableAudio,
                            keepOriginalResolution: keepOriginalResolution,
                            videoSize: videoWidth == nil || videoHeight == nil ? nil : CGSize(width: videoWidth!, height: videoHeight!))
                    )],
                    progressQueue: .main,
                    progressHandler: { _, progress in
                        DispatchQueue.main.async { [unowned self] in
                            if(self.eventSink != nil){
                                let progress = Float(progress.fractionCompleted * 100)
                                if(progress <= 100) {
                                    self.eventSink!(progress)
                                }
                            }
                        }
                    },
                    completion: { compressionResult in
                        
                        switch compressionResult {
                        case .onSuccess(let index, let outputURL, let duration):
                            if(saveInGallery) {
                                DispatchQueue.main.async {
                                    PHPhotoLibrary.shared().performChanges({
                                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                                    })
                                }
                            }
                            let originalSize = (try? FileManager.default
                                .attributesOfItem(atPath: path))?[.size] as? Int ?? 0
                            let compressedSize = (try? FileManager.default
                                .attributesOfItem(atPath: outputURL.path))?[.size] as? Int ?? 0
                            struct SuccessResponse: Encodable {
                                let onSuccess: String
                                let index: String
                                let duration: Double
                                let originalSize: Int
                                let compressedSize: Int
                            }
                            let response = SuccessResponse(
                                onSuccess: outputURL.path,
                                index: String(index),
                                duration: duration,
                                originalSize: originalSize,
                                compressedSize: compressedSize
                            )
                            replyOnce(response.toJson)
                            
                        case .onStart: break
                            
                        case .onFailure(let index, let error):
                            let response: [String: String] = [
                                "onFailure": error.title,
                                "index": String(index),
                                "failureType": error.type.rawValue,
                            ]
                            replyOnce(response.toJson)
                            
                        case .onCancelled:
                            let response: [String: Bool] = ["onCancelled": true]
                            replyOnce(response.toJson)
                        }
                    }
                )
            }
        case "startBatchCompression":
            startBatchCompression(call: call, result: result)
        case "cancelCompression":
            compression?.cancel = true
            // Reply so the Dart-side Future completes; the outcome is delivered
            // as onCancelled on the pending compression call.
            result(nil)
        case "clearCache":
            clearCache(result: result)
        case "getMediaInfo":
            getMediaInfo(call: call, result: result)
        case "getVideoThumbnail":
            getVideoThumbnail(call: call, result: result)
        default:
            let response: [String: String] = ["onFailure": "Method is not defined!"]
            result(response.toJson)
        }
    }

    private func startBatchCompression(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let args                   = call.arguments as? [String: Any?],
            let paths                  = args["paths"]                  as? [String],
            let videoNames             = args["videoNames"]             as? [String],
            let isMinBitrateEnabled    = args["isMinBitrateCheckEnabled"] as? Bool,
            let disableAudio           = args["disableAudio"]           as? Bool,
            let saveInGallery          = args["saveInGallery"]          as? Bool,
            let keepOriginalResolution = args["keepOriginalResolution"] as? Bool,
            let videoQuality           = args["videoQuality"]           as? String,
            paths.count == videoNames.count
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing or mismatched batch arguments.",
                details: nil))
            return
        }
        if paths.isEmpty {
            result([])
            return
        }

        let videoBitrateInMbps = args["videoBitrateInMbps"] as? Int
        let videoHeight        = args["videoHeight"]        as? Int
        let videoWidth         = args["videoWidth"]         as? Int
        let videoSize: CGSize? = videoWidth != nil && videoHeight != nil
            ? CGSize(width: videoWidth!, height: videoHeight!)
            : nil

        let configuration = LightCompressor.Video.Configuration(
            quality: getVideoQuality(quality: videoQuality),
            isMinBitrateCheckEnabled: isMinBitrateEnabled,
            videoBitrateInMbps: videoBitrateInMbps,
            disableAudio: disableAudio,
            keepOriginalResolution: keepOriginalResolution,
            videoSize: videoSize)

        let count = paths.count
        var videos: [LightCompressor.Video] = []
        for i in 0..<count {
            let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(videoNames[i]).mp4")
            try? FileManager.default.removeItem(at: destination)
            videos.append(.init(
                source: URL(fileURLWithPath: paths[i]),
                destination: destination,
                configuration: configuration))
        }

        var results = [[String: Any]?](repeating: nil, count: count)
        var percents = [Double](repeating: 0, count: count)
        var completed = 0

        func record(_ index: Int, _ map: [String: Any]) {
            DispatchQueue.main.async {
                guard index >= 0, index < count, results[index] == nil else { return }
                results[index] = map
                completed += 1
                var event = map
                event["type"] = "result"
                event["index"] = index
                self.batchStreamHandler.eventSink?(event)
                if completed == count {
                    result(results.map { $0 ?? ["onFailure": "Unknown error"] })
                }
            }
        }

        compression = LightCompressor().compressVideo(
            videos: videos,
            progressQueue: .main,
            progressHandler: { [weak self] index, progress in
                guard let self else { return }
                if index >= 0, index < count {
                    percents[index] = progress.fractionCompleted * 100
                }
                let overall = percents.reduce(0, +) / Double(count)
                self.batchStreamHandler.eventSink?([
                    "type": "progress",
                    "index": index,
                    "percent": progress.fractionCompleted * 100,
                    "overallPercent": overall,
                ])
            },
            completion: { compressionResult in
                switch compressionResult {
                case .onStart:
                    break

                case .onSuccess(let index, let outputURL, let duration):
                    if saveInGallery {
                        DispatchQueue.main.async {
                            PHPhotoLibrary.shared().performChanges {
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                            }
                        }
                    }
                    let originalSize = (try? FileManager.default
                        .attributesOfItem(atPath: paths[index]))?[.size] as? Int ?? 0
                    let compressedSize = (try? FileManager.default
                        .attributesOfItem(atPath: outputURL.path))?[.size] as? Int ?? 0
                    record(index, [
                        "onSuccess": outputURL.path,
                        "originalSize": originalSize,
                        "compressedSize": compressedSize,
                        "duration": duration,
                    ])

                case .onFailure(let index, let error):
                    record(index, [
                        "onFailure": error.title,
                        "failureType": error.type.rawValue,
                    ])

                case .onCancelled:
                    // onCancelled carries no index; mark every video that has not
                    // finished yet as cancelled so the batch can complete.
                    for i in 0..<count {
                        record(i, ["onCancelled": true])
                    }
                }
            }
        )
    }

    private func getMediaInfo(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?],
              let path = args["path"] as? String else {
            result(FlutterError(code: "VIDEO_NOT_FOUND", message: "No video path was provided.", details: nil))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let info = try LightCompressor.mediaInfo(for: path)
                DispatchQueue.main.async { result(info) }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(from: error, fallbackCode: "MEDIA_INFO_FAILED"))
                }
            }
        }
    }

    private func getVideoThumbnail(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?],
              let path = args["path"] as? String else {
            result(FlutterError(code: "VIDEO_NOT_FOUND", message: "No video path was provided.", details: nil))
            return
        }
        let positionInMs = (args["positionInMs"] as? Int) ?? 0
        let quality = (args["quality"] as? Int) ?? 50
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let thumbPath = try LightCompressor.thumbnail(
                    for: path, positionInMs: positionInMs, quality: quality)
                DispatchQueue.main.async { result(thumbPath) }
            } catch {
                DispatchQueue.main.async {
                    result(Self.flutterError(from: error, fallbackCode: "THUMBNAIL_FAILED"))
                }
            }
        }
    }

    /// Maps a thrown error to a FlutterError, preferring a typed `MediaError`
    /// code and falling back to [fallbackCode] for anything else.
    private static func flutterError(from error: Error, fallbackCode: String) -> FlutterError {
        if let mediaError = error as? MediaError {
            return FlutterError(code: mediaError.code, message: mediaError.message, details: nil)
        }
        return FlutterError(code: fallbackCode, message: error.localizedDescription, details: nil)
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    private func getVideoQuality(quality: String) -> VideoQuality{
        switch quality {
        case "very_low":
            return VideoQuality.very_low
        case "low":
            return VideoQuality.low
        case "medium":
            return VideoQuality.medium
        case "high":
            return VideoQuality.high
        case "very_high":
            return VideoQuality.very_high
        default:
            return VideoQuality.medium
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

/// Stream handler for the batch progress/result EventChannel
/// (`compression/batch-stream`).
final class BatchStreamHandler: NSObject, FlutterStreamHandler {
    var eventSink: FlutterEventSink?

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
