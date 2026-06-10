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
