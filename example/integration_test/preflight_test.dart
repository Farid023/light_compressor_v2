// End-to-end tests for the Phase 7 pre-flight & introspection APIs on the REAL
// native pipeline: getCompressionEstimate, getVideoThumbnails, isCompressing.
// (The package unit tests only cover the mocked MethodChannel.)
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/preflight_test.dart -d <deviceId>

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

  group('getCompressionEstimate (real device)', () {
    testWidgets('returns sane figures that track the real output', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      const VideoQuality quality = VideoQuality.medium;
      final CompressionEstimate estimate = await compressor
          .getCompressionEstimate(source!, videoQuality: quality);

      // Structural sanity.
      expect(estimate.originalSizeBytes, greaterThan(0));
      expect(estimate.estimatedSizeBytes, greaterThan(0));
      expect(estimate.targetBitrate, greaterThan(0));
      expect(estimate.outputWidth, greaterThan(0));
      expect(estimate.outputHeight, greaterThan(0));
      expect(estimate.estimatedRatio, inInclusiveRange(0.0, 100.0));

      // Compress for real with the same options and compare the ballpark. The
      // estimate is single-pass and approximate, so assert it lands within a
      // generous band of the real output rather than an exact match.
      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: quality,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_estimate'),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );
      expect(result, isA<OnSuccess>());
      final int real = (result as OnSuccess).compressedSize;
      expect(real, greaterThan(estimate.estimatedSizeBytes ~/ 4));
      expect(real, lessThan(estimate.estimatedSizeBytes * 4));
    });
  });

  group('getVideoThumbnails (real device)', () {
    testWidgets('returns one readable JPEG per request, in order', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      final List<String> paths = await compressor.getVideoThumbnails(
        source!,
        const <ThumbnailRequest>[
          ThumbnailRequest(positionInMs: 0, quality: 70),
          ThumbnailRequest(positionInMs: 250, quality: 70),
          ThumbnailRequest(positionInMs: 500, quality: 70),
        ],
      );

      expect(paths, hasLength(3));
      for (final String path in paths) {
        final File file = File(path);
        expect(file.existsSync(), isTrue,
            reason: 'thumbnail should exist: $path');
        expect(file.lengthSync(), greaterThan(0));
      }
    });
  });

  group('isCompressing (real device)', () {
    testWidgets('is false when idle, true during a batch, false after', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      expect(
        await compressor.isCompressing(),
        isFalse,
        reason: 'should be idle before starting',
      );

      // A 4-item batch runs long enough to observe the running state (Android
      // caps concurrency at 2, so four clips do not all finish instantly).
      final Future<List<Result>> batch = compressor.compressVideos(
        paths: <String>[source!, source!, source!, source!],
        videoNames: <String>[
          'lc_it_run0',
          'lc_it_run1',
          'lc_it_run2',
          'lc_it_run3',
        ],
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );

      bool sawRunning = false;
      for (int i = 0; i < 30 && !sawRunning; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (await compressor.isCompressing()) {
          sawRunning = true;
        }
      }

      await batch;

      expect(
        sawRunning,
        isTrue,
        reason: 'isCompressing should be true while a batch runs',
      );
      expect(
        await compressor.isCompressing(),
        isFalse,
        reason: 'should be idle after completion',
      );
    });
  });
}
