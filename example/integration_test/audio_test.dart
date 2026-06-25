// End-to-end test for the Phase 8c audio re-encode on the REAL native pipeline
// (the package unit tests only cover the mocked MethodChannel).
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — this test SKIPS until it is replaced).
//
//   cd example && flutter test integration_test/audio_test.dart -d <deviceId>

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

  group('audio re-encode (real device)', () {
    testWidgets('re-encoding the audio yields a valid video', (
      WidgetTester tester,
    ) async {
      if (source == null) return markTestSkipped(kNoClipSkipReason);

      // Re-encode the audio to a low AAC bitrate + sample rate. The decode→PCM→
      // encode path and the muxer track ordering must produce a valid file, not
      // hang or corrupt the container.
      final Result result = await compressor.compressVideo(
        path: source!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: 'lc_it_audio'),
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
        audio: const AudioConfig(bitrate: 64000, sampleRate: 44100),
      );

      expect(result, isA<OnSuccess>());
      await expectReadableVideo(
          compressor, (result as OnSuccess).destinationPath);
    });
  });
}
