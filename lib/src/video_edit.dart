import 'package:flutter/foundation.dart';

/// Lightweight, native edits applied while compressing: trimming the clip to a
/// time range and/or rotating it by a quarter-turn.
///
/// Passed as the `edit:` argument to `LightCompressor.compressVideo` /
/// `compressVideos`. Every field is optional and defaults to "no change", so an
/// empty [VideoEdit] (or `null`) leaves the video untouched.
@immutable
class VideoEdit {
  /// Creates a [VideoEdit].
  ///
  /// [trimStartMs] must be `>= 0`. [trimEndMs] must be greater than
  /// [trimStartMs] (or greater than `0` when no start is given).
  /// [rotationDegrees] must be one of `0`, `90`, `180`, `270`. The color knobs
  /// ([brightness] / [contrast] / [saturation]) are clamped to their valid
  /// ranges by [toMap].
  const VideoEdit({
    this.trimStartMs,
    this.trimEndMs,
    this.rotationDegrees,
    this.brightness,
    this.contrast,
    this.saturation,
  }) : assert(
        trimStartMs == null || trimStartMs >= 0,
        'trimStartMs must be greater than or equal to 0',
      ),
      assert(
        trimEndMs == null || trimEndMs > (trimStartMs ?? 0),
        'trimEndMs must be greater than trimStartMs (or 0 when no start)',
      ),
      assert(
        rotationDegrees == null ||
            rotationDegrees == 0 ||
            rotationDegrees == 90 ||
            rotationDegrees == 180 ||
            rotationDegrees == 270,
        'rotationDegrees must be one of 0, 90, 180, 270',
      );

  /// Start of the kept range, in milliseconds from the beginning of the source.
  ///
  /// Frames before this point are dropped and the output timeline is rebased to
  /// `0`. Must be `>= 0`. Defaults to the start of the video.
  final int? trimStartMs;

  /// End of the kept range, in milliseconds from the beginning of the source.
  ///
  /// Frames at or after this point are dropped. Must be greater than
  /// [trimStartMs] (or greater than `0` when no start is given). Defaults to the
  /// end of the video.
  final int? trimEndMs;

  /// Clockwise rotation to apply **on top of** the source orientation, in
  /// degrees. Must be one of `0`, `90`, `180`, `270`.
  ///
  /// This is a cheap container-metadata rotation (no extra pixel pass) — it sets
  /// the rotation flag in the output, which virtually all players honour.
  /// Defaults to no rotation.
  final int? rotationDegrees;

  /// Brightness adjustment in `-1.0..1.0` (`0` = no change), applied additively.
  /// Out-of-range values are clamped by [toMap]; `null` leaves brightness alone.
  final double? brightness;

  /// Contrast multiplier in `0.0..2.0` (`1` = no change). Out-of-range values
  /// are clamped by [toMap]; `null` leaves contrast alone.
  final double? contrast;

  /// Saturation multiplier in `0.0..2.0` (`1` = no change, `0` = grayscale).
  /// Out-of-range values are clamped by [toMap]; `null` leaves saturation alone.
  final double? saturation;

  /// The map form sent over the platform channel. Unset fields are sent as
  /// `null` so the native side can treat them as "not set"; the color knobs are
  /// clamped to their valid ranges.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'rotationDegrees': rotationDegrees,
    'brightness': brightness?.clamp(-1.0, 1.0),
    'contrast': contrast?.clamp(0.0, 2.0),
    'saturation': saturation?.clamp(0.0, 2.0),
  };
}
