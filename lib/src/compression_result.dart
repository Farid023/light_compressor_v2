import 'package:light_compressor_v2/light_compressor_v2.dart';

/// Base class for video compression results.
abstract class Result {}

/// Represents a successful video compression.
class OnSuccess implements Result {
  /// Creates an [OnSuccess] result.
  const OnSuccess({
    required this.destinationPath,
    required this.originalSize,
    required this.compressedSize,
    required this.duration,
    required this.ratio,
    this.usedFormat = VideoFormat.h264,
  });

  /// The absolute path to the successfully compressed video file.
  final String destinationPath;

  /// The original size of the video in bytes.
  final int originalSize;

  /// The size of the compressed video in bytes.
  final int compressedSize;

  /// The duration of the video in seconds.
  final double duration;

  /// The percentage of size reduction.
  final double ratio;

  /// The codec actually used to encode the output.
  ///
  /// Normally matches the requested `videoFormat`. When [VideoFormat.h265] was
  /// requested but the device has no HEVC encoding support, the compressor
  /// falls back to [VideoFormat.h264] and this field reflects that real
  /// outcome. Defaults to [VideoFormat.h264].
  final VideoFormat usedFormat;
}

/// Represents a failed video compression attempt.
class OnFailure implements Result {
  /// Creates an [OnFailure] result with a description of the error.
  const OnFailure(this.message);

  /// Description of the error that caused the compression to fail.
  final String message;
}

/// Represents a cancelled video compression operation.
class OnCancelled implements Result {
  /// Creates an [OnCancelled] result.
  const OnCancelled({required this.isCancelled});

  /// Indicates if the compression operation was successfully cancelled.
  final bool isCancelled;
}
