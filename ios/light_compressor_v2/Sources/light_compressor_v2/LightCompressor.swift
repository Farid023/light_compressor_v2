import AVFoundation
import CoreImage
import ImageIO

/// Desired quality level for video compression.
public enum VideoQuality {
    case very_high
    case high
    case medium
    case low
    case very_low
}

/// The output video codec used for compression.
public enum VideoFormat {
    /// H.264 / AVC — the widely compatible default.
    case h264
    /// H.265 / HEVC — smaller files at the same quality; requires hardware
    /// support, otherwise the compressor falls back to `.h264`.
    case h265

    /// Lower-case wire value shared with Dart (`"h264"` / `"h265"`).
    var wireValue: String { self == .h265 ? "h265" : "h264" }

    /// Maps a Dart wire value back to a format; defaults to `.h264`.
    static func from(wire: String?) -> VideoFormat { wire == "h265" ? .h265 : .h264 }
}

/// The result of a compression operation.
public enum CompressionResult {
    /// Compression has started.
    case onStart
    /// Compression succeeded. Contains the video index, output URL, video
    /// duration in seconds, the codec actually used (which may differ from the
    /// requested one if H.265 fell back to H.264), whether a requested target
    /// output size was met, and the number of encode passes run (1 or 2).
    case onSuccess(Int, URL, Double, VideoFormat, Bool, Int)
    /// Compression failed. Contains the video index and error.
    case onFailure(Int, CompressionError)
    /// Compression was cancelled by the user.
    case onCancelled
}

/// A handle that allows cancelling an ongoing compression.
public class Compression {
    public init() {}

    /// Set to `true` to cancel the active compression.
    public var cancel = false
}

/// Classifies a compression failure so callers can react programmatically
/// instead of matching error message text.
public enum CompressionErrorType: String {
    /// Missing read/write permission.
    case permission
    /// Unsupported format/codec or a missing video track.
    case unsupported
    /// The source video could not be found.
    case notFound
    /// Any other, unclassified failure.
    case unknown
}

/// Describes a compression failure.
public struct CompressionError: LocalizedError {
    public let title: String
    public let type: CompressionErrorType

    init(title: String = "Compression Error", type: CompressionErrorType = .unknown) {
        self.title = title
        self.type = type
    }
}

/// Errors thrown by the metadata and thumbnail helpers. Each case carries a
/// stable [code] that the plugin layer forwards to Dart as a PlatformException
/// code, plus a human-readable [message].
public enum MediaError: Error {
    /// The source file does not exist.
    case notFound
    /// The file exists but no video track could be read.
    case unreadable
    /// A thumbnail frame could not be generated.
    case thumbnailFailed

    public var code: String {
        switch self {
        case .notFound: return "VIDEO_NOT_FOUND"
        case .unreadable: return "UNSUPPORTED_VIDEO"
        case .thumbnailFailed: return "THUMBNAIL_FAILED"
        }
    }

    public var message: String {
        switch self {
        case .notFound: return "The video file was not found at the specified path."
        case .unreadable: return "The video could not be read or has no video track."
        case .thumbnailFailed: return "Could not extract a frame from the video."
        }
    }
}

/// Lightweight video compressor backed by AVFoundation.
public struct LightCompressor {

    // MARK: - Nested types

    /// Represents a single video to compress.
    public struct Video {

        /// Per-video compression settings.
        public struct Configuration {
            public let quality: VideoQuality
            public let isMinBitrateCheckEnabled: Bool
            public let videoBitrateInMbps: Int?
            public let targetSizeBytes: Int?
            public let videoFps: Int?
            public let audioBitrate: Int?
            public let audioSampleRate: Int?
            public let disableAudio: Bool
            public let keepOriginalResolution: Bool
            public let videoSize: CGSize?
            public let videoFormat: VideoFormat
            public let twoPass: Bool
            public let trimStartMs: Int?
            public let trimEndMs: Int?
            public let rotationDegrees: Int?
            public let brightness: Double?
            public let contrast: Double?
            public let saturation: Double?
            // Phase 11a: max videos transcoded at once in a batch. nil starts
            // them all (the historic behaviour); a set value (>= 1) throttles.
            public let maxConcurrent: Int?

