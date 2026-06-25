package com.gurfdev.light_compressor_v2.lightcompressorlibrary.compressor

import android.content.Context
import android.media.*
import android.net.Uri
import android.os.Build
import android.util.Log
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.CompressionErrorType
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.CompressionProgressListener
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.VideoFormat
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.config.Configuration
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.findTrack
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.isHevcHardwareEncoderAvailable
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.getBitrate
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.prepareVideoHeight
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.prepareVideoWidth
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.printException
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.CompressorUtils.setOutputFileParameters
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils.roundDimension
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.video.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

object Compressor {

    // 2Mbps
    private const val MIN_BITRATE = 2000000

    // H.264 Advanced Video Coding
    private const val MIME_TYPE = "video/avc"
    // H.265 High Efficiency Video Coding
    private const val HEVC_MIME = "video/hevc"
    private const val MEDIACODEC_TIMEOUT_DEFAULT = 100L

    private const val INVALID_BITRATE =
        "The provided bitrate is smaller than what is needed for compression " +
                "try to set isMinBitRateEnabled to false"

    @Volatile
    var isRunning = true

    suspend fun compressVideo(
        index: Int,
        context: Context,
        srcUri: Uri,
        destination: String,
        configuration: Configuration,
        listener: CompressionProgressListener,
    ): Result = withContext(Dispatchers.Default) {

        val extractor = MediaExtractor()
        // Retrieve the source's metadata to be used as input to generate new values for compression
        val mediaMetadataRetriever = MediaMetadataRetriever()

        val file = File(srcUri.path ?: "")
        if (!file.exists() || file.length() == 0L) {
            return@withContext Result(
                index,
                success = false,
                failureMessage = "File does not exist or is empty (size 0). It may not have been fully copied by file_picker.",
                errorType = CompressionErrorType.NOT_FOUND
            )
        }

        var fisRetriever: FileInputStream? = null
        try {
            fisRetriever = FileInputStream(file)
            mediaMetadataRetriever.setDataSource(fisRetriever.fd)
        } catch (exception: Exception) {
            printException(exception)
            // The fd-based source failed; drop it and fall back to a Uri source.
            try { fisRetriever?.close() } catch (ignored: Exception) {}
            fisRetriever = null
            try {
                mediaMetadataRetriever.setDataSource(context, srcUri)
            } catch (inner: Exception) {
                printException(inner)
                try { mediaMetadataRetriever.release() } catch (ignored: Exception) {}
                return@withContext Result(
                    index,
                    success = false,
                    failureMessage = "Retriever failed: ${inner.message}",
                    errorType = CompressionErrorType.UNSUPPORTED
                )
            }
        }
        // IMPORTANT: do NOT close fisRetriever here. MediaMetadataRetriever reads
        // the fd lazily during extractMetadata(); closing it now makes every
        // metadata lookup return null (observed on Qualcomm/MIUI devices), which
        // breaks duration/bitrate detection. It is closed in the finally below.

        var fisExtractor: FileInputStream? = null
        try {
            fisExtractor = FileInputStream(file)
            extractor.setDataSource(fisExtractor.fd)
        } catch (exception: Exception) {
            printException(exception)
            try { fisExtractor?.close() } catch (ignored: Exception) {}
            fisExtractor = null
            try {
                extractor.setDataSource(context, srcUri, null)
            } catch (inner: Exception) {
                printException(inner)
                try { mediaMetadataRetriever.release() } catch (ignored: Exception) {}
                try { fisRetriever?.close() } catch (ignored: Exception) {}
                return@withContext Result(
                    index,
                    success = false,
                    failureMessage = "Extractor failed: ${inner.message}",
                    errorType = CompressionErrorType.UNSUPPORTED
                )
            }
        }
        // IMPORTANT: keep fisExtractor open for the whole compression; the
        // extractor reads samples from this fd until start() releases it.

        try {

        val height: Double = prepareVideoHeight(mediaMetadataRetriever)

        val width: Double = prepareVideoWidth(mediaMetadataRetriever)

        val rotationData =
            mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: "0"

        val bitrateData =
            mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "0"

        val durationData =
            mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)


        val hasVideo = mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)

