// End-to-end tests for the rest of the plugin's public surface on the REAL
// native pipeline: metadata, thumbnails, compression options, progress streams,
// cache and cancellation. (Codec selection has its own hevc_compression_test.)
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/plugin_integration_test.dart -d <deviceId>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final LightCompressor compressor = LightCompressor();
  String? source;

  setUpAll(() async {
    source = await prepareSampleSource();
  });

  // Compresses the sample to app-specific storage (no runtime permission) with
  // the given tweaks, asserting success.
  Future<OnSuccess> compressSample({
    VideoQuality quality = VideoQuality.medium,
    int? width,
    int? height,
    bool disableAudio = false,
    String name = 'lc_it_out',
  }) async {
    final Result r = await compressor.compressVideo(
      path: source!,
      videoQuality: quality,
      isMinBitrateCheckEnabled: false,
      disableAudio: disableAudio,
      video: Video(videoName: name, videoWidth: width, videoHeight: height),
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
    );
    expect(r, isA<OnSuccess>(), reason: 'compression should succeed');
    return r as OnSuccess;
  }

  group('getMediaInfo', () {
    testWidgets('reads sane metadata from a real clip', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final MediaInfo info = await compressor.getMediaInfo(source!);
      expect((info.width ?? 0) > 0, isTrue);
      expect((info.height ?? 0) > 0, isTrue);
      expect(info.duration, isNotNull);
      expect(info.duration! > Duration.zero, isTrue);
    });

    testWidgets('throws VideoNotFoundException for a missing file', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      await expectLater(
        compressor.getMediaInfo('/does/not/exist_lc_it.mp4'),
        throwsA(isA<VideoNotFoundException>()),
      );
    });
  });

  group('getVideoThumbnail', () {
    testWidgets('writes a JPEG frame', (WidgetTester tester) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final String path = await compressor.getVideoThumbnail(
        source!,
        positionInMs: 0,
        quality: 70,
      );
      expect(path, isNotEmpty);
      final File f = File(path);
      expect(f.existsSync(), isTrue);
      final List<int> bytes = await f.readAsBytes();
      expect(bytes.length, greaterThan(0));
      // JPEG SOI marker (0xFFD8).
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
    });

    testWidgets('throws for a missing file', (WidgetTester tester) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      await expectLater(
        compressor.getVideoThumbnail('/does/not/exist_lc_it.mp4'),
        throwsA(isA<LightCompressorException>()),
      );
    });
  });

  group('compressVideo options', () {
    testWidgets('reports sane size statistics', (WidgetTester tester) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final OnSuccess ok = await compressSample(name: 'lc_it_stats');
      expect(ok.originalSize, greaterThan(0));
      expect(ok.compressedSize, greaterThan(0));
      expect(ok.ratio, inInclusiveRange(0.0, 100.0));
      await expectReadableVideo(compressor, ok.destinationPath);
    });

    testWidgets('honours a custom output resolution', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final OnSuccess ok =
          await compressSample(width: 640, height: 360, name: 'lc_it_res');
      final MediaInfo info = await compressor.getMediaInfo(ok.destinationPath);
      // Orientation-agnostic: compare the sorted dimensions within a tolerance
      // (the encoder rounds to macroblock-friendly sizes).
      final List<int> dims = <int>[
        info.displayWidth ?? 0,
        info.displayHeight ?? 0,
      ]..sort();
      expect(dims[0], closeTo(360, 48));
      expect(dims[1], closeTo(640, 48));
    });

    testWidgets('disableAudio still produces a valid video', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final OnSuccess ok =
          await compressSample(disableAudio: true, name: 'lc_it_noaudio');
      await expectReadableVideo(compressor, ok.destinationPath);
    });
  });

  group('progress streams', () {
    testWidgets('onProgressUpdated emits during a compression', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final List<double> values = <double>[];
      final sub = compressor.onProgressUpdated.listen(values.add);
      await compressSample(name: 'lc_it_progress');
      await sub.cancel();
      expect(values, isNotEmpty);
      expect(values.every((double v) => v >= 0 && v <= 100), isTrue);
    });

    testWidgets('onBatchUpdate emits progress and completion events', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final List<BatchEvent> events = <BatchEvent>[];
      final sub = compressor.onBatchUpdate.listen(events.add);
      final List<Result> results = await compressor.compressVideos(
        paths: <String>[source!, source!],
        videoNames: <String>['lc_it_be0', 'lc_it_be1'],
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );
      await sub.cancel();
      expect(results, hasLength(2));
      expect(events.whereType<BatchProgress>(), isNotEmpty);
      expect(events.whereType<BatchItemCompleted>().length, 2);
    });
  });

  group('lifecycle', () {
    testWidgets('clearCache completes without error', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      await compressor.clearCache(); // smoke: must not throw or hang
    });

    testWidgets('cancelCompression resolves the pending call (no hang)', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      // Tolerant by design: on a short clip the compression may finish before
      // the cancel lands. The contract under test is that cancelCompression()
      // returns and the pending compressVideo Future resolves to a terminal
      // result — guarding the 1.2.0 "cancel never completed" hang regression.
      final Future<Result> pending = compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_cancel'),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await compressor.cancelCompression();
      final Result result = await pending;
      expect(
        result is OnCancelled || result is OnSuccess || result is OnFailure,
        isTrue,
      );
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
