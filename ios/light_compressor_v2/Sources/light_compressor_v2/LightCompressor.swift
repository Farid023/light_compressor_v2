import AVFoundation
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
    /// duration in seconds, and the codec actually used (which may differ from
    /// the requested one if H.265 fell back to H.264).
    case onSuccess(Int, URL, Double, VideoFormat)
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
            public let disableAudio: Bool
            public let keepOriginalResolution: Bool
            public let videoSize: CGSize?
            public let videoFormat: VideoFormat

            public init(
                quality: VideoQuality = .medium,
                isMinBitrateCheckEnabled: Bool = true,
                videoBitrateInMbps: Int? = nil,
                disableAudio: Bool = false,
                keepOriginalResolution: Bool = false,
                videoSize: CGSize? = nil,
                videoFormat: VideoFormat = .h264
            ) {
                self.quality = quality
                self.isMinBitrateCheckEnabled = isMinBitrateCheckEnabled
                self.videoBitrateInMbps = videoBitrateInMbps
                self.disableAudio = disableAudio
                self.keepOriginalResolution = keepOriginalResolution
                self.videoSize = videoSize
                self.videoFormat = videoFormat
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

        for (index, video) in videos.enumerated() {
            // Reset frame count per video so progress is accurate.
            var frameCount = 0

            let source        = video.source
            let destination   = video.destination
            let configuration = video.configuration

            completion(.onStart)

            let videoAsset = AVURLAsset(url: source)

            guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
                completion(.onFailure(index, CompressionError(
                    title: "Cannot find video track", type: .unsupported)))
                continue
            }

            let bitrate = videoTrack.estimatedDataRate

            if configuration.isMinBitrateCheckEnabled && bitrate <= Self.MIN_BITRATE {
                completion(.onFailure(index, CompressionError(
                    title: "Bitrate is too low for compression. Set isMinBitrateCheckEnabled to false to skip this check."
                )))
                continue
            }

            let newBitrate = configuration.videoBitrateInMbps == nil
                ? getBitrate(bitrate: bitrate, quality: configuration.quality)
                : configuration.videoBitrateInMbps! * 1_000_000

            let videoSize = videoTrack.naturalSize
            let size: (width: Int, height: Int) = configuration.videoSize == nil
                ? generateWidthAndHeight(
                    width: videoSize.width,
                    height: videoSize.height,
                    keepOriginalResolution: configuration.keepOriginalResolution)
                : (Int(configuration.videoSize!.width), Int(configuration.videoSize!.height))

            let durationInSeconds = videoAsset.duration.seconds
            let frameRate         = videoTrack.nominalFrameRate
            let totalFrames       = ceil(durationInSeconds * Double(frameRate))
            let progress          = Progress(totalUnitCount: Int64(totalFrames))

            // Resolve the output codec: use H.265 only when requested AND the
            // device supports HEVC encoding; otherwise fall back to H.264.
            let resolvedFormat: VideoFormat =
                (configuration.videoFormat == .h265 && Self.isHEVCEncodingSupported()) ? .h265 : .h264

            // Video writer
            let videoWriterInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: getVideoWriterSettings(
                    bitrate: newBitrate,
                    width: size.width,
                    height: size.height,
                    format: resolvedFormat))
            videoWriterInput.expectsMediaDataInRealTime = true
            videoWriterInput.transform = videoTrack.preferredTransform

            guard let videoWriter = try? AVAssetWriter(outputURL: destination, fileType: .mov) else {
                completion(.onFailure(index, CompressionError(title: "Failed to create video writer")))
                continue
            }
            videoWriter.add(videoWriterInput)

            // Video reader
            let videoReaderSettings: [String: AnyObject] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) as AnyObject
            ]
            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)

            guard let videoReader = try? AVAssetReader(asset: videoAsset) else {
                completion(.onFailure(index, CompressionError(title: "Failed to create video reader")))
                continue
            }
            videoReader.add(videoReaderOutput)

            // Audio setup
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioWriterInput.expectsMediaDataInRealTime = false
            videoWriter.add(audioWriterInput)

            let audioTrack = videoAsset.tracks(withMediaType: .audio).first
            var audioReader: AVAssetReader?
            var audioReaderOutput: AVAssetReaderTrackOutput?
            if let audioTrack {
                audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                audioReader = try? AVAssetReader(asset: videoAsset)
                audioReader?.add(audioReaderOutput!)
            }

            videoWriter.startWriting()
            videoReader.startReading()
            videoWriter.startSession(atSourceTime: .zero)

            var isFirstBuffer = true
            let processingQueue = DispatchQueue(label: "processingQueue1", qos: .background)

            videoWriterInput.requestMediaDataWhenReady(on: processingQueue) {
                while videoWriterInput.isReadyForMoreMediaData {

                    // Handle cancellation
                    if compressionOperation.cancel {
                        videoReader.cancelReading()
                        videoWriter.cancelWriting()
                        completion(.onCancelled)
                        return
                    }

                    // Update progress
                    frameCount += 1
                    if let handler = progressHandler {
                        progress.completedUnitCount = Int64(frameCount)
                        progressQueue.async { handler(index, progress) }
                    }

                    let sampleBuffer = videoReaderOutput.copyNextSampleBuffer()

                    if videoReader.status == .reading, let sampleBuffer {
                        videoWriterInput.append(sampleBuffer)
                    } else {
                        videoWriterInput.markAsFinished()

                        guard videoReader.status == .completed else { return }

                        if let audioReader, let audioReaderOutput, !configuration.disableAudio,
                           audioReader.status != .reading, audioReader.status != .completed {

                            audioReader.startReading()
                            videoWriter.startSession(atSourceTime: .zero)

                            let audioQueue = DispatchQueue(label: "processingQueue2", qos: .background)
                            audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                                while audioWriterInput.isReadyForMoreMediaData {
                                    let audioBuffer = audioReaderOutput.copyNextSampleBuffer()

                                    if audioReader.status == .reading, let audioBuffer {
                                        if isFirstBuffer {
                                            let dict = CMTimeCopyAsDictionary(
                                                CMTimeMake(value: 1024, timescale: 44100),
                                                allocator: kCFAllocatorDefault)
                                            CMSetAttachment(
                                                audioBuffer as CMAttachmentBearer,
                                                key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                                                value: dict,
                                                attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                                            isFirstBuffer = false
                                        }
                                        audioWriterInput.append(audioBuffer)
                                    } else {
                                        audioWriterInput.markAsFinished()
                                        videoWriter.finishWriting {
                                            DispatchQueue.main.async {
                                                completion(.onSuccess(index, destination, durationInSeconds, resolvedFormat))
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            videoWriter.finishWriting {
                                DispatchQueue.main.async {
                                    completion(.onSuccess(index, destination, durationInSeconds, resolvedFormat))
                                }
                            }
                        }
                    }
                }
            }
        }

        return compressionOperation
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