import 'package:flutter/foundation.dart';

/// A pre-flight prediction of a compression's output, returned by
/// `LightCompressor.getCompressionEstimate`.
///
/// Computed natively from the source metadata using the same bitrate and
/// resize math the compressor itself uses — no transcode is run, so the figures
/// are approximate (typically within ~30% of the real output for single-pass).
@immutable
class CompressionEstimate {
  /// Creates a [CompressionEstimate].
  const CompressionEstimate({
    required this.originalSizeBytes,
    required this.estimatedSizeBytes,
    required this.targetBitrate,
    required this.outputWidth,
    required this.outputHeight,
    required this.estimatedRatio,
  });

  /// Builds a [CompressionEstimate] from the raw platform-channel map.
  ///
  /// Missing fields default to `0`; numbers are coerced because the channel may
  /// deliver them as `int` or `double`.
  factory CompressionEstimate.fromMap(Map<String, dynamic> map) =>
      CompressionEstimate(
        originalSizeBytes: (map['originalSizeBytes'] as num?)?.toInt() ?? 0,
        estimatedSizeBytes: (map['estimatedSizeBytes'] as num?)?.toInt() ?? 0,
        targetBitrate: (map['targetBitrate'] as num?)?.toInt() ?? 0,
        outputWidth: (map['outputWidth'] as num?)?.toInt() ?? 0,
        outputHeight: (map['outputHeight'] as num?)?.toInt() ?? 0,
        estimatedRatio: (map['estimatedRatio'] as num?)?.toDouble() ?? 0.0,
      );

  /// Size of the source file in bytes.
  final int originalSizeBytes;

  /// Predicted size of the compressed output in bytes.
  final int estimatedSizeBytes;

  /// Target video bitrate, in bits per second, used for the estimate.
  final int targetBitrate;

  /// Predicted output width in pixels.
  final int outputWidth;

  /// Predicted output height in pixels.
  final int outputHeight;

  /// Predicted size reduction as a percentage (`0`–`100`).
  final double estimatedRatio;

  @override
  String toString() =>
      'CompressionEstimate(originalSizeBytes: $originalSizeBytes, '
      'estimatedSizeBytes: $estimatedSizeBytes, targetBitrate: $targetBitrate, '
      'outputWidth: $outputWidth, outputHeight: $outputHeight, '
      'estimatedRatio: $estimatedRatio)';
}