            public init(
                quality: VideoQuality = .medium,
                isMinBitrateCheckEnabled: Bool = true,
                videoBitrateInMbps: Int? = nil,
                disableAudio: Bool = false,
                keepOriginalResolution: Bool = false,
                videoSize: CGSize? = nil,
                videoFormat: VideoFormat = .h264,
                targetSizeBytes: Int? = nil,
                videoFps: Int? = nil,
                audioBitrate: Int? = nil,
                audioSampleRate: Int? = nil,
                twoPass: Bool = false,
                trimStartMs: Int? = nil,
                trimEndMs: Int? = nil,
                rotationDegrees: Int? = nil,
                brightness: Double? = nil,
                contrast: Double? = nil,
                saturation: Double? = nil,
                maxConcurrent: Int? = nil
            ) {
                self.quality = quality
                self.isMinBitrateCheckEnabled = isMinBitrateCheckEnabled
                self.videoBitrateInMbps = videoBitrateInMbps
                self.targetSizeBytes = targetSizeBytes
                self.videoFps = videoFps
                self.audioBitrate = audioBitrate
                self.audioSampleRate = audioSampleRate
                self.disableAudio = disableAudio
                self.keepOriginalResolution = keepOriginalResolution
                self.videoSize = videoSize
                self.videoFormat = videoFormat
                self.twoPass = twoPass
                self.trimStartMs = trimStartMs
                self.trimEndMs = trimEndMs
                self.rotationDegrees = rotationDegrees
                self.brightness = brightness
                self.contrast = contrast
                self.saturation = saturation
                self.maxConcurrent = maxConcurrent
            }
        }

        public let source: URL
        public let destination: URL
        public let configuration: Configuration

        public init(
            source: URL,
            destination: URL,
            configuration: Configuration = Configuration()
        ) {
            self.source = source
            self.destination = destination
            self.configuration = configuration
        }
    }

    // MARK: - Constants

    private static let MIN_BITRATE = Float(2_000_000)
    private static let MIN_HEIGHT  = 640.0
    private static let MIN_WIDTH   = 360.0

    /// Phase 8d: a two-pass run triggers a corrective second pass only when the
    /// first pass overshoots the target by more than this fraction.
    private static let TWO_PASS_TOLERANCE = 0.10

    // MARK: - Init

    public init() {}

