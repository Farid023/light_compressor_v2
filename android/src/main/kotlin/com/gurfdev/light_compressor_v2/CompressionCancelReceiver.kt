package com.gurfdev.light_compressor_v2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.VideoCompressor

/**
 * Receives the "Cancel" action from the foreground-service notification and
 * cancels the active compression. The library then delivers `onCancelled` to
 * the running listener, which resolves the pending call and stops the service
 * through the normal terminal path.
 */
class CompressionCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        VideoCompressor.cancel()
    }
}
