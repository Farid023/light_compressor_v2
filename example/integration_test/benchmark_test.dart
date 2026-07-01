// Benchmark harness (NOT a correctness test): runs the REAL native pipeline over
// a matrix of quality presets and codecs, then prints a Markdown table of size
// reduction and wall-clock time you can paste into the README. Runs on a device:
//
//   cd example && flutter test integration_test/benchmark_test.dart -d <deviceId>
//
// SKIPS cleanly until a real clip replaces the tiny placeholder at
// integration_test/assets/sample.mp4. The numbers are device- and clip-specific
// — never hand-write them into the README; capture them here on the target
// device and paste the printed table.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'support.dart';

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

/// Compresses [source] once with [quality] + [format], timing the whole call.
/// Returns null (rather than throwing) on any failure so one bad run never
/// aborts the whole table.
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
      return null;
    }
    final OnSuccess ok = result;
    final MediaInfo info = await compressor.getMediaInfo(ok.destinationPath);
    return _Row(
      label: label,
      originalBytes: ok.originalSize,
      compressedBytes: ok.compressedSize,
      ratioPercent: ok.ratio,
      elapsedMs: sw.elapsedMilliseconds,
      dimensions: '${info.displayWidth ?? '?'}x${info.displayHeight ?? '?'}',
      usedFormat: ok.usedFormat.name,
    );
  } catch (_) {
    return null;
  }
}

/// Renders the collected rows as a copy-pasteable Markdown block.
void _printTable(MediaInfo src, List<_Row> rows) {
  String mb(int bytes) => (bytes / (1000 * 1000)).toStringAsFixed(2);

  final double srcSeconds = (src.duration?.inMilliseconds ?? 0) / 1000;
  final List<String> out = <String>[
    '',
    '### light_compressor_v2 benchmark',
    '',
    '- Device: <fill in model> (${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion})',
    '- Source: ${src.displayWidth ?? '?'}x${src.displayHeight ?? '?'}, '
        '${srcSeconds.toStringAsFixed(1)}s, ${mb(src.fileSize ?? 0)} MB',
    '',
    '| Preset | Output | Size | Reduced | Time | Codec |',
    '|--------|-------:|-----:|--------:|-----:|-------|',
  ];
  for (final _Row r in rows) {
    out.add('| ${r.label} | ${r.dimensions} | ${mb(r.compressedBytes)} MB '
        '| ${r.ratioPercent.toStringAsFixed(1)}% '
        '| ${(r.elapsedMs / 1000).toStringAsFixed(1)}s | ${r.usedFormat} |');
  }
  out.add('');

  for (final String line in out) {
    debugPrint(line);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final LightCompressor compressor = LightCompressor();
  String? source;

  setUpAll(() async {
    source = await prepareSampleSource();
  });

  testWidgets(
    'benchmark: quality presets and H.264 vs H.265',
    (WidgetTester tester) async {
      if (source == null) {
        return markTestSkipped(kNoClipSkipReason);
      }

      final MediaInfo src = await compressor.getMediaInfo(source!);
      final List<_Row> rows = <_Row>[];

      // Every quality preset on the default H.264 codec.
      const List<VideoQuality> presets = <VideoQuality>[
        VideoQuality.very_low,
        VideoQuality.low,
        VideoQuality.medium,
        VideoQuality.high,
        VideoQuality.very_high,
      ];
      for (final VideoQuality q in presets) {
        final _Row? row = await _run(compressor, source!, q, VideoFormat.h264);
        if (row != null) {
          rows.add(row);
        }
      }

      // HEVC at medium to show the extra saving. Falls back to H.264 when the
      // device has no hardware HEVC encoder — the Codec column reveals which.
      final _Row? hevc = await _run(
          compressor, source!, VideoQuality.medium, VideoFormat.h265);
      if (hevc != null) {
        rows.add(hevc);
      }

      _printTable(src, rows);

      // Sanity only (the table is the point): at least one preset shrank it.
      expect(rows, isNotEmpty);
      expect(
        rows.any((_Row r) => r.compressedBytes < r.originalBytes),
        isTrue,
      );

      await compressor.clearCache();
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
