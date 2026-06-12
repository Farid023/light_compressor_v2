import 'compression_result.dart';

/// An update emitted while a batch of videos is being compressed.
///
/// Subscribe via `LightCompressor.onBatchUpdate` to react as the batch makes
/// progress. Each event carries the [index] of the video within the `paths`
/// list passed to `compressVideos`.
sealed class BatchEvent {
  /// Creates a [BatchEvent] for the video at [index].
  const BatchEvent(this.index);

  /// The position of the video within the original `paths` list.
  final int index;
}

/// Progress update for a single video in the batch.
class BatchProgress extends BatchEvent {
  /// Creates a [BatchProgress] event.
  const BatchProgress({
    required int index,
    required this.percent,
    required this.overallPercent,
  }) : super(index);

  /// Compression progress of this video, from `0.0` to `100.0`.
  final double percent;

  /// Average progress across every video in the batch, from `0.0` to `100.0`.
  final double overallPercent;

  @override
  String toString() =>
      'BatchProgress(index: $index, percent: $percent, overallPercent: $overallPercent)';
}

/// Emitted once the video at [index] has finished (successfully, with a
/// failure, or cancelled). The same [result] also appears, in order, in the
/// list returned by `compressVideos`.
class BatchItemCompleted extends BatchEvent {
  /// Creates a [BatchItemCompleted] event.
  const BatchItemCompleted({required int index, required this.result})
    : super(index);

  /// The outcome for this video: [OnSuccess], [OnFailure] or [OnCancelled].
  final Result result;

  @override
  String toString() => 'BatchItemCompleted(index: $index, result: $result)';
}
