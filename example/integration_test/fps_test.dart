// End-to-end test for the Phase 8b frame-rate downsampling on the REAL native
// pipeline (the package unit tests only cover the mocked MethodChannel).
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — this test SKIPS until it is replaced).
//
//   cd example && flutter test integration_test/fps_test.dart -d <deviceId>

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

  group('frame-rate downsampling (real device)', () {
    testWidgets('a lower videoFps yields a valid, not-faster video', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      final double? sourceFps =
          (await compressor.getMediaInfo(source!)).frameRate;

      // A rate clearly below any common source frame rate.
      const int targetFps = 15;

      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_fps', videoFps: targetFps),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );

      expect(result, isA<OnSuccess>());
      final OnSuccess ok = result as OnSuccess;
      await expectReadableVideo(compressor, ok.destinationPath);

      // When the platform reports the output frame rate, downsampling must never
      // raise it above the source, and — when the source clearly exceeds the
      // target — it should land near the requested rate.
      final double? outFps =
          (await compressor.getMediaInfo(ok.destinationPath)).frameRate;
      if (outFps != null && outFps > 0) {
        if (sourceFps != null && sourceFps > 0) {
          expect(outFps, lessThanOrEqualTo(sourceFps + 1.0));
        }
        if (sourceFps != null && sourceFps > targetFps * 1.2) {
          expect(
            outFps,
            lessThan(sourceFps),
            reason: 'output fps should be reduced below the source',
          );
        }
      }
    });
  });
}
