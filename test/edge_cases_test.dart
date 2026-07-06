import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

/// Adversarial edge-case tests aimed at *finding* defects, not padding coverage.
///
/// Some tests here assert the behaviour the contract *should* have (e.g. progress
/// must be within 0..100 on every path). If one fails, it has surfaced a real
/// inconsistency in the library — that is the point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final LightCompressor compressor = LightCompressor();
  const MethodChannel method = MethodChannel('light_compressor');
  const EventChannel single = EventChannel('compression/stream');
  const EventChannel batch = EventChannel('compression/batch-stream');
  final List<MethodCall> log = <MethodCall>[];
  String compressResponse = '';
  Object? batchResponse;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(method, (MethodCall call) async {
      log.add(call);
      if (call.method == 'startBatchCompression') return batchResponse;
      return compressResponse;
    });
  });

  tearDown(() {
    log.clear();
    batchResponse = null;
    messenger
      ..setMockMethodCallHandler(method, null)
      ..setMockStreamHandler(single, null)
      ..setMockStreamHandler(batch, null);
  });

  void emitBatch(List<Map<String, dynamic>> events) {
    messenger.setMockStreamHandler(
      batch,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {
          for (final Map<String, dynamic> e in events) {
            sink.success(e);
          }
          sink.endOfStream();
        },
      ),
    );
  }

  void emitSingle(List<Object?> events) {
    messenger.setMockStreamHandler(
      single,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {
          for (final Object? e in events) {
            sink.success(e);
          }
          sink.endOfStream();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progress must always be a sane 0..100 on EVERY path. The single-video path
  // clamps (compression_progress.dart); these check the batch path matches.
  // ---------------------------------------------------------------------------

  group('progress bounds', () {
    test('batch per-item percent is clamped to 0..100 (like the single path)',
        () async {
      emitBatch(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'progress', 'index': 0, 'percent': 150.0},
        <String, dynamic>{'type': 'progress', 'index': 0, 'percent': -10.0},
      ]);

      final List<BatchEvent> events =
          await compressor.onBatchUpdate.take(2).toList();

      expect((events[0] as BatchProgress).percent, 100.0);
      expect((events[1] as BatchProgress).percent, 0.0);
    });

    test('batch overallPercent is clamped to 0..100', () async {
      emitBatch(<Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'progress',
          'index': 0,
          'percent': 50.0,
          'overallPercent': 150.0,
        },
      ]);

      final BatchProgress p = (await compressor.onBatchUpdate.take(1).toList())
          .first as BatchProgress;

      expect(p.overallPercent, 100.0);
    });

    test('CONTRAST: single onProgressDetail percent IS clamped', () async {
      emitSingle(<Object?>[
        <String, dynamic>{'percent': 150.0}
      ]);

      final CompressionProgress p =
          (await compressor.onProgressDetail.take(1).toList()).first;

      expect(p.percent, 100.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Numeric-safety guards: never emit NaN / Infinity / crash on odd sizes.
  // ---------------------------------------------------------------------------

  group('ratio safety', () {
    test('ratio is 0.0 (never NaN) when originalSize is 0', () async {
      compressResponse = jsonEncode(<String, dynamic>{
        'onSuccess': '/nonexistent-output.mp4',
        'duration': 1.0,
        'originalSize': 0,
        'compressedSize': 0,
      });

      final Result r = await compressor.compressVideo(
        path: '/nonexistent-input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'out.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(r, isA<OnSuccess>());
      final double ratio = (r as OnSuccess).ratio;
      expect(ratio.isNaN, isFalse);
      expect(ratio.isInfinite, isFalse);
      expect(ratio, 0.0);
    });

    test('ratio stays within 0..100 for a huge compressed size', () async {
      compressResponse = jsonEncode(<String, dynamic>{
        'onSuccess': '/nonexistent-output.mp4',
        'duration': 1.0,
        'originalSize': 10,
        'compressedSize': 9999999999,
      });

      final OnSuccess r = await compressor.compressVideo(
        path: '/nonexistent-input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'out.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      ) as OnSuccess;

      expect(r.ratio, inInclusiveRange(0.0, 100.0));
    });
  });

  // ---------------------------------------------------------------------------
  // compressVideos input-contract guards.
  // ---------------------------------------------------------------------------

  group('compressVideos contract', () {
    test('empty paths short-circuits to [] without hitting the channel',
        () async {
      final List<Result> results = await compressor.compressVideos(
        paths: <String>[],
        videoNames: <String>[],
        videoQuality: VideoQuality.medium,
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(results, isEmpty);
      expect(
        log.where((MethodCall c) => c.method == 'startBatchCompression'),
        isEmpty,
      );
    });

    test('mismatched paths/videoNames lengths throw before the channel', () {
      expect(
        () => compressor.compressVideos(
          paths: <String>['/a.mp4', '/b.mp4'],
          videoNames: <String>['only-one.mp4'],
          videoQuality: VideoQuality.medium,
          android: AndroidConfig(),
          ios: IOSConfig(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
