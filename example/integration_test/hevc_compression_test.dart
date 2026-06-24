// End-to-end tests for the H.264 / H.265 codec selection on the REAL native
// pipeline (the package unit tests only cover the mocked MethodChannel).
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/hevc_compression_test.dart -d <deviceId>
//
// Codec note: the only codec signal exposed to Dart is OnSuccess.usedFormat
// (getMediaInfo reports the container, not the codec), so these tests trust
// usedFormat for the codec claim and additionally assert the output is valid.

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

  Future<OnSuccess> compress(VideoFormat format, String outputName) async {
    final Result result = await compressor.compressVideo(
      path: source!,
      videoQuality: VideoQuality.medium,
      isMinBitrateCheckEnabled: false,
      videoFormat: format,
      video: Video(videoName: outputName),
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
    );
    expect(result, isA<OnSuccess>(), reason: 'compression should succeed');
    final OnSuccess success = result as OnSuccess;
    expect(success.destinationPath, isNotEmpty);
    expect(success.compressedSize, greaterThan(0));
    return success;
  }

  group('HEVC compression (real device)', () {
    testWidgets('H.264 produces a valid file reported as h264', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final OnSuccess ok = await compress(VideoFormat.h264, 'lc_it_h264');
      expect(ok.usedFormat, VideoFormat.h264);
      await expectReadableVideo(compressor, ok.destinationPath);
    });

    testWidgets(
        'H.265 is honoured or falls back, and the report matches a '
        'valid file', (WidgetTester tester) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final OnSuccess ok = await compress(VideoFormat.h265, 'lc_it_h265');
      // With a hardware HEVC encoder -> h265; otherwise the documented fallback
      // -> h264. Either is correct; the contract is that the reported format is
      // one of the two and the output is a real, playable video.
      expect(ok.usedFormat, anyOf(VideoFormat.h265, VideoFormat.h264));
      await expectReadableVideo(compressor, ok.destinationPath);
    });

    testWidgets('batch compresses every input requesting h265', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);
      final List<Result> results = await compressor.compressVideos(
        paths: <String>[source!, source!],
        videoNames: <String>['lc_it_b0', 'lc_it_b1'],
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        videoFormat: VideoFormat.h265,
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
      );
      expect(results, hasLength(2));
      expect(
        results.every((Result r) => r is OnSuccess),
        isTrue,
        reason: 'every video in the batch should succeed',
      );
      for (final Result r in results) {
        expect(
          (r as OnSuccess).usedFormat,
          anyOf(VideoFormat.h265, VideoFormat.h264),
        );
      }
    });
  });
}
