import 'package:light_compressor_v2/light_compressor_v2.dart';

/// The output video codec used for compression.
///
/// Pass to [LightCompressor.compressVideo] / [LightCompressor.compressVideos]
/// through their `videoFormat` parameter. Defaults to [VideoFormat.h264], which
/// preserves the previous behaviour and is the safest, most compatible choice.
///
/// Both formats are written into an MP4/QuickTime container; only the video
/// codec changes.
enum VideoFormat {
  /// H.264 / AVC — the widely compatible default, encodable and playable on
  /// virtually every device.
  h264,

  /// H.265 / HEVC — roughly the same visual quality at a smaller file size, but
  /// it requires a hardware HEVC encoder on the device.
  ///
  /// When [h265] is requested on a device (or platform) without HEVC encoding
  /// support, the compressor automatically falls back to [h264]; the format
  /// that was actually used is reported by [OnSuccess.usedFormat].
  ///
  /// Background by platform:
  /// * **Android** — used only when a hardware HEVC encoder is present;
  ///   software-only HEVC is treated as unsupported and falls back to H.264.
  /// * **iOS / macOS** — used when the device advertises HEVC encoding support.
  h265,
}
