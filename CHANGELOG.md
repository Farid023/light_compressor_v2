# Changelog

# 1.2.0

### New

- **Batch compression** — `compressVideos({required List<String> paths, required List<String> videoNames, ...})` compresses multiple videos with a shared set of options and returns `Future<List<Result>>` in the same order as the inputs (each entry an `OnSuccess`, `OnFailure` or `OnCancelled`). A single video failing does not stop the rest.
- **`onBatchUpdate`** — a `Stream<BatchEvent>` that emits `BatchProgress` (per-video and overall percent) and `BatchItemCompleted` (a video's result) as the batch runs, for building per-item UIs.
- The single-video `compressVideo` and its `onProgressUpdated` stream are unchanged — batch uses a separate `compression/batch-stream` channel, so existing code is unaffected.

### Changed

- **`cancelCompression()` now returns `Future<void>`** instead of `Future<Map<String, dynamic>?>`. The old return type never carried a meaningful value; the cancellation outcome arrives as an `OnCancelled` result on the pending `compressVideo` / `compressVideos` call.

### Fixed

- **Cancelling a single compression crashed the app on Android.** Cancellation delivered two terminal callbacks for one video (`onCancelled` followed by `onFailure`) and replied twice on the same `MethodChannel.Result`, throwing `IllegalStateException: Reply already submitted`. Cancellation now yields exactly one `onCancelled`, and the single-video handler de-duplicates its reply like batch already did.
- **`cancelCompression()` never completed.** The Android, iOS and macOS handlers did not reply to the method call, so the returned `Future` hung forever. All three platforms now reply.
- **iOS / macOS:** the single-video handler funnels every terminal reply through one main-thread reply, so a cancel/finish race can no longer deliver two `FlutterResult`s or reply off the main thread.

# 1.1.0

### New

- **`getMediaInfo(path)`** — returns a structured `MediaInfo` (width, height, duration, file size, bitrate, rotation, frame rate, MIME type) with rotation-aware `displayWidth`/`displayHeight`. On Android, duration/bitrate fall back to the `MediaExtractor` track format when the metadata retriever does not expose them.
- **`getVideoThumbnail(path, {positionInMs, quality})`** — extracts a JPEG frame and returns its file path (Android `MediaMetadataRetriever`, iOS/macOS `AVAssetImageGenerator`).
- **`clearCache()`** — deletes temporary files generated during compression and thumbnail extraction (`.mp4` and `.jpg`).
- **Structured success result** — `OnSuccess` now carries `originalSize`, `compressedSize`, `duration` and `ratio` (percentage reduction).
- **Typed exceptions** — `PermissionDeniedException`, `UnsupportedVideoException`, `VideoNotFoundException`, `MediaInfoException`, `ThumbnailException`, all extending `LightCompressorException`. Native failures are surfaced via stable error codes instead of message text.
- Example app demonstrates metadata display, thumbnail preview, and a Clear Cache action.

### Fixed

- **Android H.264 encoder** — pair `KEY_PROFILE` with a supported `KEY_LEVEL`, so the hardware encoder no longer fails `configure()` with error `-38` and silently downgrades to Baseline.
- **Reported duration** — use the exact duration measured during transcoding instead of a file-size/bitrate estimate (previously could report wildly wrong values for files without duration metadata).
- **Over-compression** — when a source has no duration/bitrate metadata, estimate the bitrate from the resolution instead of collapsing to the minimum bitrate.
- **Resource handling (Android)** — keep `MediaMetadataRetriever`/`MediaExtractor` file descriptors open while reading and release the retriever (previously leaked).
- **macOS** — fixed a build failure caused by an out-of-sync `LightCompressor.swift`.

# 1.0.1

- Added Swift Package Manager (SPM) support for iOS.
- Fully migrated the Android native layer to Kotlin, including core compression algorithms, MP4 builder, and video/texture renderers.
- Integrated the native compression library sources directly into the plugin codebase.
- Upgraded the Android build system and configurations (converted build scripts to Kotlin DSL `.gradle.kts`).
- Added comprehensive production-ready documentation (`README.md`).
- Updated example project and video player.
- Optimized codebase and improved performance.
- Fixed minor issues.

# 1.0.0 (Fork)

- Forked from the original `light_compressor` package.
- Updated `kotlin-gradle-plugin` to version 1.8.21.
- Upgraded the `LightCompressor` dependency to version 1.3.2.
- Increased `compileSdkVersion` to 33.
- Fixed various bugs and improved performance.

