/// Configurations for the output video.
class Video {
  /// Creates a new [Video] configuration instance.
  ///
  /// The [videoName] is required.
  Video({
    required this.videoName,
    this.keepOriginalResolution = false,
    this.videoBitrateInMbps,
    this.videoHeight,
    this.videoWidth,
  });

  /// The name of the output video file (e.g., `compressed_video.mp4`).
  ///
  /// This value is required. If the `.mp4` extension is omitted, it will
  /// be appended automatically by the plugin.
  final String videoName;

  /// Whether to preserve the original video resolution (width and height) during compression.
  ///
  /// Defaults to `false`.
  final bool? keepOriginalResolution;

  /// A custom target bitrate for the output video in Mbps (Megabits per second).
  ///
  /// If provided, this overrides the default bitrate calculated by the selected VideoQuality.
  final int? videoBitrateInMbps;

  /// A custom height for the output video in pixels.
  ///
  /// If specified, you must also provide [videoWidth].
  final int? videoHeight;

  /// A custom width for the output video in pixels.
  ///
  /// If specified, you must also provide [videoHeight].
  final int? videoWidth;
}
