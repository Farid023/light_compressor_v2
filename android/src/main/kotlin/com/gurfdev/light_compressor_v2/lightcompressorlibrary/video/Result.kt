package com.gurfdev.light_compressor_v2.lightcompressorlibrary.video

import com.gurfdev.light_compressor_v2.lightcompressorlibrary.CompressionErrorType

data class Result(
    val index: Int,
    val success: Boolean,
    val failureMessage: String?,
    val size: Long = 0,
    val path: String? = null,
    val duration: Double = 0.0,
    val errorType: CompressionErrorType = CompressionErrorType.UNKNOWN,
    /** True when the run was stopped by [VideoCompressor.cancel], so the caller
     *  can deliver onCancelled instead of treating it as a failure. */
    val cancelled: Boolean = false,
    /** Codec actually used for the output: "h264" or "h265". H.265 falls back to
     *  H.264 when the device has no hardware HEVC encoder. */
    val videoFormat: String = "h264",
)
