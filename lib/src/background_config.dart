import 'package:light_compressor_v2/light_compressor_v2.dart';

/// Keeps a compression running while the app is backgrounded or the screen is
/// off.
///
/// Pass an instance to [LightCompressor.compressVideo] or
/// [LightCompressor.compressVideos] through their `background` parameter to opt
/// in. Leaving it `null` (the default) preserves the previous behaviour, where
/// the OS may pause or terminate a long-running compression once the app
/// leaves the foreground.
///
/// ## Platform behaviour
///
/// Background execution is constrained by each operating system, so the
/// guarantees differ substantially:
///
/// * **Android** — the compression runs under a *foreground service*, surfaced
///   to the user as an ongoing notification that shows live progress (bar +
///   percentage), an elapsed-time timer, the current file or batch progress
///   and a Cancel action. [notificationTitle] sets its
///   title. This keeps the process at
///   foreground priority, so compression continues uninterrupted when the app
///   is backgrounded or the screen turns off.
///   On Android 13+ the system notification requires the `POST_NOTIFICATIONS`
///   permission; the plugin requests it automatically. If the user denies it,
///   compression still runs — only the notification is hidden.
///
/// * **macOS** — App Nap is suppressed for the duration of the compression
///   (via `NSProcessInfo.beginActivity`), so the process keeps full CPU while
///   in the background. The notification fields are ignored.
///
/// * **iOS** — **not supported.** iOS suspends backgrounded apps within
///   seconds, which freezes an in-process compression until the app returns to
///   the foreground; there is no sanctioned way to keep video transcoding
///   running in the background. Passing a [BackgroundConfig] on iOS therefore
///   has no effect — the compression behaves exactly as it would without it.
class BackgroundConfig {
  /// Creates a configuration that enables background execution.
  ///
  /// The notification fields are used on Android only; other platforms ignore
  /// them. Sensible English defaults are provided so the simplest opt-in is
  /// `const BackgroundConfig()`.
  const BackgroundConfig({this.notificationTitle = 'Compressing video'});

  /// Android only — the title shown on the foreground-service notification.
  final String notificationTitle;

  /// Serialises this configuration into the map sent across the method channel.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'notificationTitle': notificationTitle,
      };
}
