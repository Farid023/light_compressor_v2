// End-to-end tests for the Phase 8d two-pass encoder on the REAL native
// pipeline (the package unit tests only cover the mocked MethodChannel).
//
// Two-pass refines a target-size compression: pass 1 encodes at the solved
// bitrate, and only if it OVERSHOOTS the target does pass 2 re-encode lower.
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/two_pass_test.dart -d <deviceId>

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

  group('two-pass encoding (real device)', () {
    testWidgets(
      'two-pass never enlarges the output and tightens it when a 2nd pass runs',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        final int originalBytes = File(source!).lengthSync();
        expect(originalBytes, greaterThan(0));

        // An aggressive target (~40% of the original) is the case most likely
        // to make the single pass overshoot and therefore exercise pass 2.
        final int targetMb =
            (originalBytes * 0.4 / 1000000).ceil().clamp(1, 4096);

        // Single-pass baseline (twoPass defaults to false).
        final Result single = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(videoName: 'lc_it_2pass_single', targetSizeMb: targetMb),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );
        expect(single, isA<OnSuccess>());
        final OnSuccess s1 = single as OnSuccess;
        expect(s1.passesUsed, 1, reason: 'single-pass must report one pass');
        await expectReadableVideo(compressor, s1.destinationPath);

        // Two-pass run with the same target.
        final Result two = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(
            videoName: 'lc_it_2pass_two',
            targetSizeMb: targetMb,
            twoPass: true,
          ),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );
        expect(two, isA<OnSuccess>());
        final OnSuccess s2 = two as OnSuccess;
        await expectReadableVideo(compressor, s2.destinationPath);

        expect(s2.passesUsed, anyOf(1, 2));

        // Two-pass only ever re-encodes at a LOWER bitrate, so it must never
        // produce a meaningfully larger file than the single pass.
        expect(
          s2.compressedSize,
          lessThanOrEqualTo((s1.compressedSize * 1.10).round()),
          reason: 'two-pass should never enlarge the output',
        );

        // When a corrective second pass actually ran, it must have shrunk the
        // output toward the target (that is the whole point of the feature).
        if (s2.passesUsed == 2) {
          expect(
            s2.compressedSize,
            lessThan(s1.compressedSize),
            reason: 'the corrective pass should shrink the output',
          );
        }
      },
    );

    testWidgets(
      'an unreachable target stays single-pass at the floor',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        // 1 MB is below the 2 Mbps floor for any non-trivial clip: the target
        // is unreachable, so a second pass cannot improve it and must be
        // skipped (passesUsed stays 1).
        final Result result = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(
            videoName: 'lc_it_2pass_floor',
            targetSizeMb: 1,
            twoPass: true,
          ),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );

        expect(result, isA<OnSuccess>());
        final OnSuccess ok = result as OnSuccess;
        await expectReadableVideo(compressor, ok.destinationPath);
        expect(
          ok.passesUsed,
          1,
          reason: 'a floor-bound target cannot be improved by a second pass',
        );
      },
    );
  });
}
