import AVFoundation

/// Desired quality level for video compression.
public enum VideoQuality {
    case very_high
    case high
    case medium
    case low
    case very_low
}

/// The result of a compression operation.
public enum CompressionResult {
    /// Compression has started.
    case onStart
    /// Compression succeeded. Contains the video index, output URL, and video duration in seconds.
    case onSuccess(Int, URL, Double)
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

            public init(
                quality: VideoQuality = .medium,
                isMinBitrateCheckEnabled: Bool = true,
                videoBitrateInMbps: Int? = nil,
                disableAudio: Bool = false,
                keepOriginalResolution: Bool = false,
                videoSize: CGSize? = nil
            ) {
                self.quality = quality
                self.isMinBitrateCheckEnabled = isMinBitrateCheckEnabled
                self.videoBitrateInMbps = videoBitrateInMbps
                self.disableAudio = disableAudio
                self.keepOriginalResolution = keepOriginalResolution
                self.videoSize = videoSize
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

    /// Deletes all `.mp4` files in the temporary directory used for compression
    /// output. Shared by the iOS and macOS plugins.
    ///
    /// Note: compressed videos are written to the temporary directory, so calling
    /// this removes any compressed file that has not been moved/saved elsewhere.
    public static func clearCache() throws {
        let tempDir = NSTemporaryDirectory()
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir)
        for file in files where file.hasSuffix(".mp4") {
            let filePath = (tempDir as NSString).appendingPathComponent(file)
            try FileManager.default.removeItem(atPath: filePath)
        }
    }

    // MARK: - Public API

    /// Compresses one or more videos sequentially.
    ///
    /// - Parameters:
    ///   - videos: The list of videos to compress.
    ///   - progressQueue: The queue on which `progressHandler` is called. Defaults to `.main`.
    ///   - progressHandler: Called repeatedly with the current `Progress` object.
    ///   - completion: Called with the `CompressionResult` for each video.
    /// - Returns: A `Compression` handle that can be used to cancel the operation.
    public func compressVideo(
        videos: [Video],
        progressQueue: DispatchQueue = .main,
        progressHandler: ((Progress) -> Void)?,
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

            // Video writer
            let videoWriterInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: getVideoWriterSettings(
                    bitrate: newBitrate,
                    width: size.width,
                    height: size.height))
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
                        progressQueue.async { handler(progress) }
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
                                                completion(.onSuccess(index, destination, durationInSeconds))
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            videoWriter.finishWriting {
                                DispatchQueue.main.async {
                                    completion(.onSuccess(index, destination, durationInSeconds))
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

    private func getVideoWriterSettings(bitrate: Int, width: Int, height: Int) -> [String: AnyObject] {
        let compressionSettings: [String: AnyObject] = [
            AVVideoAverageBitRateKey: bitrate as AnyObject
        ]
        return [
            AVVideoCodecKey:                  AVVideoCodecType.h264 as AnyObject,
            AVVideoCompressionPropertiesKey:  compressionSettings as AnyObject,
            AVVideoWidthKey:                  width  as AnyObject,
            AVVideoHeightKey:                 height as AnyObject,
        ]
    }
}