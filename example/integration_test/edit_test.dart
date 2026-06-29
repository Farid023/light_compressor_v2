// End-to-end tests for the Phase 9a/9b native editing (trim + rotate) on the
// REAL native pipeline (the package unit tests only cover the mocked channel).
//
// Trim (9a) keeps a time range and rebases the output timeline to 0; rotate (9b)
// adds a quarter-turn as container-metadata rotation (so the displayed
// dimensions swap on a 90° turn).
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/edit_test.dart -d <deviceId>

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

  group('native editing (real device)', () {
    testWidgets('trim produces an output of about the requested length', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      final Duration? srcDuration =
          (await compressor.getMediaInfo(source!)).duration;
      expect(srcDuration, isNotNull);
      final int srcMs = srcDuration!.inMilliseconds;
      if (srcMs < 1000) {
        return markTestSkipped('sample clip is too short to trim meaningfully');
      }

      // Keep the middle half of the clip.
      final int startMs = (srcMs * 0.25).round();
      final int endMs = (srcMs * 0.75).round();
      final int expectedMs = endMs - startMs;

      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_trim'),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
        edit: VideoEdit(trimStartMs: startMs, trimEndMs: endMs),
      );

      expect(result, isA<OnSuccess>());
      final OnSuccess ok = result as OnSuccess;
      await expectReadableVideo(compressor, ok.destinationPath);

      final Duration? outDuration =
          (await compressor.getMediaInfo(ok.destinationPath)).duration;
      expect(outDuration, isNotNull);
      final int outMs = outDuration!.inMilliseconds;

      // The trimmed output must be clearly shorter than the source and land
      // near the requested length. Slack is generous because the exact span
      // varies with sync-sample/frame alignment and container timing across
      // platforms.
      expect(
        outMs,
        lessThan(srcMs - 100),
        reason: 'trimmed output ($outMs ms) must be shorter than '
            'the source ($srcMs ms)',
      );
      expect(
        outMs,
        greaterThan((expectedMs * 0.5).round()),
        reason: 'trimmed output ($outMs ms) is far below the requested '
            '~$expectedMs ms',
      );
      expect(
        outMs,
        lessThan(expectedMs + 1000),
        reason: 'trimmed output ($outMs ms) is far above the requested '
            '~$expectedMs ms',
      );
    });

    testWidgets('rotating 90° swaps the displayed dimensions', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      Future<MediaInfo> compressAndInfo(String name, VideoEdit? edit) async {
        final Result r = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(videoName: name),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
          edit: edit,
        );
        expect(r, isA<OnSuccess>());
        final OnSuccess ok = r as OnSuccess;
        await expectReadableVideo(compressor, ok.destinationPath);
        return compressor.getMediaInfo(ok.destinationPath);
      }

      final MediaInfo base = await compressAndInfo('lc_it_rot_base', null);
      final MediaInfo rotated = await compressAndInfo(
        'lc_it_rot_90',
        const VideoEdit(rotationDegrees: 90),
      );

      // A 90° quarter-turn must swap the displayed dimensions relative to the
      // unrotated baseline (works regardless of the source orientation: adding
      // 90° always toggles the display swap). displayWidth/displayHeight are
      // rotation-aware in MediaInfo.
      expect(
        rotated.displayWidth,
        base.displayHeight,
        reason: 'rotated displayWidth should equal the baseline displayHeight',
      );
      expect(
        rotated.displayHeight,
        base.displayWidth,
        reason: 'rotated displayHeight should equal the baseline displayWidth',
      );
    });
  });
}