        // Duration from retriever is in milliseconds, convert to microseconds
        var duration = (durationData?.toLongOrNull() ?: 0L) * 1000L

        if (duration <= 0L) {
            // Try to extract duration from MediaExtractor if Retriever failed.
            val videoIndex = findTrack(extractor, true)
            if (videoIndex >= 0) {
                val format = extractor.getTrackFormat(videoIndex)
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    duration = format.getLong(MediaFormat.KEY_DURATION)
                }
            }
        }

        // Fallback: use MediaPlayer to get duration
        if (duration <= 0L) {
            try {
                val mp = android.media.MediaPlayer()
                try {
                    val fis = FileInputStream(file)
                    try {
                        mp.setDataSource(fis.fd)
                        mp.prepare()
                        val durationMs = mp.duration // in milliseconds
                        if (durationMs > 0) {
                            duration = durationMs.toLong() * 1000L // to microseconds
                        }
                    } finally {
                        try { fis.close() } catch (ignored: Exception) {}
                    }
                } finally {
                    mp.release()
                }
            } catch (e: Exception) {
                Log.w("Compressor", "MediaPlayer duration fallback failed: ${e.message}")
            }
        }

        var actualBitrate = bitrateData?.toDoubleOrNull()?.toInt() ?: 0

        // Fall back to the extractor's per-track bitrate when the retriever has none.
        if (actualBitrate <= 0) {
            val videoIndex = findTrack(extractor, true)
            if (videoIndex >= 0) {
                val format = extractor.getTrackFormat(videoIndex)
                if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                    actualBitrate = format.getInteger(MediaFormat.KEY_BIT_RATE)
                }
            }
        }

        // If bitrate is missing or unreliable, compute from file size and duration
        if (actualBitrate <= 0 && duration > 0L) {
            val durationSec = duration / 1000000.0
            if (durationSec > 0) {
                actualBitrate = ((file.length() * 8.0) / durationSec).toInt()
                Log.i("Compressor", "Computed bitrate from file size: $actualBitrate bps (file=${file.length()} bytes, duration=${durationSec}s)")
            }
        }
        if (actualBitrate <= 0) {
            // Neither the metadata nor a duration-based computation produced a
            // bitrate. Estimate from the source resolution instead of falling
            // back to MIN_BITRATE, which would crush HD video to a tiny output.
            actualBitrate = estimateBitrateFromResolution(width, height)
        }

        if (duration <= 0L) {
            // Last resort: estimate duration based on file size and actualBitrate.
            // Note: this is only used for the progress denominator; the value
            // reported back to Dart is replaced with the exact duration measured
            // during transcoding (see start()).
            val durationSeconds = file.length() / (actualBitrate / 8.0)
            duration = (durationSeconds * 1000000.0).toLong()
            if (duration <= 0L) duration = 1L
        }

        var rotation = rotationData?.toDoubleOrNull()?.toInt() ?: 0
        val bitrate = actualBitrate

        // Check for a min video bitrate before compression
        // Note: this is an experimental value
        if (configuration.isMinBitrateCheckEnabled && bitrate > 0 && bitrate <= MIN_BITRATE)
            return@withContext Result(index, success = false, failureMessage = INVALID_BITRATE)

        //Handle new width and height values. Computed before the bitrate so the
        //target-size solver can scale its floor to the OUTPUT resolution.
        val resizer = configuration.resizer
        val target = resizer?.resize(width, height) ?: Pair(width, height)
        var newWidth = roundDimension(target.first)
        var newHeight = roundDimension(target.second)

        // Handle new bitrate value. Precedence: an explicit videoBitrateInMbps
        // wins; else a requested target output size is solved for; else the
        // quality preset is used.
        var targetSizeMet = true
        val newBitrate: Int = when {
            configuration.videoBitrateInMbps != null ->
                configuration.videoBitrateInMbps!! * 1000000

            configuration.targetSizeBytes != null -> {
                val durationSec = duration / 1000000.0
                // Reserve bits for the (passed-through) audio track and ~3%
                // container overhead, then solve for the video bitrate.
                val audioBps =
                    if (configuration.disableAudio) 0 else findAudioBitrate(extractor)
                val totalBudgetBits = configuration.targetSizeBytes!! * 8.0
                val audioBits = audioBps.toDouble() * durationSec
                val videoBudgetBits = totalBudgetBits * 0.97 - audioBits
                val solvedBps =
                    if (durationSec > 0) videoBudgetBits / durationSec else 0.0
                // Quality floor: keep at least MIN_BITRATE but never exceed the
                // source (a sub-floor source can't be compressed further). A
                // target below this lands at the floor and reports
                // targetSizeMet = false.
                val floor = minOf(MIN_BITRATE, actualBitrate).toDouble()
                targetSizeMet = solvedBps >= floor
                solvedBps.coerceIn(floor, actualBitrate.toDouble()).toInt()
            }

            else -> getBitrate(actualBitrate, configuration.quality)
        }

        //Handle rotation values and swapping height and width if needed
        rotation = when (rotation) {
            90, 270 -> {
                val tempHeight = newHeight
                newHeight = newWidth
                newWidth = tempHeight
                0
            }

            180 -> 0
            else -> rotation
        }

        // Decide the output codec. H.265 is used only when the caller asked for
        // it AND the device exposes a hardware HEVC encoder; otherwise we fall
        // back to H.264 so compatibility is never silently broken.
        val outputMime =
            if (configuration.videoFormat == VideoFormat.H265 && isHevcHardwareEncoderAvailable())
                HEVC_MIME
            else
                MIME_TYPE

        return@withContext start(
            index,
            newWidth,
            newHeight,
            destination,
            newBitrate,
            configuration.disableAudio,
            extractor,
            listener,
            duration,
            rotation,
            outputMime,
            targetSizeMet,
        )

        } finally {
            // Release metadata resources and close the file descriptors that were
            // kept open for lazy reads during extraction/compression.
            try { mediaMetadataRetriever.release() } catch (ignored: Exception) {}
            try { fisRetriever?.close() } catch (ignored: Exception) {}
            try { fisExtractor?.close() } catch (ignored: Exception) {}
        }
    }

    @Suppress("DEPRECATION")
    private fun start(
        id: Int,
        newWidth: Int,
        newHeight: Int,
        destination: String,
        newBitrate: Int,
        disableAudio: Boolean,
        extractor: MediaExtractor,
        compressionProgressListener: CompressionProgressListener,
        duration: Long,
        rotation: Int,
        outputMime: String,
        targetSizeMet: Boolean,
    ): Result {

        if (newWidth != 0 && newHeight != 0) {

            val cacheFile = File(destination)

            // Tracks the largest frame presentation time seen while transcoding.
            // This is the ground-truth duration and is used in place of the
            // (possibly estimated) input duration when reporting back to Dart.
            var maxPresentationTimeUs = 0L

            // Held outside the try so the outer finally can always release the
            // native muxer, including on the early-return error paths below.
            var mediaMuxerRef: MediaMuxer? = null

            try {
                // MediaCodec accesses encoder and decoder components and processes the new video
                //input to generate a compressed/smaller size video
                val bufferInfo = MediaCodec.BufferInfo()

                // Platform MP4 muxer — natively handles AVC and HEVC, so no
                // codec-specific container code (or a third-party mp4 parser) is
                // needed. MediaMuxer requires every track to be added before
                // start(), so it is started lazily once the encoder publishes its
                // real output format (which carries the codec-specific data).
                val mediaMuxer = MediaMuxer(
                    cacheFile.absolutePath,
                    MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
                )
                mediaMuxerRef = mediaMuxer
                if (rotation != 0) mediaMuxer.setOrientationHint(rotation)
                var muxerStarted = false

                // Start with video track
                val videoIndex = findTrack(extractor, isVideo = true)
                if (videoIndex < 0) {
                    return Result(
                        id,
                        success = false,
                        failureMessage = "No video track found in the source file.",
                        errorType = CompressionErrorType.UNSUPPORTED,
                    )
                }

                extractor.selectTrack(videoIndex)
                extractor.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val inputFormat = extractor.getTrackFormat(videoIndex)

                // Audio is copied through untouched. Resolve it up front because
                // every track must be added to MediaMuxer before start().
                val audioExtractorIndex = findTrack(extractor, isVideo = false)
                val audioFormat: MediaFormat? =
                    if (!disableAudio && audioExtractorIndex >= 0)
                        extractor.getTrackFormat(audioExtractorIndex)
                    else null
                var audioMuxerTrackIndex = -1

                val outputFormat: MediaFormat =
                    MediaFormat.createVideoFormat(outputMime, newWidth, newHeight)
                //set output format
                setOutputFileParameters(
                    inputFormat,
                    outputFormat,
                    newBitrate,
                )

                var decoder: MediaCodec? = null
                var encoder: MediaCodec? = null
                var inputSurface: InputSurface? = null
                var outputSurface: OutputSurface? = null

                try {
                    encoder = prepareEncoder(outputFormat)

                    var inputDone = false
                    var outputDone = false

                    var videoTrackIndex = -5

                    inputSurface = InputSurface(encoder.createInputSurface())
                    inputSurface.makeCurrent()
                    //Move to executing state
                    encoder.start()

                    outputSurface = OutputSurface()

                    decoder = prepareDecoder(inputFormat, outputSurface)

                    //Move to executing state
                    decoder.start()

                    while (!outputDone) {
                        if (!inputDone) {

                            val index = extractor.sampleTrackIndex

                            if (index == videoIndex) {
                                val inputBufferIndex =
                                    decoder.dequeueInputBuffer(MEDIACODEC_TIMEOUT_DEFAULT)
                                if (inputBufferIndex >= 0) {
                                    val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                                    val chunkSize = extractor.readSampleData(inputBuffer!!, 0)
                                    when {
                                        chunkSize < 0 -> {

                                            decoder.queueInputBuffer(
                                                inputBufferIndex,
                                                0,
                                                0,
                                                0L,
                                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                            )
                                            inputDone = true
                                        }

                                        else -> {

                                            decoder.queueInputBuffer(
                                                inputBufferIndex,
                                                0,
                                                chunkSize,
                                                extractor.sampleTime,
                                                0
                                            )
                                            extractor.advance()

                                        }
                                    }
                                }

                            } else if (index == -1) { //end of file
                                val inputBufferIndex =
                                    decoder.dequeueInputBuffer(MEDIACODEC_TIMEOUT_DEFAULT)
                                if (inputBufferIndex >= 0) {
                                    decoder.queueInputBuffer(
                                        inputBufferIndex,
                                        0,
                                        0,
                                        0L,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    inputDone = true
                                }
                            }
                        }

                        var decoderOutputAvailable = true
                        var encoderOutputAvailable = true

                        loop@ while (decoderOutputAvailable || encoderOutputAvailable) {

                            if (!isRunning) {
                                // Signal cancellation through the result; the caller
                                // turns this into a single onCancelled callback. We must
                                // NOT also fire a terminal callback here, otherwise the
                                // video reports twice (onCancelled + onFailure).
                                return Result(
                                    id,
                                    success = false,
                                    failureMessage = "The compression has stopped!",
                                    cancelled = true
                                )
                            }

                            //Encoder
                            val encoderStatus =
                                encoder.dequeueOutputBuffer(bufferInfo, MEDIACODEC_TIMEOUT_DEFAULT)

                            when {
                                encoderStatus == MediaCodec.INFO_TRY_AGAIN_LATER -> encoderOutputAvailable =
                                    false

                                encoderStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                    // Add every track and start the muxer exactly
                                    // once, when the encoder publishes its real
                                    // output format (which carries the csd needed
                                    // to write a correct avcC/hvcC).
                                    if (!muxerStarted) {
                                        videoTrackIndex =
                                            mediaMuxer.addTrack(encoder.outputFormat)
                                        if (audioFormat != null) {
                                            audioMuxerTrackIndex =
                                                mediaMuxer.addTrack(audioFormat)
                                        }
                                        mediaMuxer.start()
                                        muxerStarted = true
                                    }
                                }

                                encoderStatus == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                                    // ignore this status
                                }

                                encoderStatus < 0 -> throw RuntimeException("unexpected result from encoder.dequeueOutputBuffer: $encoderStatus")
                                else -> {
                                    val encodedData = encoder.getOutputBuffer(encoderStatus)
                                        ?: throw RuntimeException("encoderOutputBuffer $encoderStatus was null")

                                    if (muxerStarted && bufferInfo.size > 0 &&
                                        (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                                    ) {
                                        encodedData.position(bufferInfo.offset)
                                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                                        mediaMuxer.writeSampleData(
                                            videoTrackIndex, encodedData, bufferInfo
                                        )
                                    }

                                    outputDone =
                                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                                    encoder.releaseOutputBuffer(encoderStatus, false)
                                }
                            }
                            if (encoderStatus != MediaCodec.INFO_TRY_AGAIN_LATER) continue@loop

                            //Decoder
                            val decoderStatus =
                                decoder.dequeueOutputBuffer(bufferInfo, MEDIACODEC_TIMEOUT_DEFAULT)
                            when {
                                decoderStatus == MediaCodec.INFO_TRY_AGAIN_LATER -> decoderOutputAvailable =
                                    false

                                decoderStatus == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                                    // ignore this status
                                }

                                decoderStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                    // ignore this status
                                }

                                decoderStatus < 0 -> throw RuntimeException("unexpected result from decoder.dequeueOutputBuffer: $decoderStatus")
                                else -> {
                                    val doRender = bufferInfo.size != 0

                                    decoder.releaseOutputBuffer(decoderStatus, doRender)
                                    if (doRender) {
                                        var errorWait = false
                                        try {
                                            outputSurface.awaitNewImage()
                                        } catch (e: Exception) {
                                            errorWait = true
                                            Log.e(
                                                "Compressor",
                                                e.message ?: "Compression failed at swapping buffer"
                                            )
                                        }

                                        if (!errorWait) {
                                            outputSurface.drawImage()

                                            inputSurface.setPresentationTime(bufferInfo.presentationTimeUs * 1000)

                                            if (bufferInfo.presentationTimeUs > maxPresentationTimeUs) {
                                                maxPresentationTimeUs = bufferInfo.presentationTimeUs
                                            }

                                            val progress = (bufferInfo.presentationTimeUs.toFloat() / duration.toFloat() * 100).coerceAtMost(99f)
                                            compressionProgressListener.onProgressChanged(
                                                id,
                                                progress
                                            )

                                            inputSurface.swapBuffers()
                                        }
                                    }
                                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                        decoderOutputAvailable = false
                                        encoder.signalEndOfInputStream()
                                    }
                                }
                            }
                        }
                    }

                } catch (exception: Exception) {
                    printException(exception)
                    return Result(id, success = false, failureMessage = exception.message)
                } finally {
                    extractor.unselectTrack(videoIndex)

                    try { decoder?.stop() } catch (ignored: Exception) {}
                    try { decoder?.release() } catch (ignored: Exception) {}

                    try { encoder?.stop() } catch (ignored: Exception) {}
                    try { encoder?.release() } catch (ignored: Exception) {}

                    try { inputSurface?.release() } catch (ignored: Exception) {}
                    try { outputSurface?.release() } catch (ignored: Exception) {}
                }

                if (muxerStarted && audioFormat != null && audioMuxerTrackIndex >= 0) {
                    copyAudioSamples(
                        mediaMuxer,
                        audioMuxerTrackIndex,
                        audioExtractorIndex,
                        extractor,
                        bufferInfo,
                    )
                }

                extractor.release()
                if (muxerStarted) {
                    try { mediaMuxer.stop() } catch (e: Exception) { printException(e) }
                } else {
                    // The encoder never published an output format, so no track
                    // was written — report failure instead of a 0-byte "success".
                    return Result(
                        id,
                        success = false,
                        failureMessage = "Compression produced no output (the source may be empty or unsupported).",
                        errorType = CompressionErrorType.UNSUPPORTED,
                    )
                }

            } catch (exception: Exception) {
                printException(exception)
                return Result(
                    id,
                    success = false,
                    failureMessage = exception.message ?: "An error occurred during video compression setup"
                )
            } finally {
                // Always release the native muxer — including the early-return
                // error paths above. release() is safe whether or not start()/
                // stop() ran.
                try { mediaMuxerRef?.release() } catch (ignored: Exception) {}
            }

            // Prefer the exact duration measured during transcoding; fall back to
            // the (possibly estimated) input duration only if no frames were timed.
            val reportedDurationUs =
                if (maxPresentationTimeUs > 0L) maxPresentationTimeUs else duration
            return Result(
                id,
                success = true,
                failureMessage = null,
                size = cacheFile.length(),
                path = cacheFile.path,
                duration = reportedDurationUs.toDouble() / 1000000.0,
                videoFormat = if (outputMime == HEVC_MIME) "h265" else "h264",
                targetSizeMet = targetSizeMet,
            )
        }

        return Result(
            id,
            success = false,
            failureMessage = "Something went wrong, please try again"
        )
    }

    /**
     * Copies the source audio track verbatim into [mediaMuxer]. The track is
     * already added (MediaMuxer requires that before start()); here we just pump
     * the encoded audio samples through, unchanged.
     */
    private fun copyAudioSamples(
        mediaMuxer: MediaMuxer,
        muxerTrackIndex: Int,
        audioExtractorIndex: Int,
        extractor: MediaExtractor,
        bufferInfo: MediaCodec.BufferInfo,
    ) {
        extractor.selectTrack(audioExtractorIndex)
        val audioFormat = extractor.getTrackFormat(audioExtractorIndex)
        var maxBufferSize =
            if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            else 0
        if (maxBufferSize <= 0) maxBufferSize = 64 * 1024

        var buffer: ByteBuffer = ByteBuffer.allocateDirect(maxBufferSize)
        if (Build.VERSION.SDK_INT >= 28) {
            val size = extractor.sampleSize
            if (size > maxBufferSize) {
                maxBufferSize = (size + 1024).toInt()
                buffer = ByteBuffer.allocateDirect(maxBufferSize)
            }
        }

        extractor.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        var inputDone = false
        while (!inputDone) {
            when (extractor.sampleTrackIndex) {
                audioExtractorIndex -> {
                    val chunkSize = extractor.readSampleData(buffer, 0)
                    if (chunkSize >= 0) {
                        bufferInfo.offset = 0
                        bufferInfo.size = chunkSize
                        bufferInfo.presentationTimeUs = extractor.sampleTime
                        bufferInfo.flags =
                            if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0)
                                MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                        buffer.position(0)
                        buffer.limit(chunkSize)
                        mediaMuxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
                        extractor.advance()
                    } else {
                        inputDone = true
                    }
                }
                -1 -> inputDone = true
                else -> extractor.advance()
            }
        }
        extractor.unselectTrack(audioExtractorIndex)
    }

    /**
     * Rough source-bitrate estimate (bps) based on the source resolution, used
     * only when neither the file metadata nor a duration-based computation could
     * provide a real bitrate. Picks a sane H.264 ballpark so that the
     * quality-based fraction in [CompressorUtils.getBitrate] yields a reasonable
     * output instead of the absurdly small result MIN_BITRATE would produce.
     */
    /**
     * Source audio-track bitrate (bps) for the target-size solver's audio
     * reserve, or a 128 kbps AAC fallback when the track does not report one.
     */
    private fun findAudioBitrate(extractor: MediaExtractor): Int {
        val audioIndex = findTrack(extractor, isVideo = false)
        if (audioIndex >= 0) {
            val format = extractor.getTrackFormat(audioIndex)
            if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                val br = format.getInteger(MediaFormat.KEY_BIT_RATE)
                if (br > 0) return br
            }
        }
        return 128_000
    }

    private fun estimateBitrateFromResolution(width: Double, height: Double): Int {
        val pixels = width * height
        return when {
            pixels >= 1920 * 1080 -> 12_000_000 // 1080p+
            pixels >= 1280 * 720 -> 6_000_000   // 720p
            pixels >= 854 * 480 -> 3_000_000    // 480p
            else -> MIN_BITRATE
        }
    }

    private fun prepareEncoder(outputFormat: MediaFormat): MediaCodec {
        var encoder: MediaCodec? = null
        var lastException: Exception? = null
        // The encoder must match the codec chosen for the output format (AVC/HEVC).
        val mime = outputFormat.getString(MediaFormat.KEY_MIME) ?: MIME_TYPE

        // Attempt 1: Default configuration (Hardware, Profile, CBR mode)
        try {
            encoder = MediaCodec.createEncoderByType(mime)
            encoder.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            return encoder
        } catch (e: Exception) {
            lastException = e
            Log.w("Compressor", "Failed to configure hardware encoder with default format: ${e.message}")
            try { encoder?.release() } catch (ignored: Exception) {}
        }

        // Attempt 2: Fallback to VBR (Variable Bitrate Mode) with profile
        val formatVBR = cloneFormat(outputFormat)
        formatVBR.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
        try {
            encoder = MediaCodec.createEncoderByType(mime)
            encoder.configure(formatVBR, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            return encoder
        } catch (e: Exception) {
            lastException = e
            Log.w("Compressor", "Failed to configure hardware encoder with VBR mode: ${e.message}")
            try { encoder?.release() } catch (ignored: Exception) {}
        }

        // Attempt 3: Remove profile level (Baseline/Default fallback, VBR mode)
        val formatNoProfile = cloneFormat(formatVBR, listOf(MediaFormat.KEY_PROFILE, MediaFormat.KEY_LEVEL))
        try {
            encoder = MediaCodec.createEncoderByType(mime)
            encoder.configure(formatNoProfile, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            return encoder
        } catch (e: Exception) {
            lastException = e
            Log.w("Compressor", "Failed to configure hardware encoder without profile: ${e.message}")
            try { encoder?.release() } catch (ignored: Exception) {}
        }

        // Attempt 4: Fallback to Software Encoders (codec-specific names).
        val softwareEncoderNames = if (mime == HEVC_MIME) {
            listOf("c2.android.hevc.encoder", "OMX.google.hevc.encoder")
        } else {
            listOf("c2.android.avc.encoder", "OMX.google.h264.encoder")
        }
        for (name in softwareEncoderNames) {
            try {
                encoder = MediaCodec.createByCodecName(name)
                encoder.configure(formatNoProfile, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                Log.i("Compressor", "Successfully configured software encoder fallback: $name")
                return encoder
            } catch (e: Exception) {
                lastException = e
                Log.w("Compressor", "Failed to configure software encoder $name: ${e.message}")
                try { encoder?.release() } catch (ignored: Exception) {}
            }
        }

        throw lastException ?: RuntimeException("Failed to prepare and configure encoder")
    }

    private fun cloneFormat(format: MediaFormat, excludeKeys: List<String> = emptyList()): MediaFormat {
        val width = format.getInteger(MediaFormat.KEY_WIDTH)
        val height = format.getInteger(MediaFormat.KEY_HEIGHT)
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val newFormat = MediaFormat.createVideoFormat(mime, width, height)

        val keys = listOf(
            MediaFormat.KEY_BIT_RATE,
            MediaFormat.KEY_FRAME_RATE,
            MediaFormat.KEY_I_FRAME_INTERVAL,
            MediaFormat.KEY_COLOR_FORMAT,
            MediaFormat.KEY_COLOR_STANDARD,
            MediaFormat.KEY_COLOR_TRANSFER,
            MediaFormat.KEY_COLOR_RANGE,
            MediaFormat.KEY_BITRATE_MODE,
            MediaFormat.KEY_PROFILE,
            MediaFormat.KEY_LEVEL
        )
        for (key in keys) {
            if (!excludeKeys.contains(key) && format.containsKey(key)) {
                try {
                    newFormat.setInteger(key, format.getInteger(key))
                } catch (ignored: Exception) {}
            }
        }
        return newFormat
    }

    private fun prepareDecoder(
        inputFormat: MediaFormat,
        outputSurface: OutputSurface,
    ): MediaCodec {
        // This seems to cause an issue with certain phones
        // val decoderName =
        //    MediaCodecList(REGULAR_CODECS).findDecoderForFormat(inputFormat)
        // val decoder = MediaCodec.createByCodecName(decoderName)
        // Log.i("decoderName", decoder.name)

        // val decoder = if (hasQTI) {
        // MediaCodec.createByCodecName("c2.android.avc.decoder")
        //} else {

        val decoder = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
        //}

        decoder.configure(inputFormat, outputSurface.getSurface(), null, 0)

        return decoder
    }
}
