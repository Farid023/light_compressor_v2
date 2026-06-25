package com.gurfdev.light_compressor_v2.lightcompressorlibrary

import androidx.annotation.MainThread
import androidx.annotation.WorkerThread

/**
 * Classifies a compression failure so callers can react programmatically
 * instead of matching error message text.
 */
enum class CompressionErrorType {
    /** Missing read/write permission. */
    PERMISSION,
    /** Unsupported format/codec or a missing video track. */
    UNSUPPORTED,
    /** The source video could not be found. */
    NOT_FOUND,
    /** Any other, unclassified failure. */
    UNKNOWN;

    /** Lower-camel name forwarded to Dart (matches the Dart `failureType` values). */
    fun toWireValue(): String = when (this) {
        PERMISSION -> "permission"
        UNSUPPORTED -> "unsupported"
        NOT_FOUND -> "notFound"
        UNKNOWN -> "unknown"
    }
}

interface CompressionListener {
    @MainThread
    fun onStart(index: Int)

    @MainThread
    fun onSuccess(index: Int, size: Long, path: String?, duration: Double, videoFormat: String, targetSizeMet: Boolean = true)

    @MainThread
    fun onFailure(index: Int, failureMessage: String, errorType: CompressionErrorType = CompressionErrorType.UNKNOWN)

    @WorkerThread
    fun onProgress(index: Int, percent: Float)

    @WorkerThread
    fun onCancelled(index: Int)
}

interface CompressionProgressListener {
    fun onProgressChanged(index: Int, percent: Float)
}
