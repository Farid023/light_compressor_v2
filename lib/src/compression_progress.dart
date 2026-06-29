import 'package:flutter/foundation.dart';

/// A rich progress sample emitted while a single video is compressing.
///
/// Subscribe via `LightCompressor.onProgressDetail`. For just the percentage,
/// `LightCompressor.onProgressUpdated` (`Stream<double>`) is unchanged and
/// remains the simplest option.
@immutable
class CompressionProgress {
  /// Creates a [CompressionProgress].
  const CompressionProgress({
    required this.percent,
    this.bytesProcessed,
    this.etaMs,
    this.elapsedMs,
  });

  /// Builds a [CompressionProgress] from a raw `compression/stream` event.
  ///
  /// Accepts either the current map payload
  /// (`{percent, bytesProcessed, etaMs, elapsedMs}`) or a bare numeric percent
  /// (the pre-1.8.0 wire), so a Dart upgrade never breaks against an older
  /// native side. A negative `etaMs` (the "not yet estimable" sentinel the
  /// natives send while progress is near zero) becomes `null`.
  factory CompressionProgress.fromEvent(dynamic event) {
    if (event is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(event);
      final int? eta = (map['etaMs'] as num?)?.toInt();
      return CompressionProgress(
        percent: ((map['percent'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 100.0)
            .toDouble(),
        bytesProcessed: (map['bytesProcessed'] as num?)?.toInt(),
        etaMs: (eta == null || eta < 0) ? null : eta,
        elapsedMs: (map['elapsedMs'] as num?)?.toInt(),
      );
    }
    // Back-compat: a bare numeric percent (the pre-1.8.0 wire).
    return CompressionProgress(
      percent: ((event as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, 100.0)
          .toDouble(),
    );
  }

  /// Compression progress, from `0.0` to `100.0`.
  final double percent;

  /// Encoded output bytes written so far, or `null` when the platform did not
  /// report it. Grows toward the final `OnSuccess.compressedSize`.
  final int? bytesProcessed;

  /// Estimated milliseconds remaining, or `null` while it is not yet estimable
  /// (e.g. progress is still near zero). A rough projection from elapsed time
  /// and progress — treat it as an indicator, not a guarantee.
  final int? etaMs;

  /// Milliseconds elapsed since this video's encode started, or `null` when the
  /// platform did not report it.
  final int? elapsedMs;

  @override
  String toString() =>
      'CompressionProgress(percent: $percent, bytesProcessed: $bytesProcessed, '
      'etaMs: $etaMs, elapsedMs: $elapsedMs)';
}