    /// Deletes generated `.mp4` (compressed videos) and `.jpg` (thumbnails)
    /// files from the temporary directory. Shared by the iOS and macOS plugins.
    ///
    /// Note: compressed videos and thumbnails are written to the temporary
    /// directory, so calling this removes any such file that has not been
    /// moved/saved elsewhere.
    public static func clearCache() throws {
        let tempDir = NSTemporaryDirectory()
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir)
        for file in files where file.hasSuffix(".mp4") || file.hasSuffix(".jpg") {
            let filePath = (tempDir as NSString).appendingPathComponent(file)
            try FileManager.default.removeItem(atPath: filePath)
        }
    }

    /// Reads metadata (dimensions, duration, bitrate, rotation, frame rate)
    /// from the video at [path].
    ///
    /// - Returns: a dictionary matching the keys expected by `MediaInfo.fromMap`.
    /// - Throws: [MediaError.notFound] or [MediaError.unreadable].
    public static func mediaInfo(for path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MediaError.notFound
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw MediaError.unreadable
        }

        let naturalSize = track.naturalSize
        var info: [String: Any] = [
            "width": Int(abs(naturalSize.width)),
            "height": Int(abs(naturalSize.height)),
            "bitrate": Int(track.estimatedDataRate),
            "rotation": rotationDegrees(from: track.preferredTransform),
            "frameRate": Double(track.nominalFrameRate),
        ]

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
            info["durationMs"] = Int(durationSeconds * 1000.0)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = (attrs[.size] as? NSNumber)?.intValue {
            info["fileSize"] = size
        }
        if let mimeType = mimeType(for: url) {
            info["mimeType"] = mimeType
        }
        return info
    }

    /// Generates a JPEG thumbnail from the video at [path] and returns the
    /// absolute path of the written image.
    ///
    /// - Parameters:
    ///   - positionInMs: the timecode (clamped to the video duration) of the
    ///     frame to capture.
    ///   - quality: JPEG quality from 0 (smallest) to 100 (best).
    /// - Throws: [MediaError.notFound] or [MediaError.thumbnailFailed].
    public static func thumbnail(for path: String, positionInMs: Int, quality: Int) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MediaError.notFound
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        var seconds = Double(max(0, positionInMs)) / 1000.0
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
            seconds = min(seconds, max(0, durationSeconds - 0.05))
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            throw MediaError.thumbnailFailed
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb_\(UUID().uuidString).jpg")
        let clampedQuality = Double(min(max(quality, 0), 100)) / 100.0
        guard writeJPEG(cgImage, to: outURL, quality: clampedQuality) else {
            throw MediaError.thumbnailFailed
        }
        return outURL.path
    }

    /// Generates several thumbnails from one source in a single call, returning
    /// their file paths in the same order as [requests]. Each request is a map
    /// with `"positionInMs"` and `"quality"`.
    ///
    /// - Throws: [MediaError.notFound] or [MediaError.thumbnailFailed].
    static func thumbnails(for path: String, requests: [[String: Any]]) throws -> [String] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MediaError.notFound
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let durationSeconds = CMTimeGetSeconds(asset.duration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        var paths: [String] = []
        for request in requests {
            let positionInMs = max(0, (request["positionInMs"] as? Int) ?? 0)
            let quality = min(max((request["quality"] as? Int) ?? 50, 0), 100)
            var seconds = Double(positionInMs) / 1000.0
            if durationSeconds.isFinite && durationSeconds > 0 {
                seconds = min(seconds, max(0, durationSeconds - 0.05))
            }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                throw MediaError.thumbnailFailed
            }
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("thumb_\(UUID().uuidString).jpg")
            guard writeJPEG(cgImage, to: outURL, quality: Double(quality) / 100.0) else {
                throw MediaError.thumbnailFailed
            }
            paths.append(outURL.path)
        }
        return paths
    }

    /// Predicts the output of compressing the video at [path] **without**
    /// transcoding it, reusing the same bitrate and resize math as
    /// `compressVideo`. The figures are approximate.
    ///
    /// - Returns: a dictionary matching the keys parsed by `CompressionEstimate`.
    /// - Throws: [MediaError.notFound] or [MediaError.unreadable].
    func estimate(
        for path: String,
        quality: VideoQuality,
        keepOriginalResolution: Bool,
        videoSize: CGSize?,
        videoBitrateInMbps: Int?,
        disableAudio: Bool
    ) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MediaError.notFound
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw MediaError.unreadable
        }

        let naturalSize = track.naturalSize
        let durationSeconds = max(0, CMTimeGetSeconds(asset.duration))

        // Output resolution — identical to compressVideo.
        let size: (width: Int, height: Int) = videoSize == nil
            ? generateWidthAndHeight(
                width: naturalSize.width,
                height: naturalSize.height,
                keepOriginalResolution: keepOriginalResolution)
            : (Int(videoSize!.width), Int(videoSize!.height))

        // Target video bitrate — the same value compressVideo would request.
        let targetBitrate = videoBitrateInMbps == nil
            ? getBitrate(bitrate: track.estimatedDataRate, quality: quality)
            : videoBitrateInMbps! * 1_000_000

        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        let audioBitrate = (disableAudio || !hasAudio) ? 0 : 128_000

        let estimatedSize = Int(
            (Double(targetBitrate + audioBitrate) / 8.0 * durationSeconds * 1.02).rounded())
        let originalSize = (try? FileManager.default
            .attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        let ratio = originalSize > 0
            ? min(100.0, max(0.0, (1.0 - Double(estimatedSize) / Double(originalSize)) * 100.0))
            : 0.0

        return [
            "originalSizeBytes": originalSize,
            "estimatedSizeBytes": estimatedSize,
            "targetBitrate": targetBitrate,
            "outputWidth": size.width,
            "outputHeight": size.height,
            "estimatedRatio": ratio,
        ]
    }

    // MARK: - Media helpers

    /// Writes [image] as JPEG to [url] using ImageIO (available on iOS & macOS).
    private static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.jpeg" as CFString, 1, nil
        ) else {
            return false
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Derives rotation degrees (0/90/180/270) from a track's preferred transform.
    private static func rotationDegrees(from transform: CGAffineTransform) -> Int {
        let angle = atan2(transform.b, transform.a)
        var degrees = Int(round(angle * 180 / .pi))
        degrees %= 360
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Best-effort MIME type derived from the file extension.
    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov", "qt": return "video/quicktime"
        case "3gp": return "video/3gpp"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        default: return nil
        }
    }

    // MARK: - Public API

    /// Compresses one or more videos sequentially.
    ///
    /// - Parameters:
    ///   - videos: The list of videos to compress.
    ///   - progressQueue: The queue on which `progressHandler` is called. Defaults to `.main`.
    ///   - progressHandler: Called repeatedly with the video index and its current `Progress`.
    ///   - completion: Called with the `CompressionResult` for each video.
    /// - Returns: A `Compression` handle that can be used to cancel the operation.
    public func compressVideo(
        videos: [Video],
        progressQueue: DispatchQueue = .main,
        progressHandler: ((Int, Progress) -> Void)?,
        completion: @escaping (CompressionResult) -> Void
    ) -> Compression {
        let compressionOperation = Compression()
        guard !videos.isEmpty else { return compressionOperation }

        // Phase 11a: cap how many videos transcode at once. nil keeps the
        // historic behaviour (start them all); a set value (>= 1) throttles.
        // All scheduler state below is mutated only on `scheduler` (serial).
        let count = videos.count
        let limit = max(1, videos.first?.configuration.maxConcurrent ?? count)
        let scheduler = DispatchQueue(label: "com.lightcompressor.batchScheduler")
        var nextIndex = 0
        var inFlight = 0

        // Transcodes one video (the whole pass-1/pass-2 flow) and calls `onDone`
        // exactly once when it reaches a terminal state, freeing its slot.
        func startVideo(_ index: Int, _ video: Video, onDone: @escaping () -> Void) {
            let source        = video.source
            let destination   = video.destination
            let configuration = video.configuration

            completion(.onStart)

            let videoAsset = AVURLAsset(url: source)

            guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
                completion(.onFailure(index, CompressionError(
                    title: "Cannot find video track", type: .unsupported)))
                onDone()
                return
            }

            let bitrate = videoTrack.estimatedDataRate

            if configuration.isMinBitrateCheckEnabled && bitrate <= Self.MIN_BITRATE {
                completion(.onFailure(index, CompressionError(
                    title: "Bitrate is too low for compression. Set isMinBitrateCheckEnabled to false to skip this check."
                )))
                onDone()
                return
            }

            let videoSize = videoTrack.naturalSize
            let size: (width: Int, height: Int) = configuration.videoSize == nil
                ? generateWidthAndHeight(
                    width: videoSize.width,
                    height: videoSize.height,
                    keepOriginalResolution: configuration.keepOriginalResolution)
                : (Int(configuration.videoSize!.width), Int(configuration.videoSize!.height))

            // Native editing (Phase 9a): resolve the kept time range. The output
            // timeline is rebased to 0 (startSession at trimRange.start), so the
            // reported duration, the size solver and the progress denominator all
            // use the trimmed length. trimRange stays nil when no trim is asked.
            let fullDuration = videoAsset.duration
            let trimRange: CMTimeRange?
            if configuration.trimStartMs != nil || configuration.trimEndMs != nil {
                let start = min(
                    CMTime(
                        value: CMTimeValue(max(0, configuration.trimStartMs ?? 0)),
                        timescale: 1000),
                    fullDuration)
                let end = configuration.trimEndMs
                    .map { min(CMTime(value: CMTimeValue($0), timescale: 1000), fullDuration) }
                    ?? fullDuration
                trimRange = CMTimeRange(start: start, end: end)
            } else {
                trimRange = nil
            }
            let durationInSeconds = trimRange
                .map { max(0.0, CMTimeGetSeconds($0.duration)) } ?? fullDuration.seconds

            // Choose the target video bitrate. Precedence: an explicit
            // videoBitrateInMbps wins; else a requested target output size is
            // solved for (computed after `size` so the floor scales to the
            // output resolution); else the quality preset is used.
            var targetSizeMet = true
            let newBitrate: Int
            if let mbps = configuration.videoBitrateInMbps {
                newBitrate = mbps * 1_000_000
            } else if let targetBytes = configuration.targetSizeBytes {
                let solved = solveTargetBitrate(
                    targetSizeBytes: targetBytes,
                    durationSeconds: durationInSeconds,
                    sourceBitrate: bitrate,
                    disableAudio: configuration.disableAudio,
                    hasAudio: !videoAsset.tracks(withMediaType: .audio).isEmpty)
                newBitrate = solved.bitrate
                targetSizeMet = solved.met
            } else {
                newBitrate = getBitrate(bitrate: bitrate, quality: configuration.quality)
            }

            let frameRate         = videoTrack.nominalFrameRate
            let totalFrames       = ceil(durationInSeconds * Double(frameRate))

            // Frame-rate downsampling (8b): drop frames toward videoFps when it
            // is below the source rate (never duplicate). Disabled otherwise.
            let sourceFps = Double(frameRate)
            let frameDropEnabled = configuration.videoFps != nil
                && configuration.videoFps! > 0
                && (sourceFps <= 0 || Double(configuration.videoFps!) < sourceFps)
            let frameIntervalSeconds =
                frameDropEnabled ? 1.0 / Double(configuration.videoFps!) : 0.0

            // Resolve the output codec: use H.265 only when requested AND the
            // device supports HEVC encoding; otherwise fall back to H.264.
            let resolvedFormat: VideoFormat =
                (configuration.videoFormat == .h265 && Self.isHEVCEncodingSupported()) ? .h265 : .h264

            // Phase 8d: two-pass. Enabled only when requested AND a target size
            // was set AND it is reachable (a floor-bound pass 1 can't be improved
            // by a lower bitrate). Pass 1 encodes at the solved bitrate; if it
            // overshoots, pass 2 re-encodes at a corrected (lower) bitrate.
            let twoPassEnabled =
                configuration.twoPass && configuration.targetSizeBytes != nil && targetSizeMet
            let targetBytes = configuration.targetSizeBytes ?? 0
            let floor = min(Double(Self.MIN_BITRATE), Double(bitrate))

            // Reports the terminal result for this video and frees its slot.
            // The single funnel for the encode path; validation failures above
            // call onDone() directly (they precede the values finish() needs).
            func finish(_ outcome: PassOutcome, passesUsed: Int) {
                switch outcome {
                case .cancelled:
                    completion(.onCancelled)
                case .failure(let error):
                    completion(.onFailure(index, error))
                case .success(let url):
                    completion(.onSuccess(
                        index, url, durationInSeconds, resolvedFormat,
                        targetSizeMet, passesUsed))
                }
                onDone()
            }

            // Pass 1.
            encodePass(
                index: index, videoAsset: videoAsset, videoTrack: videoTrack,
                size: size, bitrate: newBitrate, resolvedFormat: resolvedFormat,
                frameDropEnabled: frameDropEnabled,
                frameIntervalSeconds: frameIntervalSeconds, totalFrames: totalFrames,
                trimRange: trimRange,
                configuration: configuration, destination: destination,
                compressionOperation: compressionOperation,
                progressQueue: progressQueue, progressHandler: progressHandler
            ) { outcome in
                guard case .success(let url) = outcome else {
                    finish(outcome, passesUsed: 1)
                    return
                }

                // Decide whether a corrective second pass is warranted.
                let actualBytes = Self.fileSize(url)
                guard twoPassEnabled,
                      !compressionOperation.cancel,
                      Double(actualBytes) > Double(targetBytes) * (1.0 + Self.TWO_PASS_TOLERANCE)
                else {
                    finish(.success(url), passesUsed: 1)
                    return
                }
                let adjusted = min(
                    max(Double(newBitrate) * Double(targetBytes) / Double(actualBytes), floor),
                    Double(bitrate))
                // Skip pass 2 when it can't lower the bitrate (already at floor).
                guard Int(adjusted) < newBitrate else {
                    finish(.success(url), passesUsed: 1)
                    return
                }

                // Pass 2 writes to a temp; the valid pass-1 output is kept until
                // pass 2 succeeds, then replaced.
                let tempDest = destination.deletingPathExtension()
                    .appendingPathExtension("p2").appendingPathExtension("mp4")
                try? FileManager.default.removeItem(at: tempDest)

                self.encodePass(
                    index: index, videoAsset: videoAsset, videoTrack: videoTrack,
                    size: size, bitrate: Int(adjusted), resolvedFormat: resolvedFormat,
                    frameDropEnabled: frameDropEnabled,
                    frameIntervalSeconds: frameIntervalSeconds, totalFrames: totalFrames,
                    trimRange: trimRange,
                    configuration: configuration, destination: tempDest,
                    compressionOperation: compressionOperation,
                    progressQueue: progressQueue, progressHandler: progressHandler
                ) { outcome2 in
                    switch outcome2 {
                    case .cancelled:
                        try? FileManager.default.removeItem(at: tempDest)
                        finish(.cancelled, passesUsed: 2)
                    case .failure:
                        // Pass 2 failed — keep the valid pass-1 output.
                        try? FileManager.default.removeItem(at: tempDest)
                        finish(.success(destination), passesUsed: 2)
                    case .success:
                        try? FileManager.default.removeItem(at: destination)
                        try? FileManager.default.moveItem(at: tempDest, to: destination)
                        finish(.success(destination), passesUsed: 2)
                    }
                }
            }
        }

        // Pump: start up to `limit` videos now; each finishing video releases
        // its slot and starts the next queued one. Runs entirely on `scheduler`
        // (off the caller thread), so this method returns the handle at once.
        // Every video is started even after a cancel, so each one still reports
        // a terminal result (a cancelled pass returns quickly) — the batch
        // caller relies on exactly one reply per index to know it is done.
        func startNext() {
            while inFlight < limit && nextIndex < count {
                let index = nextIndex
                nextIndex += 1
                inFlight += 1
                startVideo(index, videos[index]) {
                    scheduler.async {
                        inFlight -= 1
                        startNext()
                    }
                }
            }
        }
        scheduler.async { startNext() }

        return compressionOperation
    }

    // MARK: - Two-pass support (Phase 8d)

    /// The outcome of a single transcode pass.
    private enum PassOutcome {
        case success(URL)
        case failure(CompressionError)
        case cancelled
    }

    /// File size in bytes at [url], or 0 when it cannot be read.
    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    }

    /// Runs one full transcode pass at [bitrate], writing to [destination], and
    /// reports the outcome via [onPassComplete]. Phase 8d calls this once, or a
    /// second time at a corrected bitrate when the first pass overshot the target.
    /// Progress is reported as 0..<100 (never the terminal 100) so a two-pass run
    /// does not signal "done" between passes; completion is the `onPassComplete`
    /// callback, mirroring Android.
    private func encodePass(
        index: Int,
        videoAsset: AVURLAsset,
        videoTrack: AVAssetTrack,
        size: (width: Int, height: Int),
        bitrate: Int,
        resolvedFormat: VideoFormat,
        frameDropEnabled: Bool,
        frameIntervalSeconds: Double,
        totalFrames: Double,
        trimRange: CMTimeRange?,
        configuration: Video.Configuration,
        destination: URL,
        compressionOperation: Compression,
        progressQueue: DispatchQueue,
        progressHandler: ((Int, Progress) -> Void)?,
        onPassComplete: @escaping (PassOutcome) -> Void
    ) {
        var frameCount = 0
        let progress = Progress(totalUnitCount: Int64(totalFrames))
        var nextEmitSeconds = 0.0
        // Cap progress just below the total so fractionCompleted never reaches
        // 1.0 (100%); the terminal signal is onPassComplete, not a 100 event.
        let progressCap = max(Int64(totalFrames) - 1, 0)

        // Video writer
        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: getVideoWriterSettings(
                bitrate: bitrate,
                width: size.width,
                height: size.height,
                format: resolvedFormat))
        videoWriterInput.expectsMediaDataInRealTime = true
        // Rotate (9b): compose the requested quarter-turn onto the source
        // orientation (cheap container-metadata rotation).
        var outputTransform = videoTrack.preferredTransform
        if let deg = configuration.rotationDegrees, deg != 0 {
            outputTransform = outputTransform.concatenating(
                CGAffineTransform(rotationAngle: CGFloat(Double(deg) * .pi / 180.0)))
        }
        videoWriterInput.transform = outputTransform

        // .mp4 container to match the .mp4 output filename — important for
        // HEVC interop with players/Android that key off the extension.
        guard let videoWriter = try? AVAssetWriter(outputURL: destination, fileType: .mp4) else {
            onPassComplete(.failure(CompressionError(title: "Failed to create video writer")))
            return
        }
        videoWriter.add(videoWriterInput)

        // Video reader
        let videoReaderSettings: [String: AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) as AnyObject
        ]
        // Color adjust (Phase 9c): when any color knob is set, read through a
        // video composition that applies CIColorControls; otherwise keep the
        // cheap track output. Identity = brightness 0, contrast 1, saturation 1.
        let videoReaderOutput: AVAssetReaderOutput
        if configuration.brightness != nil || configuration.contrast != nil
            || configuration.saturation != nil {
            let brightness = configuration.brightness ?? 0
            let contrast = configuration.contrast ?? 1
            let saturation = configuration.saturation ?? 1
            let composition = AVVideoComposition(
                asset: videoAsset,
                applyingCIFiltersWithHandler: { request in
                    let filter = CIFilter(name: "CIColorControls")
                    filter?.setValue(
                        request.sourceImage.clampedToExtent(), forKey: kCIInputImageKey)
                    filter?.setValue(brightness, forKey: kCIInputBrightnessKey)
                    filter?.setValue(contrast, forKey: kCIInputContrastKey)
                    filter?.setValue(saturation, forKey: kCIInputSaturationKey)
                    let filtered = filter?.outputImage?
                        .cropped(to: request.sourceImage.extent) ?? request.sourceImage
                    request.finish(with: filtered, context: nil)
                })
            let compOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack], videoSettings: videoReaderSettings)
            compOutput.videoComposition = composition
            videoReaderOutput = compOutput
        } else {
            videoReaderOutput = AVAssetReaderTrackOutput(
                track: videoTrack, outputSettings: videoReaderSettings)
        }

        guard let videoReader = try? AVAssetReader(asset: videoAsset) else {
            onPassComplete(.failure(CompressionError(title: "Failed to create video reader")))
            return
        }
        videoReader.add(videoReaderOutput)
        // Trim (9a): restrict the read to the kept range; the output is rebased
        // to 0 via startSession below.
        if let trimRange { videoReader.timeRange = trimRange }

        // Audio setup — only wire up an audio input when there is audio to
        // copy and it isn't disabled. Adding an input that is never fed and
        // never marked finished can stall AVAssetWriter.finishWriting.
        let audioTrack = configuration.disableAudio
            ? nil
            : videoAsset.tracks(withMediaType: .audio).first
        // Re-encode the audio to AAC when a bitrate/sample-rate was requested
        // (8c); otherwise copy the source samples through untouched (nil).
        let reEncodeAudio = !configuration.disableAudio
            && (configuration.audioBitrate != nil
                || configuration.audioSampleRate != nil)
        var audioWriterInput: AVAssetWriterInput?
        var audioReader: AVAssetReader?
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            var writerSettings: [String: Any]?
            var readerSettings: [String: Any]?
            if reEncodeAudio {
                // Default channels + sample rate from the source track.
                var channels = 2
                var srcSampleRate = 44100.0
                let descs = audioTrack.formatDescriptions as! [CMAudioFormatDescription]
                if let desc = descs.first,
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                        desc)?.pointee {
                    if asbd.mChannelsPerFrame > 0 { channels = Int(asbd.mChannelsPerFrame) }
                    if asbd.mSampleRate > 0 { srcSampleRate = asbd.mSampleRate }
                }
                var aac: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVNumberOfChannelsKey: channels,
                    AVSampleRateKey: configuration.audioSampleRate ?? Int(srcSampleRate),
                ]
                if let bitrate = configuration.audioBitrate {
                    aac[AVEncoderBitRateKey] = bitrate
                }
                writerSettings = aac
                // The reader must decompress to PCM so the writer can re-encode.
                readerSettings = [AVFormatIDKey: Int(kAudioFormatLinearPCM)]
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            input.expectsMediaDataInRealTime = false
            videoWriter.add(input)
            audioWriterInput = input
            audioReaderOutput = AVAssetReaderTrackOutput(
                track: audioTrack, outputSettings: readerSettings)
            audioReader = try? AVAssetReader(asset: videoAsset)
            audioReader?.add(audioReaderOutput!)
            if let trimRange { audioReader?.timeRange = trimRange }
        }

        videoWriter.startWriting()
        videoReader.startReading()
        videoWriter.startSession(atSourceTime: trimRange?.start ?? .zero)

        var isFirstBuffer = true
        let processingQueue = DispatchQueue(label: "processingQueue1", qos: .background)

        videoWriterInput.requestMediaDataWhenReady(on: processingQueue) {
            while videoWriterInput.isReadyForMoreMediaData {

                // Handle cancellation
                if compressionOperation.cancel {
                    videoReader.cancelReading()
                    videoWriter.cancelWriting()
                    onPassComplete(.cancelled)
                    return
                }

                // Update progress (capped just below 100%).
                frameCount += 1
                if let handler = progressHandler {
                    progress.completedUnitCount = min(Int64(frameCount), progressCap)
                    progressQueue.async { handler(index, progress) }
                }

                let sampleBuffer = videoReaderOutput.copyNextSampleBuffer()

                if videoReader.status == .reading, let sampleBuffer {
                    // Frame-rate downsampling (8b): append the frame only once
                    // its timestamp reaches the next emit point; otherwise drop
                    // it (don't append) so it never reaches the encoder.
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    if !frameDropEnabled || !pts.isFinite || pts >= nextEmitSeconds {
                        if frameDropEnabled { nextEmitSeconds += frameIntervalSeconds }
                        videoWriterInput.append(sampleBuffer)
                    }
                } else {
                    videoWriterInput.markAsFinished()

                    guard videoReader.status == .completed else { return }

                    if let audioReader, let audioReaderOutput, let audioWriterInput,
                       audioReader.status != .reading, audioReader.status != .completed {

                        audioReader.startReading()
                        videoWriter.startSession(atSourceTime: trimRange?.start ?? .zero)

                        let audioQueue = DispatchQueue(label: "processingQueue2", qos: .background)
                        audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                            while audioWriterInput.isReadyForMoreMediaData {
                                let audioBuffer = audioReaderOutput.copyNextSampleBuffer()

                                if audioReader.status == .reading, let audioBuffer {
                                    if isFirstBuffer {
                                        // AAC passthrough: trim the encoder
                                        // priming samples at the start. When
                                        // re-encoding, the writer's encoder
                                        // handles priming itself.
                                        if !reEncodeAudio {
                                            let dict = CMTimeCopyAsDictionary(
                                                CMTimeMake(value: 1024, timescale: 44100),
                                                allocator: kCFAllocatorDefault)
                                            CMSetAttachment(
                                                audioBuffer as CMAttachmentBearer,
                                                key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                                                value: dict,
                                                attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                                        }
                                        isFirstBuffer = false
                                    }
                                    audioWriterInput.append(audioBuffer)
                                } else {
                                    audioWriterInput.markAsFinished()
                                    videoWriter.finishWriting {
                                        DispatchQueue.main.async {
                                            if videoWriter.status == .completed {
                                                onPassComplete(.success(destination))
                                            } else {
                                                onPassComplete(.failure(CompressionError(
                                                    title: videoWriter.error?.localizedDescription ?? "Video writing failed")))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        videoWriter.finishWriting {
                            DispatchQueue.main.async {
                                if videoWriter.status == .completed {
                                    onPassComplete(.success(destination))
                                } else {
                                    onPassComplete(.failure(CompressionError(
                                        title: videoWriter.error?.localizedDescription ?? "Video writing failed")))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private helpers

    private func getBitrate(bitrate: Float, quality: VideoQuality) -> Int {
        switch quality {
        case .very_high: return Int(bitrate * 0.6)
        case .high:      return Int(bitrate * 0.4)
        case .medium:    return Int(bitrate * 0.3)
        case .low:       return Int(bitrate * 0.2)
        case .very_low:  return Int(bitrate * 0.1)
        }
    }

    /// Solves for the video bitrate (bps) that lands the output at/under
    /// [targetSizeBytes], reserving room for audio (a 128 kbps estimate) + ~3%
    /// container overhead, then clamps to a resolution-scaled floor (so HD is
    /// not crushed) capped at the source bitrate (never upscale). `met` is false
    /// when the floor forced the output above the requested size.
    private func solveTargetBitrate(
        targetSizeBytes: Int,
        durationSeconds: Double,
        sourceBitrate: Float,
        disableAudio: Bool,
        hasAudio: Bool
    ) -> (bitrate: Int, met: Bool) {
        let audioBps = (disableAudio || !hasAudio) ? 0.0 : 128_000.0
        let totalBudgetBits = Double(targetSizeBytes) * 8.0
        let audioBits = audioBps * durationSeconds
        let videoBudgetBits = totalBudgetBits * 0.97 - audioBits
        let solvedBps = durationSeconds > 0 ? videoBudgetBits / durationSeconds : 0.0
        let source = Double(sourceBitrate)
        // Quality floor: keep at least MIN_BITRATE but never exceed the source
        // (a sub-floor source can't be compressed further). A target below this
        // lands at the floor and reports met = false.
        let floor = min(Double(Self.MIN_BITRATE), source)
        let met = solvedBps >= floor
        let clamped = min(max(solvedBps, floor), source)
        return (Int(clamped), met)
    }

    private func generateWidthAndHeight(
        width: CGFloat,
        height: CGFloat,
        keepOriginalResolution: Bool
    ) -> (width: Int, height: Int) {
        guard !keepOriginalResolution else {
            return (Int(width), Int(height))
        }

        let newWidth: Int
        let newHeight: Int

        if width >= 1920 || height >= 1920 {
            newWidth  = Int(width  * 0.5 / 16) * 16
            newHeight = Int(height * 0.5 / 16) * 16
        } else if width >= 1280 || height >= 1280 {
            newWidth  = Int(width  * 0.75 / 16) * 16
            newHeight = Int(height * 0.75 / 16) * 16
        } else if width >= 960 || height >= 960 {
            if width > height {
                newWidth  = Int(Self.MIN_HEIGHT * 0.95 / 16) * 16
                newHeight = Int(Self.MIN_WIDTH  * 0.95 / 16) * 16
            } else {
                newWidth  = Int(Self.MIN_WIDTH  * 0.95 / 16) * 16
                newHeight = Int(Self.MIN_HEIGHT * 0.95 / 16) * 16
            }
        } else {
            newWidth  = Int(width  * 0.9 / 16) * 16
            newHeight = Int(height * 0.9 / 16) * 16
        }

        return (newWidth, newHeight)
    }

    /// Whether this device supports hardware HEVC (H.265) **encoding**. The
    /// platform's advertised export presets include the HEVC presets only when
    /// an HEVC encoder is available, which makes this a reliable capability probe.
    private static func isHEVCEncodingSupported() -> Bool {
        AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
    }

    private func getVideoWriterSettings(bitrate: Int, width: Int, height: Int, format: VideoFormat) -> [String: AnyObject] {
        // NOTE: the frame rate is reduced by actually dropping source frames in
        // the writer loop (see frameDropEnabled). We deliberately do NOT set
        // AVVideoExpectedSourceFrameRateKey / AVVideoAverageNonDroppableFrameRateKey
        // here — they are only encoder hints, and the iOS simulator's software
        // encoder stalls when they are present, hanging the compression.
        let compressionSettings: [String: AnyObject] = [
            AVVideoAverageBitRateKey: bitrate as AnyObject
        ]
        let codec: AVVideoCodecType = (format == .h265) ? .hevc : .h264
        return [
            AVVideoCodecKey:                  codec as AnyObject,
            AVVideoCompressionPropertiesKey:  compressionSettings as AnyObject,
            AVVideoWidthKey:                  width  as AnyObject,
            AVVideoHeightKey:                 height as AnyObject,
        ]
    }
}