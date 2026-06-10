/// Base exception for LightCompressor errors.
abstract class LightCompressorException implements Exception {
  /// Creates a [LightCompressorException] with the given [message].
  const LightCompressorException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the application lacks the necessary permissions to read or write the video.
class PermissionDeniedException extends LightCompressorException {
  /// Creates a [PermissionDeniedException] with an optional custom message.
  const PermissionDeniedException([
    super.message = 'Permission denied to access the video file or storage.',
  ]);
}

/// Thrown when the provided video format or codec is not supported for compression.
class UnsupportedVideoException extends LightCompressorException {
  /// Creates an [UnsupportedVideoException] with an optional custom message.
  const UnsupportedVideoException([
    super.message = 'The provided video format or codec is unsupported.',
  ]);
}

/// Thrown when the video cannot be found at the given path.
class VideoNotFoundException extends LightCompressorException {
  /// Creates a [VideoNotFoundException] with an optional custom message.
  const VideoNotFoundException([
    super.message = 'The video file was not found at the specified path.',
  ]);
}

/// Thrown when the media metadata could not be read from the video.
class MediaInfoException extends LightCompressorException {
  /// Creates a [MediaInfoException] with an optional custom message.
  const MediaInfoException([
    super.message = 'Failed to read media information from the video.',
  ]);
}

/// Thrown when a thumbnail frame could not be generated from the video.
class ThumbnailException extends LightCompressorException {
  /// Creates a [ThumbnailException] with an optional custom message.
  const ThumbnailException([
    super.message = 'Failed to generate a thumbnail from the video.',
  ]);
}
