import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

/// Video quality presets to determine the target bitrate for compression.
enum VideoQuality {
  /// Very low quality. Results in the smallest file size but lowest detail.
  very_low,

  /// Low quality. Good for high compression with moderate detail loss.
  low,

  /// Medium quality. Balanced setting for size reduction and good video quality.
  medium,

  /// High quality. Retains high levels of detail with moderate file size reduction.
  high,

  /// Very high quality. Focuses on maximum quality preservation with minor file size reduction.
  very_high,
}

/// A lightweight, easy-to-use video compressor for Flutter.
///
/// This class provides methods to compress videos and track their progress.
class LightCompressor {
  /// Returns the singleton instance of [LightCompressor].
  factory LightCompressor() => _instance;

  LightCompressor._internal();

  static final LightCompressor _instance = LightCompressor._internal();

  static const MethodChannel _channel = MethodChannel('light_compressor');

  /// A stream to listen to video compression progress
  static const EventChannel _progressStream = EventChannel(
    'compression/stream',
  );

  /// A stream that carries per-video updates while a batch is compressing.
  static const EventChannel _batchStream = EventChannel(
    'compression/batch-stream',
  );

  Stream<double>? _onProgressUpdated;
  Stream<BatchEvent>? _onBatchUpdate;

  /// A broadcast stream that emits the current compression progress.
  ///
  /// The emitted values range from `0.0` to `100.0`.
  Stream<double> get onProgressUpdated {
    _onProgressUpdated ??= _progressStream.receiveBroadcastStream().map<double>(
      (dynamic result) => result != null ? result : 0,
    );
    return _onProgressUpdated!;
  }

