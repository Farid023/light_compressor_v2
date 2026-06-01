/// iOS and macOS specific configurations for saving the compressed video.
class IOSConfig {
  /// Creates a new [IOSConfig] instance.
  ///
  /// By default, [saveInGallery] is `true`.
  IOSConfig({this.saveInGallery = true});

  /// Whether to save the compressed video directly to the device's photo library (Gallery).
  ///
  /// If `true`, you must add `NSPhotoLibraryUsageDescription` to your `Info.plist`.
  /// Defaults to `true`.
  final bool saveInGallery;
}
