// End-to-end tests for the Phase 8a target-file-size solver on the REAL native
// pipeline (the package unit tests only cover the mocked MethodChannel).
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/target_size_test.dart -d <deviceId>

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

  group('target file size (real device)', () {
    testWidgets('compresses to at or below the requested size when reachable', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      final int originalBytes = File(source!).lengthSync();
      expect(originalBytes, greaterThan(0));

      // Aim for ~70% of the original — a gentle reduction most clips can hit
      // above the resolution floor.
      final int targetMb =
          (originalBytes * 0.7 / 1000000).ceil().clamp(1, 4096);
      final int targetBytes = targetMb * 1000 * 1000;

      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_targetsize', targetSizeMb: targetMb),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );

      expect(result, isA<OnSuccess>());
      final OnSuccess ok = result as OnSuccess;
      await expectReadableVideo(compressor, ok.destinationPath);

      // Never upscales: the output is not meaningfully larger than the source.
      expect(
          ok.compressedSize, lessThanOrEqualTo((originalBytes * 1.1).round()));

      // The core guarantee: when the target was achievable, the output lands at
      // or below it (with slack for container overhead + single-pass VBR
      // variance, which Phase 8d's two-pass would tighten).
      if (ok.targetSizeMet) {
        expect(
          ok.compressedSize,
          lessThanOrEqualTo((targetBytes * 1.25).round()),
          reason:
              'a met target should yield output at/below the requested size',
        );
      }
    });

    testWidgets('an unreachable target still succeeds (floor, not failure)', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      // 1 MB is below the resolution floor for any non-trivial clip: the
      // compressor must proceed at the floor and produce a valid output rather
      // than fail. (targetSizeMet may be false here — that is the signal.)
      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_targetsize_tiny', targetSizeMb: 1),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );

      expect(result, isA<OnSuccess>());
      await expectReadableVideo(
          compressor, (result as OnSuccess).destinationPath);
    });
  });
}