  /// A broadcast stream of [BatchEvent]s emitted during [compressVideos].
  ///
  /// Emits [BatchProgress] as each video advances and [BatchItemCompleted] the
  /// moment a video finishes (success, failure or cancellation). Subscribe to
  /// this to drive a per-item UI; the final ordered results are also returned
  /// by [compressVideos].
  Stream<BatchEvent> get onBatchUpdate {
    _onBatchUpdate ??= _batchStream.receiveBroadcastStream().map<BatchEvent>((
      dynamic event,
    ) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(
        event as Map<dynamic, dynamic>,
      );
      final int index = (map['index'] as num?)?.toInt() ?? 0;
      if (map['type'] == 'progress') {
        return BatchProgress(
          index: index,
          percent: (map['percent'] as num?)?.toDouble() ?? 0.0,
          overallPercent: (map['overallPercent'] as num?)?.toDouble() ?? 0.0,
        );
      }
      return BatchItemCompleted(index: index, result: _resultFromMap(map));
    });
    return _onBatchUpdate!;
  }

  /// Compresses a video file at the given [path] using the specified options.
  ///
  /// The video is saved into either app-specific or shared storage depending on
  /// the configurations provided in [android] and [ios].
  ///
  /// Required Parameters:
  /// * [path] — The absolute file path of the source video to be compressed.
  /// * [videoQuality] — The target quality preset.
  /// * [android] — Android-specific configuration (e.g., storage type).
  /// * [ios] — iOS/macOS-specific configuration (e.g., gallery saving).
  /// * [video] — Specifications for the output video (e.g., name, resolution).
  ///
  /// Optional Parameters:
  /// * [disableAudio] — If set to `true`, the audio track will be stripped, producing a silent video. Defaults to `false`.
  /// * [isMinBitrateCheckEnabled] — If `true`, the compressor checks if the source video's bitrate is above a minimum threshold (2 Mbps) before starting. If it's below the threshold, compression is skipped to prevent quality degradation. Defaults to `true`.
  /// * [background] — When provided, keeps the compression running while the
  ///   app is backgrounded or the screen is off. Behaviour and guarantees vary
  ///   per platform; see [BackgroundConfig]. Defaults to `null` (the OS may
  ///   pause/terminate the compression once the app leaves the foreground).
  ///
  /// Returns a [Result] which can be:
  /// * [OnSuccess] containing the output destination file path and statistics.
  /// * [OnFailure] containing an error message.
  /// * [OnCancelled] indicating that the compression was manually cancelled.
  ///
  /// Throws a [LightCompressorException] when the native side reports a
  /// recognizable error:
  /// * [PermissionDeniedException] — missing read/write permission.
  /// * [UnsupportedVideoException] — unsupported format/codec or missing track.
  /// * [VideoNotFoundException] — the source video could not be found.
  Future<Result> compressVideo({
    required String path,
    required VideoQuality videoQuality,
    required AndroidConfig android,
    required IOSConfig ios,
    required Video video,
    bool? disableAudio = false,
    bool isMinBitrateCheckEnabled = true,
    BackgroundConfig? background,
  }) async {
    final Map<String, dynamic> response = jsonDecode(
      await _channel
          .invokeMethod<dynamic>('startCompression', <String, dynamic>{
            'path': path,
            'videoQuality': videoQuality.toString().split('.').last,
            'isSharedStorage': android.isSharedStorage,
            'saveAt': android.saveAt.name,
            'disableAudio': disableAudio,
            'keepOriginalResolution': video.keepOriginalResolution,
            'isMinBitrateCheckEnabled': isMinBitrateCheckEnabled,
            'videoBitrateInMbps': video.videoBitrateInMbps,
            'videoHeight': video.videoHeight,
            'videoWidth': video.videoWidth,
            'videoName': video.videoName,
            'saveInGallery': ios.saveInGallery,
            'background': background?.toMap(),
          }),
    );

    if (response['onSuccess'] != null) {
      final String destinationPath = response['onSuccess'] as String;
      if (destinationPath.isEmpty) {
        return const OnFailure(
          'Compression reported success but returned no output path.',
        );
      }

      final double duration = (response['duration'] as num?)?.toDouble() ?? 0.0;

      // Prefer the sizes reported by the native side. The output file may live
      // in scoped/shared storage (e.g. MediaStore on Android) whose path is not
      // directly readable via `File`, so re-reading it in Dart is unreliable.
      int originalSize = (response['originalSize'] as num?)?.toInt() ?? 0;
      int compressedSize = (response['compressedSize'] as num?)?.toInt() ?? 0;

      // Fallback to reading from disk when the native side did not report sizes.
      if (originalSize <= 0) {
        originalSize = _fileSizeOrZero(path);
      }
      if (compressedSize <= 0) {
        compressedSize = _fileSizeOrZero(destinationPath);
      }

      final double ratio = originalSize > 0
          ? ((1 - compressedSize / originalSize) * 100).clamp(0.0, 100.0)
          : 0.0;

      return OnSuccess(
        destinationPath: destinationPath,
        originalSize: originalSize,
        compressedSize: compressedSize,
        duration: duration,
        ratio: ratio,
      );
    } else if (response['onFailure'] != null) {
      final String failureMessage = response['onFailure'] as String;
      final String? failureType = response['failureType'] as String?;
      final LightCompressorException? exception = _exceptionFor(
        failureType,
        failureMessage,
      );
      if (exception != null) {
        throw exception;
      }
      return OnFailure(failureMessage);
    } else if (response['onCancelled'] != null) {
      return OnCancelled(isCancelled: response['onCancelled']);
    } else {
      return const OnFailure('Something went wrong');
    }
  }

  /// Compresses multiple videos with a single shared set of options.
  ///
  /// [paths] are the source video paths and [videoNames] the matching output
  /// file names; the two lists must have the same length. Every video shares
  /// the same [videoQuality], resolution and bitrate settings.
  ///
  /// Returns the results in the same order as [paths]; each entry is an
  /// [OnSuccess], [OnFailure] or [OnCancelled]. Every video is attempted: a
  /// single video failing does not throw and does not stop the others — its
  /// slot in the returned list becomes an [OnFailure].
  ///
  /// Subscribe to [onBatchUpdate] for per-video progress and completion events
  /// as the batch runs.
  ///
  /// When [background] is provided the whole batch keeps running while the app
  /// is backgrounded or the screen is off; see [BackgroundConfig] for the
  /// per-platform behaviour and caveats.
  Future<List<Result>> compressVideos({
    required List<String> paths,
    required List<String> videoNames,
    required VideoQuality videoQuality,
    required AndroidConfig android,
    required IOSConfig ios,
    bool keepOriginalResolution = false,
    int? videoWidth,
    int? videoHeight,
    int? videoBitrateInMbps,
    bool disableAudio = false,
    bool isMinBitrateCheckEnabled = true,
    BackgroundConfig? background,
  }) async {
    assert(
      paths.length == videoNames.length,
      'paths and videoNames must have the same length',
    );
    if (paths.isEmpty) {
      return <Result>[];
    }

    final List<dynamic>? response = await _channel
        .invokeListMethod<dynamic>('startBatchCompression', <String, dynamic>{
          'paths': paths,
          'videoNames': videoNames,
          'videoQuality': videoQuality.toString().split('.').last,
          'isSharedStorage': android.isSharedStorage,
          'saveAt': android.saveAt.name,
          'saveInGallery': ios.saveInGallery,
          'keepOriginalResolution': keepOriginalResolution,
          'videoWidth': videoWidth,
          'videoHeight': videoHeight,
          'videoBitrateInMbps': videoBitrateInMbps,
          'disableAudio': disableAudio,
          'isMinBitrateCheckEnabled': isMinBitrateCheckEnabled,
          'background': background?.toMap(),
        });

    if (response == null) {
      return <Result>[];
    }
    return response
        .map(
          (dynamic e) => _resultFromMap(
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
          ),
        )
        .toList();
  }

  /// Builds a [Result] from a native result map. Shared by the [compressVideos]
  /// return value and the [BatchItemCompleted] events on [onBatchUpdate].
  Result _resultFromMap(Map<String, dynamic> map) {
    if (map['onSuccess'] != null) {
      final String destinationPath = map['onSuccess'] as String;
      final double duration = (map['duration'] as num?)?.toDouble() ?? 0.0;
      final int originalSize = (map['originalSize'] as num?)?.toInt() ?? 0;
      final int compressedSize = (map['compressedSize'] as num?)?.toInt() ?? 0;
      final double ratio = originalSize > 0
          ? ((1 - compressedSize / originalSize) * 100).clamp(0.0, 100.0)
          : 0.0;
      return OnSuccess(
        destinationPath: destinationPath,
        originalSize: originalSize,
        compressedSize: compressedSize,
        duration: duration,
        ratio: ratio,
      );
    } else if (map['onFailure'] != null) {
      return OnFailure(map['onFailure'] as String);
    } else if (map['onCancelled'] != null) {
      return OnCancelled(isCancelled: map['onCancelled'] == true);
    }
    return const OnFailure('Something went wrong');
  }

  /// Maps a native failure to a typed exception.
  ///
  /// Prefers the structured [failureType] code reported by the native side.
  /// Falls back to message heuristics for untyped OS-level errors (whose text
  /// the package does not control). Returns `null` when the failure cannot be
  /// classified, in which case an [OnFailure] is returned instead of throwing.
  LightCompressorException? _exceptionFor(String? failureType, String message) {
    switch (failureType) {
      case 'permission':
        return PermissionDeniedException(message);
      case 'unsupported':
        return UnsupportedVideoException(message);
      case 'notFound':
        return VideoNotFoundException(message);
    }

    final String lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return PermissionDeniedException(message);
    }
    if (lower.contains('unsupported') ||
        lower.contains('codec') ||
        lower.contains('format') ||
        lower.contains('track')) {
      return UnsupportedVideoException(message);
    }
    if (lower.contains('not found') ||
        lower.contains('no such file') ||
        lower.contains('does not exist')) {
      return VideoNotFoundException(message);
    }
    return null;
  }

  /// Returns the size of the file at [filePath] in bytes, or `0` if it cannot
  /// be read (e.g. the path points to scoped storage or does not exist).
  int _fileSizeOrZero(String filePath) {
    try {
      final File file = File(filePath);
      return file.existsSync() ? file.lengthSync() : 0;
    } on Exception catch (_) {
      return 0;
    }
  }

  /// Reads metadata (dimensions, duration, bitrate, rotation, etc.) from the
  /// video located at [path].
  ///
  /// Throws a [VideoNotFoundException] if the file does not exist,
  /// a [PermissionDeniedException] if it cannot be accessed, or a
  /// [MediaInfoException] if the metadata could not be read.
  Future<MediaInfo> getMediaInfo(String path) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMapMethod<dynamic, dynamic>('getMediaInfo', <String, dynamic>{
            'path': path,
          });
      if (result == null) {
        throw const MediaInfoException();
      }
      return MediaInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw _mapPlatformException(
        e,
        MediaInfoException(e.message ?? _defaultMediaInfoMessage),
      );
    }
  }

  /// Generates a JPEG thumbnail from the video at [path] and returns the
  /// absolute path of the generated image file.
  ///
  /// * [positionInMs] — the timecode (in milliseconds) of the frame to grab.
  ///   Clamped to the video duration by the native side. Defaults to `0`.
  /// * [quality] — JPEG quality from `0` (smallest) to `100` (best).
  ///   Defaults to `50`.
  ///
  /// The image is written to a temporary directory; use [clearCache] to remove
  /// generated files when they are no longer needed.
  ///
  /// Throws a [VideoNotFoundException] if the file does not exist,
  /// a [PermissionDeniedException] if it cannot be accessed, or a
  /// [ThumbnailException] if the frame could not be extracted.
  Future<String> getVideoThumbnail(
    String path, {
    int positionInMs = 0,
    int quality = 50,
  }) async {
    try {
      final String? thumbnailPath = await _channel
          .invokeMethod<String>('getVideoThumbnail', <String, dynamic>{
            'path': path,
            'positionInMs': positionInMs < 0 ? 0 : positionInMs,
            'quality': quality.clamp(0, 100),
          });
      if (thumbnailPath == null || thumbnailPath.isEmpty) {
        throw const ThumbnailException();
      }
      return thumbnailPath;
    } on PlatformException catch (e) {
      throw _mapPlatformException(
        e,
        ThumbnailException(e.message ?? _defaultThumbnailMessage),
      );
    }
  }

  /// Maps a native [PlatformException] code onto a typed exception, falling
  /// back to [fallback] for codes that are not specifically recognized.
  LightCompressorException _mapPlatformException(
    PlatformException e,
    LightCompressorException fallback,
  ) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return PermissionDeniedException(
          e.message ?? _defaultPermissionMessage,
        );
      case 'VIDEO_NOT_FOUND':
        return VideoNotFoundException(e.message ?? _defaultNotFoundMessage);
      case 'UNSUPPORTED_VIDEO':
        return UnsupportedVideoException(
          e.message ?? _defaultUnsupportedMessage,
        );
      default:
        return fallback;
    }
  }

  static const String _defaultMediaInfoMessage =
      'Failed to read media information from the video.';
  static const String _defaultThumbnailMessage =
      'Failed to generate a thumbnail from the video.';
  static const String _defaultPermissionMessage =
      'Permission denied to access the video file or storage.';
  static const String _defaultNotFoundMessage =
      'The video file was not found at the specified path.';
  static const String _defaultUnsupportedMessage =
      'The provided video format or codec is unsupported.';

  /// Clears temporary `.mp4` files created during compression.
  ///
  /// Platform behavior differs:
  /// * **Android** — deletes `.mp4` files from the app cache directory
  ///   (temporary source copies). Compressed outputs saved to shared storage or
  ///   app-specific storage are **not** affected.
  /// * **iOS / macOS** — deletes all `.mp4` files in the temporary directory.
  ///   Compressed videos are written there, so any output that has not been
  ///   moved or saved elsewhere (e.g. via `saveInGallery`) will be removed.
  ///   Call this only after you have copied/consumed the compressed file.
  Future<void> clearCache() async {
    await _channel.invokeMethod<void>('clearCache');
  }

  /// Requests cancellation of the active video compression.
  ///
  /// The cancellation is reported as an [OnCancelled] result from the pending
  /// [compressVideo] / [compressVideos] call; this method only forwards the
  /// request to the platform and completes once it has been delivered.
  Future<void> cancelCompression() =>
      _channel.invokeMethod<void>('cancelCompression');
}
