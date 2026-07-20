// Edge-invariant tests on the REAL native pipeline — written to *catch bugs*,
// not to pad coverage. Each targets a cross-cutting guarantee that the existing
// suite does not stress directly, and that is plausible to break in the native
// engines (Android MediaCodec/MediaMuxer, Apple AVFoundation):
//
//   * a batch where EVERY item fails still returns one result per slot, in
//     order, and completes (no deadlock / dropped slot);
//   * cancelling a batch never makes a slot reply twice or go missing —
//     exactly one terminal completion per input index;
//   * a trim reports the TRIMMED duration on OnSuccess.duration (the size
//     solver and progress denominator rely on it — the output file being short
//     is not enough);
//   * every progress sample from the real native side stays within 0..100.
//
// Requires a real input clip at example/integration_test/assets/sample.mp4 (the
// committed file is a tiny placeholder — these tests SKIP until it is replaced).
//
//   cd example && flutter test integration_test/edge_invariants_test.dart -d <deviceId>

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

  group('batch invariants (real device)', () {
    const String bogusA = '/does/not/exist_lc_edge_a.mp4';
    const String bogusB = '/does/not/exist_lc_edge_b.mp4';
    const String bogusC = '/does/not/exist_lc_edge_c.mp4';

    testWidgets(
      'a batch where every item fails still returns one OnFailure per slot',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        final List<Result> results = await compressor.compressVideos(
          paths: <String>[bogusA, bogusB, bogusC],
          videoNames: <String>['lc_edge_f0', 'lc_edge_f1', 'lc_edge_f2'],
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );

        // The whole point: an all-bad batch must still complete (not hang) and
        // fill every slot with a terminal failure, in input order.
        expect(results, hasLength(3));
        for (final Result r in results) {
          expect(r, isA<OnFailure>(),
              reason: 'every bogus path must fail its own slot');
          expect((r as OnFailure).message, isNotEmpty);
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    testWidgets(
      'cancelling a batch yields exactly one terminal reply per index',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        final List<BatchItemCompleted> completions = <BatchItemCompleted>[];
        final sub = compressor.onBatchUpdate.listen((BatchEvent e) {
          if (e is BatchItemCompleted) completions.add(e);
        });

        final Future<List<Result>> pending = compressor.compressVideos(
          paths: <String>[source!, source!, source!],
          videoNames: <String>['lc_edge_c0', 'lc_edge_c1', 'lc_edge_c2'],
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );

        // Tolerant by design: on a short clip the batch may finish before the
        // cancel lands. The invariant under test holds either way — no slot may
        // reply twice ("replying twice crashes the engine") and none may vanish.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await compressor.cancelCompression();
        final List<Result> results = await pending;
        await sub.cancel();

        // Every input index resolved to exactly one terminal result, in order.
        expect(results, hasLength(3));
        for (final Result r in results) {
          expect(
            r is OnSuccess || r is OnFailure || r is OnCancelled,
            isTrue,
            reason: 'each slot must reach a terminal result',
          );
        }

        // The completion stream must show each index at most once (a duplicate
        // index would mean a slot fired twice — the reply-once violation).
        final List<int> indices =
            completions.map((BatchItemCompleted e) => e.index).toList();
        expect(
          indices.toSet().length,
          indices.length,
          reason: 'an index appearing twice means a slot replied twice: '
              '$indices',
        );
        for (final int i in indices) {
          expect(i, inInclusiveRange(0, 2),
              reason: 'completion index $i is outside the input range');
        }
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );
  });

  group('trim reports the trimmed duration (real device)', () {
    testWidgets(
      'OnSuccess.duration reflects the kept range, not the source length',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        final Duration? srcDuration =
            (await compressor.getMediaInfo(source!)).duration;
        expect(srcDuration, isNotNull);
        final int srcMs = srcDuration!.inMilliseconds;
        if (srcMs < 1000) {
          return markTestSkipped(
              'sample clip is too short to trim meaningfully');
        }

        final int startMs = (srcMs * 0.25).round();
        final int endMs = (srcMs * 0.75).round();
        final double expectedSec = (endMs - startMs) / 1000.0;

        final Result result = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(videoName: 'lc_edge_trimdur'),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
          edit: VideoEdit(trimStartMs: startMs, trimEndMs: endMs),
        );

        expect(result, isA<OnSuccess>());
        final OnSuccess ok = result as OnSuccess;

        // The reported duration must be the TRIMMED span, well under the source.
        // If the native reports the source length here, the size solver and the
        // progress denominator are both wrong even though the output file is
        // short — this is what the assertion guards.
        expect(
          ok.duration,
          lessThan(srcMs / 1000.0 - 0.1),
          reason:
              'reported duration ${ok.duration}s should be the trimmed span, '
              'not the ${srcMs / 1000.0}s source',
        );
        expect(
          ok.duration,
          greaterThan(expectedSec * 0.5),
          reason: 'reported duration ${ok.duration}s is far below the '
              'requested ~${expectedSec}s',
        );
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });

  group('progress stays in range (real device)', () {
    testWidgets(
      'every onProgressDetail sample is within 0..100',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        final List<double> percents = <double>[];
        final sub = compressor.onProgressDetail.listen((CompressionProgress p) {
          percents.add(p.percent);
        });

        final Result result = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(videoName: 'lc_edge_prog'),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );
        await sub.cancel();

        expect(result, isA<OnSuccess>());
        expect(percents, isNotEmpty,
            reason: 'a real compression should emit progress');
        for (final double p in percents) {
          expect(p.isNaN, isFalse, reason: 'progress emitted NaN');
          expect(p, inInclusiveRange(0.0, 100.0),
              reason: 'native emitted an out-of-range percent: $p');
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });

  group('audio passthrough mux (issue #17)', () {
    testWidgets(
      'default compression of an audio-bearing clip does not crash the writer',
      (WidgetTester tester) async {
        if (source == null) return markTestSkipped(kNoClipSkipReason);

        // Regression guard for issue #17. With NO AudioConfig (the default), the
        // source audio is muxed through untouched. The native writer needs the
        // source format description to do that; without it, AVAssetWriter's
        // addInput throws NSInvalidArgumentException ("provide a format hint")
        // on a REAL iOS device. The simulator and macOS are lenient, so this
        // stays green there whether or not the fix is present — its value is on
        // physical iOS hardware / CI-on-device.
        final Result result = await compressor.compressVideo(
          path: source!,
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          video: Video(videoName: 'lc_edge_audiopass'),
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
        );

        expect(result, isA<OnSuccess>(),
            reason: 'passthrough audio compression must not crash or fail');
        await expectReadableVideo(
            compressor, (result as OnSuccess).destinationPath);
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
