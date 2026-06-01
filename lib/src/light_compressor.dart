import 'dart:async';
import 'dart:convert';

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
  /// * [OnSuccess] containing the output destination file path.
  /// * [OnFailure] containing an error message.
  /// * [OnCancelled] indicating that the compression was manually cancelled.
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
      return OnSuccess(response['onSuccess']);
    } else if (response['onFailure'] != null) {
      return OnFailure(response['onFailure']);
    } else if (response['onCancelled'] != null) {
      return OnCancelled(isCancelled: response['onCancelled']);
    } else {
      return const OnFailure('Something went wrong');
    }
  }

  /// Call this function to cancel video compression process.
  Future<Map<String, dynamic>?> cancelCompression() async =>
      jsonDecode(await _channel.invokeMethod<dynamic>('cancelCompression'));
}
