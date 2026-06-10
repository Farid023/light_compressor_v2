import 'dart:math';

/// Converts a byte count into a human-readable string with the appropriate
/// unit suffix (e.g. `1.23 MB`).
///
/// [bytes] is the number of bytes to format.
/// [decimals] controls how many decimal places are shown in the result.
///
/// Returns `'0 B'` if [bytes] is zero or negative.
///
/// Example:
/// ```dart
/// formatBytes(1536, 2); // '1.50 KB'
/// formatBytes(0, 2);    // '0 B'
/// ```
String formatBytes(int bytes, int decimals) {
  if (bytes <= 0) return '0 B';

  const List<String> suffixes = [
    'B',
    'KB',
    'MB',
    'GB',
    'TB',
    'PB',
    'EB',
    'ZB',
    'YB',
  ];

  final int i = (log(bytes) / log(1000)).floor();
  final double value = bytes / pow(1000, i);

  return '${value.toStringAsFixed(decimals)} ${suffixes[i]}';
}

/// Formats a [Duration] as `m:ss` (or `h:mm:ss` when an hour or longer).
///
/// Example:
/// ```dart
/// formatDuration(const Duration(seconds: 66)); // '1:06'
/// ```
String formatDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final String mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}
