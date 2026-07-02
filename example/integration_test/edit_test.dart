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

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

    testWidgets('saturation: 0 desaturates the output toward grayscale', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      final int midMs =
          ((await compressor.getMediaInfo(source!)).duration ?? Duration.zero)
                  .inMilliseconds ~/
              2;

      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_gray'),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
        edit: const VideoEdit(saturation: 0.0),
      );
      expect(result, isA<OnSuccess>());
      final OnSuccess ok = result as OnSuccess;
      await expectReadableVideo(compressor, ok.destinationPath);

      // Compare the same frame in the source vs the desaturated output.
      final double srcSpread = await _avgChannelSpread(
        await compressor.getVideoThumbnail(
          source!,
          positionInMs: midMs,
          quality: 90,
        ),
      );
      final double outSpread = await _avgChannelSpread(
        await compressor.getVideoThumbnail(
          ok.destinationPath,
          positionInMs: midMs,
          quality: 90,
        ),
      );

      // The source must have colour to remove, and the output must be close to
      // grey (channels nearly equal). Generous threshold for JPEG chroma noise.
      expect(
        srcSpread,
        greaterThan(outSpread + 6),
        reason: 'source ($srcSpread) should be more colourful than the '
            'desaturated output ($outSpread)',
      );
      expect(
        outSpread,
        lessThan(22),
        reason: 'desaturated output should be near-grayscale ($outSpread)',
      );
    });
  });
}

/// Average per-pixel `|R-G| + |G-B|` over a centered grid of the decoded frame
/// at [path]. Near `0` for a grayscale frame, much larger for a colourful one.
Future<double> _avgChannelSpread(String path) async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
  );
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData data =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final Uint8List px = data.buffer.asUint8List();
  final int w = image.width;
  final int h = image.height;
  int samples = 0;
  double spread = 0;
  for (int y = h ~/ 4; y < h * 3 ~/ 4; y += 8) {
    for (int x = w ~/ 4; x < w * 3 ~/ 4; x += 8) {
      final int i = (y * w + x) * 4;
      spread += (px[i] - px[i + 1]).abs() + (px[i + 1] - px[i + 2]).abs();
      samples++;
    }
  }
  return samples > 0 ? spread / samples : 0;
}
