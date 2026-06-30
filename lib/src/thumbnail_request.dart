import 'package:flutter/foundation.dart';

/// A single frame request for `LightCompressor.getVideoThumbnails`.
@immutable
class ThumbnailRequest {
  /// Creates a request for the frame at [positionInMs] with the given [quality].
  const ThumbnailRequest({required this.positionInMs, this.quality = 50});

  /// Timecode of the frame to grab, in milliseconds. Negative values are
  /// floored to `0`; the native side also clamps to the video duration.
  final int positionInMs;

  /// JPEG quality from `0` (smallest) to `100` (best). Defaults to `50`.
  final int quality;

  /// The map form sent over the platform channel, with values clamped to their
  /// valid ranges so the natives receive sane input.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'positionInMs': positionInMs < 0 ? 0 : positionInMs,
    'quality': quality.clamp(0, 100),
  };
}
