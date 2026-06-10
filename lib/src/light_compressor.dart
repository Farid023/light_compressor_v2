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

  Stream<double>? _onProgressUpdated;

  /// A broadcast stream that emits the current compression progress.
  ///
  /// The emitted values range from `0.0` to `100.0`.
  Stream<double> get onProgressUpdated {
    _onProgressUpdated ??= _progressStream.receiveBroadcastStream().map<double>(
      (dynamic result) => result != null ? result : 0,
    );
    return _onProgressUpdated!;
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

  /// Call this function to cancel video compression process.
  Future<Map<String, dynamic>?> cancelCompression() async =>
      jsonDecode(await _channel.invokeMethod<dynamic>('cancelCompression'));
}
