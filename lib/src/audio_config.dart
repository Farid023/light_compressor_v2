/// Audio re-encoding options for the output video.
///
/// Pass an [AudioConfig] as `audio:` to `compressVideo` / `compressVideos` to
/// re-encode the audio track as AAC with a custom [bitrate] and/or
/// [sampleRate]. When omitted (the default), the source audio is copied through
/// untouched. Ignored entirely when `disableAudio` is `true`.
class AudioConfig {
  /// Creates an [AudioConfig].
  ///
  /// Both fields are optional; a `null` field leaves that aspect of the audio
  /// unchanged (the source value is used). Provided values must be greater
  /// than 0.
  const AudioConfig({this.bitrate, this.sampleRate})
      : assert(
            bitrate == null || bitrate > 0, 'bitrate must be greater than 0'),
        assert(
          sampleRate == null || sampleRate > 0,
          'sampleRate must be greater than 0',
        );

  /// Target AAC bitrate in bits per second (e.g. `128000`).
  final int? bitrate;

  /// Target audio sample rate in hertz (e.g. `44100`).
  final int? sampleRate;
}
