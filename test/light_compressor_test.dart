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
    Object? mediaInfoResponse;
    Object? thumbnailResponse;
    Object? batchResponse;
    PlatformException? platformError;

    setUp(() {
      compressor = LightCompressor();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (platformError != null) {
              throw platformError!;
            }
            switch (methodCall.method) {
              case 'getMediaInfo':
                return mediaInfoResponse;
              case 'getVideoThumbnail':
                return thumbnailResponse;
              case 'startBatchCompression':
                return batchResponse;
              default:
                return mockedResponse;
            }
          });
    });

    tearDown(() {
      log.clear();
      mediaInfoResponse = null;
      thumbnailResponse = null;
      batchResponse = null;
      platformError = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'compressVideo calls startCompression with correct arguments',
      () async {
        mockedResponse = jsonEncode({
          'onSuccess': '/path/to/output.mp4',
          'duration': 5.5,
        });

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

    test('compressVideo forwards BackgroundConfig as a background map', () async {
      mockedResponse = jsonEncode({'onSuccess': '/path/to/output.mp4'});

      await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
        background: const BackgroundConfig(notificationTitle: 'Title'),
      );

      final arguments = log.first.arguments as Map<dynamic, dynamic>;
      expect(arguments['background'], <String, dynamic>{
        'notificationTitle': 'Title',
      });
    });

    test('compressVideo sends a null background when not requested', () async {
      mockedResponse = jsonEncode({'onSuccess': '/path/to/output.mp4'});

      await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      final arguments = log.first.arguments as Map<dynamic, dynamic>;
      expect(arguments.containsKey('background'), isTrue);
      expect(arguments['background'], isNull);
    });

    test('compressVideos forwards BackgroundConfig defaults', () async {
      batchResponse = <Map<String, dynamic>>[
        {'onSuccess': '/out0.mp4'},
      ];

      await compressor.compressVideos(
        paths: ['/a.mp4'],
        videoNames: ['out0.mp4'],
        videoQuality: VideoQuality.medium,
        android: AndroidConfig(),
        ios: IOSConfig(),
        background: const BackgroundConfig(),
      );

      final arguments = log.last.arguments as Map<dynamic, dynamic>;
      final background = arguments['background'] as Map<dynamic, dynamic>;
      expect(background['notificationTitle'], 'Compressing video');
    });

    test('compressVideo returns OnSuccess when successful', () async {
      mockedResponse = jsonEncode({
        'onSuccess': '/path/to/output.mp4',
        'duration': 5.5,
      });

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnSuccess>());
      expect((result as OnSuccess).destinationPath, '/path/to/output.mp4');
      expect(result.duration, 5.5);
    });

    test('compressVideo computes statistics from native sizes', () async {
      mockedResponse = jsonEncode({
        'onSuccess': '/path/to/output.mp4',
        'duration': 5.5,
        'originalSize': 1000,
        'compressedSize': 250,
      });

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnSuccess>());
      result as OnSuccess;
      expect(result.originalSize, 1000);
      expect(result.compressedSize, 250);
      expect(result.ratio, 75.0);
    });

    test('compressVideo clamps ratio to zero when output grows', () async {
      mockedResponse = jsonEncode({
        'onSuccess': '/path/to/output.mp4',
        'duration': 1.0,
        'originalSize': 500,
        'compressedSize': 800,
      });

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnSuccess>());
      expect((result as OnSuccess).ratio, 0.0);
    });

    test('compressVideo returns OnFailure when output path is empty', () async {
      mockedResponse = jsonEncode({'onSuccess': ''});

      final result = await compressor.compressVideo(
        path: '/path/to/input.mp4',
        videoQuality: VideoQuality.medium,
        video: Video(videoName: 'output.mp4'),
        android: AndroidConfig(),
        ios: IOSConfig(),
      );

      expect(result, isA<OnFailure>());
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

    test(
      'compressVideo throws PermissionDeniedException when native fails with permission error',
      () async {
        mockedResponse = jsonEncode({'onFailure': 'Permission denied'});

        expect(
          () => compressor.compressVideo(
            path: '/path/to/input.mp4',
            videoQuality: VideoQuality.medium,
            video: Video(videoName: 'output.mp4'),
            android: AndroidConfig(),
            ios: IOSConfig(),
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'compressVideo throws UnsupportedVideoException when native fails with unsupported codec',
      () async {
        mockedResponse = jsonEncode({'onFailure': 'Unsupported video codec'});

        expect(
          () => compressor.compressVideo(
            path: '/path/to/input.mp4',
            videoQuality: VideoQuality.medium,
            video: Video(videoName: 'output.mp4'),
            android: AndroidConfig(),
            ios: IOSConfig(),
          ),
          throwsA(isA<UnsupportedVideoException>()),
        );
      },
    );

    test('compressVideo maps failureType code to typed exception', () async {
      // Message text gives no hint; classification must come from failureType.
      mockedResponse = jsonEncode({
        'onFailure': 'Something broke',
        'failureType': 'unsupported',
      });

      expect(
        () => compressor.compressVideo(
          path: '/path/to/input.mp4',
          videoQuality: VideoQuality.medium,
          video: Video(videoName: 'output.mp4'),
          android: AndroidConfig(),
          ios: IOSConfig(),
        ),
        throwsA(isA<UnsupportedVideoException>()),
      );
    });

    test(
      'compressVideo returns OnFailure when failureType is unknown',
      () async {
        mockedResponse = jsonEncode({
          'onFailure': 'Some opaque error',
          'failureType': 'unknown',
        });

        final result = await compressor.compressVideo(
          path: '/path/to/input.mp4',
          videoQuality: VideoQuality.medium,
          video: Video(videoName: 'output.mp4'),
          android: AndroidConfig(),
          ios: IOSConfig(),
        );

        expect(result, isA<OnFailure>());
        expect((result as OnFailure).message, 'Some opaque error');
      },
    );

    test(
      'compressVideo throws VideoNotFoundException when native fails with file not found',
      () async {
        mockedResponse = jsonEncode({
          'onFailure': 'File not found or does not exist',
        });

        expect(
          () => compressor.compressVideo(
            path: '/path/to/input.mp4',
            videoQuality: VideoQuality.medium,
            video: Video(videoName: 'output.mp4'),
            android: AndroidConfig(),
            ios: IOSConfig(),
          ),
          throwsA(isA<VideoNotFoundException>()),
        );
      },
    );

    test('cancelCompression calls cancelCompression method', () async {
      mockedResponse = jsonEncode({'success': true});

      await compressor.cancelCompression();

      expect(log, hasLength(1));
      expect(log.first.method, 'cancelCompression');
    });
    test('clearCache calls clearCache method', () async {
      mockedResponse = jsonEncode({'success': true});

      await compressor.clearCache();

      expect(log, hasLength(1));
      expect(log.first.method, 'clearCache');
    });

    test('getMediaInfo returns parsed MediaInfo', () async {
      mediaInfoResponse = <String, dynamic>{
        'width': 1920,
        'height': 1080,
        'durationMs': 66000,
        'fileSize': 1000,
        'bitrate': 5000000,
        'rotation': 0,
        'frameRate': 30.0,
        'mimeType': 'video/mp4',
      };

      final info = await compressor.getMediaInfo('/path/to/input.mp4');

      expect(log.last.method, 'getMediaInfo');
      expect(log.last.arguments, <String, dynamic>{
        'path': '/path/to/input.mp4',
      });
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.duration, const Duration(seconds: 66));
      expect(info.mimeType, 'video/mp4');
    });

    test(
      'getMediaInfo throws VideoNotFoundException on native error',
      () async {
        platformError = PlatformException(
          code: 'VIDEO_NOT_FOUND',
          message: 'missing',
        );

        expect(
          () => compressor.getMediaInfo('/path/to/input.mp4'),
          throwsA(isA<VideoNotFoundException>()),
        );
      },
    );

    test('getMediaInfo throws MediaInfoException on generic error', () async {
      platformError = PlatformException(
        code: 'MEDIA_INFO_FAILED',
        message: 'boom',
      );

      expect(
        () => compressor.getMediaInfo('/path/to/input.mp4'),
        throwsA(isA<MediaInfoException>()),
      );
    });

    test('getVideoThumbnail returns path and forwards arguments', () async {
      thumbnailResponse = '/cache/thumb_1.jpg';

      final path = await compressor.getVideoThumbnail(
        '/path/to/input.mp4',
        positionInMs: 5000,
        quality: 80,
      );

      expect(path, '/cache/thumb_1.jpg');
      expect(log.last.method, 'getVideoThumbnail');
      final args = log.last.arguments as Map<dynamic, dynamic>;
      expect(args['path'], '/path/to/input.mp4');
      expect(args['positionInMs'], 5000);
      expect(args['quality'], 80);
    });

    test('getVideoThumbnail clamps quality to 0..100', () async {
      thumbnailResponse = '/cache/thumb_1.jpg';

      await compressor.getVideoThumbnail('/path/to/input.mp4', quality: 250);

      final args = log.last.arguments as Map<dynamic, dynamic>;
      expect(args['quality'], 100);
    });

    test(
      'getVideoThumbnail throws ThumbnailException when native returns null',
      () async {
        thumbnailResponse = null;

        expect(
          () => compressor.getVideoThumbnail('/path/to/input.mp4'),
          throwsA(isA<ThumbnailException>()),
        );
      },
    );

    test(
      'getVideoThumbnail maps permission error to PermissionDeniedException',
      () async {
        platformError = PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'denied',
        );

        expect(
          () => compressor.getVideoThumbnail('/path/to/input.mp4'),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'compressVideos returns ordered results and forwards arguments',
      () async {
        batchResponse = <Map<String, dynamic>>[
          {
            'onSuccess': '/out0.mp4',
            'originalSize': 1000,
            'compressedSize': 400,
            'duration': 5.0,
          },
          {'onFailure': 'bad codec'},
        ];

        final results = await compressor.compressVideos(
          paths: ['/a.mp4', '/b.mp4'],
          videoNames: ['out0.mp4', 'out1.mp4'],
          videoQuality: VideoQuality.high,
          android: AndroidConfig(
            isSharedStorage: false,
            saveAt: SaveAt.Pictures,
          ),
          ios: IOSConfig(saveInGallery: true),
          videoWidth: 1280,
          videoHeight: 720,
          disableAudio: true,
        );

        expect(log.last.method, 'startBatchCompression');
        final args = log.last.arguments as Map<dynamic, dynamic>;
        expect(args['paths'], ['/a.mp4', '/b.mp4']);
        expect(args['videoNames'], ['out0.mp4', 'out1.mp4']);
        expect(args['videoQuality'], 'high');
        expect(args['saveAt'], 'Pictures');
        expect(args['videoWidth'], 1280);
        expect(args['disableAudio'], true);

        expect(results, hasLength(2));
        expect(results[0], isA<OnSuccess>());
        expect((results[0] as OnSuccess).ratio, 60.0);
        expect(results[1], isA<OnFailure>());
        expect((results[1] as OnFailure).message, 'bad codec');
      },
    );

    test(
      'compressVideos returns empty list and skips channel for empty input',
      () async {
        final results = await compressor.compressVideos(
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
      },
    );
  });
}
