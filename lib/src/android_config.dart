/// Android specific configurations for saving the compressed video.
class AndroidConfig {
  /// Creates a new [AndroidConfig] instance.
  ///
  /// By default, [isSharedStorage] is `true` and the video is saved under
  /// [SaveAt.Movies].
  AndroidConfig({this.isSharedStorage = true, this.saveAt = SaveAt.Movies});

  /// Whether to save the output video in shared (MediaStore) or app-specific storage.
  ///
  /// For more details on Android storage options, see:
  /// https://developer.android.com/training/data-storage
  final bool isSharedStorage;

  /// The location where the video should be saved externally in shared storage.
  ///
  /// This value is ignored if [isSharedStorage] is `false`.
  final SaveAt saveAt;
}

/// Directory locations for saving videos in Android's shared storage.
enum SaveAt {
  /// The standard directory for pictures (e.g., `/sdcard/Pictures`).
  Pictures,

  /// The standard directory for movies (e.g., `/sdcard/Movies`).
  Movies,

  /// The standard directory for downloaded files (e.g., `/sdcard/Download`).
  Downloads,
}
