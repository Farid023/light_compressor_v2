import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LightCompressor', () {
    late LightCompressor compressor;
    const MethodChannel channel = MethodChannel('light_compressor');
    final List<MethodCall> log = <MethodCall>[];
    String mockedResponse = '';

    setUp(() {
      compressor = LightCompressor();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            return mockedResponse;
          });
    });

    tearDown(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'compressVideo calls startCompression with correct arguments',
      () async {
        mockedResponse = jsonEncode({'onSuccess': '/path/to/output.mp4'});

        await compressor.compressVideo(
          path: '/path/to/input.mp4',
          videoQuality: VideoQuality.medium,
          isMinBitrateCheckEnabled: false,
          disableAudio: true,
          video: Video(
            videoName: 'output.mp4',
            keepOriginalResolution: true,
            videoBitrateInMbps: 2,
            videoHeight: 720,
            videoWidth: 1280,
          ),
          android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
          ios: IOSConfig(saveInGallery: false),
        );

        expect(log, hasLength(1));
        expect(log.first.method, 'startCompression');

        final arguments = log.first.arguments as Map<dynamic, dynamic>;
        expect(arguments['path'], '/path/to/input.mp4');
        expect(arguments['videoQuality'], 'medium');
        expect(arguments['isSharedStorage'], true);
        expect(arguments['saveAt'], 'Movies');
        expect(arguments['disableAudio'], true);
        expect(arguments['keepOriginalResolution'], true);
        expect(arguments['isMinBitrateCheckEnabled'], false);
        expect(arguments['videoBitrateInMbps'], 2);
        expect(arguments['videoHeight'], 720);
        expect(arguments['videoWidth'], 1280);
        expect(arguments['videoName'], 'output.mp4');
        expect(arguments['saveInGallery'], false);
      },
    );

    test('compressVideo returns OnSuccess when successful', () async {
      mockedResponse = jsonEncode({'onSuccess': '/path/to/output.mp4'});

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnSuccess>());
      expect((result as OnSuccess).destinationPath, '/path/to/output.mp4');
    });

    test('compressVideo returns OnFailure when failed', () async {
      mockedResponse = jsonEncode({'onFailure': 'Compression failed'});

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnFailure>());
      expect((result as OnFailure).message, 'Compression failed');
    });

    test('compressVideo returns OnCancelled when cancelled', () async {
      mockedResponse = jsonEncode({'onCancelled': true});

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnCancelled>());
      expect((result as OnCancelled).isCancelled, true);
    });

    test('compressVideo returns OnFailure when response is invalid', () async {
      mockedResponse = jsonEncode({'unknown': 'invalid'});

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnFailure>());
      expect((result as OnFailure).message, 'Something went wrong');
    });

    test('cancelCompression calls cancelCompression method', () async {
      mockedResponse = jsonEncode({'success': true});

      await compressor.cancelCompression();

      expect(log, hasLength(1));
      expect(log.first.method, 'cancelCompression');
    });
  });
}
