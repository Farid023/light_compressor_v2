/// Base class for video compression results.
abstract class Result {}

/// Represents a successful video compression.
class OnSuccess implements Result {
  /// Creates an [OnSuccess] result.
  const OnSuccess(this.destinationPath);

  /// The absolute path to the successfully compressed video file.
  final String destinationPath;
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
