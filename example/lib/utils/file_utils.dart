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
    'B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB',
  ];

  final int i = (log(bytes) / log(1024)).floor();
  final double value = bytes / pow(1024, i);

  return '${value.toStringAsFixed(decimals)} ${suffixes[i]}';
}