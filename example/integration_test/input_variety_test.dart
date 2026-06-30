// End-to-end tests that feed the native pipeline UNUSUAL INPUTS, each derived
// from sample.mp4 via our own compressor (no ffmpeg): a no-audio clip, a clip
// that already carries rotation metadata, and an HEVC-encoded clip. Every
// variant is then compressed again to prove the engine handles that input
// shape (the existing suites only ever feed it the plain sample).
//
// VFR (variable-frame-rate) input is intentionally NOT covered: there is no
// ffmpeg-free way to synthesize a VFR asset, and ffmpeg is forbidden here.
//
// Requires a real clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/input_variety_test.dart -d <deviceId>

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

  // Compresses [path] and asserts success, returning the OnSuccess.
  Future<OnSuccess> compress(
    String path,
    String name, {
    VideoFormat videoFormat = VideoFormat.h264,
    bool disableAudio = false,
    VideoEdit? edit,
  }) async {
    final Result r = await compressor.compressVideo(
      path: path,
      videoQuality: VideoQuality.medium,
      isMinBitrateCheckEnabled: false,
      videoFormat: videoFormat,
      disableAudio: disableAudio,
      video: Video(videoName: name),
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
      edit: edit,
    );
    expect(r, isA<OnSuccess>(), reason: 'compressing "$name" should succeed');
    return r as OnSuccess;
  }

  group('input variety (real device)', () {
    testWidgets('compresses a no-audio input without breaking', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      // Derive a silent clip from the sample, then feed it back in: the audio
      // path must handle a source that simply has no audio track.
      final OnSuccess silent = await compress(
        source!,
        'lc_it_noaudio_src',
        disableAudio: true,
      );
      await expectReadableVideo(compressor, silent.destinationPath);

      final OnSuccess out = await compress(
        silent.destinationPath,
        'lc_it_noaudio_out',
      );
      await expectReadableVideo(compressor, out.destinationPath);
    });

    testWidgets('compresses a rotated input and preserves its orientation', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      // Derive a clip that carries 90° rotation metadata.
      final OnSuccess rotated = await compress(
        source!,
        'lc_it_rot_src',
        edit: const VideoEdit(rotationDegrees: 90),
      );
      final MediaInfo rotatedInfo =
          await compressor.getMediaInfo(rotated.destinationPath);

      // Re-compress the rotated input with no edit — the source-rotation
      // handling must yield a valid output with the same displayed orientation.
      final OnSuccess out = await compress(
        rotated.destinationPath,
        'lc_it_rot_out',
      );
      await expectReadableVideo(compressor, out.destinationPath);
      final MediaInfo outInfo =
          await compressor.getMediaInfo(out.destinationPath);

      // Re-compression rescales the resolution, so the exact dims change; what
      // must survive is the ORIENTATION — a rotated-to-portrait clip stays
      // portrait. If the rotation metadata were dropped it would read back
      // landscape (the source's stored orientation).
      final bool inPortrait =
          (rotatedInfo.displayWidth ?? 0) < (rotatedInfo.displayHeight ?? 0);
      final bool outPortrait =
          (outInfo.displayWidth ?? 0) < (outInfo.displayHeight ?? 0);
      expect(
        outPortrait,
        inPortrait,
        reason: 'orientation should survive re-compression: output '
            '${outInfo.displayWidth}x${outInfo.displayHeight} vs input '
            '${rotatedInfo.displayWidth}x${rotatedInfo.displayHeight}',
      );
    });

    testWidgets('decodes an HEVC input (when the device can encode HEVC)', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      // Derive an HEVC clip. If the device has no HEVC encoder it silently
      // falls back to H.264 — then we can't make an HEVC input, so skip.
      final OnSuccess hevc = await compress(
        source!,
        'lc_it_hevc_src',
        videoFormat: VideoFormat.h265,
      );
      if (hevc.usedFormat != VideoFormat.h265) {
        return markTestSkipped(
          'device has no HEVC encoder (fell back to H.264) — '
          'cannot synthesize an HEVC input',
        );
      }
      await expectReadableVideo(compressor, hevc.destinationPath);

      // Re-compress the HEVC input to H.264 — exercises the HEVC decoder.
      final OnSuccess out = await compress(
        hevc.destinationPath,
        'lc_it_hevc_out',
      );
      await expectReadableVideo(compressor, out.destinationPath);
    });
  });
}
