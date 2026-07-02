// Benchmark harness (NOT a correctness test): runs the REAL native pipeline over
// a matrix of quality presets and codecs, then prints a Markdown table of size
// reduction and wall-clock time per source. Runs on a device:
//
//   cd example && flutter test integration_test/benchmark_test.dart -d <deviceId>
//
// Sources:
//   * the bundled short clip (integration_test/assets/sample.mp4) — a baseline;
//     SKIPS while it is still the tiny placeholder.
//   * any large local clips listed in [_deviceSources]. These are NOT bundled as
//     assets (too big — it would bloat the app and blow up memory on load).
//     Push them to the app's own external dir first, e.g.:
//       adb push clip.mp4 \
//         /sdcard/Android/data/com.example.light_compressor_v2_example/files/bench/
//     A source that can't be read (not pushed, or a different platform) SKIPS.
//
// Rows print incrementally (a "[bench] …" line each), so a timeout on a huge
// clip still leaves the completed rows in the log. Numbers are device- and
// clip-specific — never hand-write them; capture them here and paste the table.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'support.dart';

/// Where [_deviceSources] are read from on the device (the example app's own
/// external files dir — readable by raw path, no runtime permission needed).
const String _deviceBenchDir =
    '/sdcard/Android/data/com.example.light_compressor_v2_example/files/bench';

/// Large local clips to benchmark by direct path (file names under
/// [_deviceBenchDir]). Push them with `adb push` first.
const List<String> _deviceSources = <String>['sample2.mp4', 'sample1.mp4'];

/// Presets, most useful first — so a timeout on a huge clip still leaves the
/// headline (`medium`) and the spread captured.
const List<VideoQuality> _presets = <VideoQuality>[
  VideoQuality.medium,
  VideoQuality.low,
  VideoQuality.high,
  VideoQuality.very_low,
  VideoQuality.very_high,
];

String _mb(int bytes) => (bytes / (1000 * 1000)).toStringAsFixed(2);

/// One measured compression run.
class _Row {
  _Row({
    required this.label,
    required this.originalBytes,
    required this.compressedBytes,
    required this.ratioPercent,
    required this.elapsedMs,
    required this.dimensions,
    required this.usedFormat,
  });

  final String label;
  final int originalBytes;
  final int compressedBytes;
  final double ratioPercent;
  final int elapsedMs;
  final String dimensions;
  final String usedFormat;
}

/// Compresses [source] once with [quality] + [format], timing the whole call,
/// and prints a one-line result immediately. Returns null (rather than throwing)
/// on any failure so one bad run never aborts the whole table.
Future<_Row?> _run(
  LightCompressor compressor,
  String source,
  VideoQuality quality,
  VideoFormat format,
) async {
  final String label = '${format.name}/${quality.name}';
  final String name = 'lc_bench_${format.name}_${quality.name}';
  final Stopwatch sw = Stopwatch()..start();
  try {
    final Result result = await compressor.compressVideo(
      path: source,
      videoQuality: quality,
      isMinBitrateCheckEnabled: false,
      videoFormat: format,
      video: Video(videoName: name),
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
    );
    sw.stop();
    if (result is! OnSuccess) {
      debugPrint('[bench] $label -> ${result.runtimeType}');
      return null;
    }
    final OnSuccess ok = result;
    final MediaInfo info = await compressor.getMediaInfo(ok.destinationPath);
    final _Row row = _Row(
      label: label,
      originalBytes: ok.originalSize,
      compressedBytes: ok.compressedSize,
      ratioPercent: ok.ratio,
      elapsedMs: sw.elapsedMilliseconds,
      dimensions: '${info.displayWidth ?? '?'}x${info.displayHeight ?? '?'}',
      usedFormat: ok.usedFormat.name,
    );
    debugPrint('[bench] $label -> ${_mb(row.compressedBytes)} MB, '
        '${row.ratioPercent.toStringAsFixed(1)}% smaller, '
        '${(row.elapsedMs / 1000).toStringAsFixed(1)}s, ${row.usedFormat}');
    return row;
  } catch (e) {
    sw.stop();
    debugPrint('[bench] $label -> FAILED: $e');
    return null;
  }
}

/// Renders one source's rows as a copy-pasteable Markdown block.
void _printTable(String title, MediaInfo src, List<_Row> rows) {
  final double seconds = (src.duration?.inMilliseconds ?? 0) / 1000;
  final List<String> out = <String>[
    '',
    '### $title',
    '',
    '- Device: <fill in model> (${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion})',
    '- Source: ${src.displayWidth ?? '?'}x${src.displayHeight ?? '?'}, '
        '${seconds.toStringAsFixed(1)}s, ${_mb(src.fileSize ?? 0)} MB',
    '',
    '| Preset | Output | Size | Reduced | Time | Codec |',
    '|--------|-------:|-----:|--------:|-----:|-------|',
  ];
  for (final _Row r in rows) {
    out.add('| ${r.label} | ${r.dimensions} | ${_mb(r.compressedBytes)} MB '
        '| ${r.ratioPercent.toStringAsFixed(1)}% '
        '| ${(r.elapsedMs / 1000).toStringAsFixed(1)}s | ${r.usedFormat} |');
  }
  out.add('');
  for (final String line in out) {
    debugPrint(line);
  }
}

/// Runs the full matrix (every preset on H.264, plus HEVC at medium) against a
/// single readable [path] and prints its table.
Future<void> _benchmarkSource(
  LightCompressor compressor,
  String title,
  String path,
) async {
  final MediaInfo src = await compressor.getMediaInfo(path);
  final List<_Row> rows = <_Row>[];
  for (final VideoQuality q in _presets) {
    final _Row? row = await _run(compressor, path, q, VideoFormat.h264);
    if (row != null) {
      rows.add(row);
    }
  }
  // HEVC at medium: the Codec column shows whether the device honoured H.265 or
  // fell back to H.264.
  final _Row? hevc =
      await _run(compressor, path, VideoQuality.medium, VideoFormat.h265);
  if (hevc != null) {
    rows.add(hevc);
  }

  _printTable(title, src, rows);

  expect(rows, isNotEmpty);
  expect(rows.any((_Row r) => r.compressedBytes < r.originalBytes), isTrue);
  await compressor.clearCache();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final LightCompressor compressor = LightCompressor();
  String? bundled;

  setUpAll(() async {
    bundled = await prepareSampleSource();
  });

  testWidgets(
    'benchmark: bundled sample.mp4',
    (WidgetTester tester) async {
      if (bundled == null) {
        return markTestSkipped(kNoClipSkipReason);
      }
      await _benchmarkSource(compressor, 'sample.mp4 (bundled)', bundled!);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  for (final String fileName in _deviceSources) {
    final String path = '$_deviceBenchDir/$fileName';
    testWidgets(
      'benchmark: $fileName',
      (WidgetTester tester) async {
        try {
          await compressor.getMediaInfo(path);
        } catch (_) {
          return markTestSkipped('not readable (adb push it first): $path');
        }
        await _benchmarkSource(compressor, fileName, path);
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }
}
