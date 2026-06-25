import 'package:flutter_test/flutter_test.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

void main() {
  group('AndroidConfig', () {
    test('default values', () {
      final config = AndroidConfig();
      expect(config.isSharedStorage, true);
      expect(config.saveAt, SaveAt.Movies);
    });

    test('custom values', () {
      final config = AndroidConfig(
        isSharedStorage: false,
        saveAt: SaveAt.Pictures,
      );
      expect(config.isSharedStorage, false);
      expect(config.saveAt, SaveAt.Pictures);
    });
  });

  group('IOSConfig', () {
    test('default values', () {
      final config = IOSConfig();
      expect(config.saveInGallery, true);
    });

    test('custom values', () {
      final config = IOSConfig(saveInGallery: false);
      expect(config.saveInGallery, false);
    });
  });

  group('Video', () {
    test('required properties', () {
      final video = Video(videoName: 'test.mp4');
      expect(video.videoName, 'test.mp4');
      expect(video.keepOriginalResolution, false);
      expect(video.videoBitrateInMbps, null);
      expect(video.videoHeight, null);
      expect(video.videoWidth, null);
    });

    test('custom values', () {
      final video = Video(
        videoName: 'test.mp4',
        keepOriginalResolution: true,
        videoBitrateInMbps: 5,
        videoHeight: 720,
        videoWidth: 1280,
      );
      expect(video.videoName, 'test.mp4');
      expect(video.keepOriginalResolution, true);
      expect(video.videoBitrateInMbps, 5);
      expect(video.videoHeight, 720);
      expect(video.videoWidth, 1280);
    });

    test('targetSizeMb defaults to null and can be set', () {
      expect(Video(videoName: 'test.mp4').targetSizeMb, isNull);
      expect(Video(videoName: 'test.mp4', targetSizeMb: 10).targetSizeMb, 10);
    });

    test(
      'asserts targetSizeMb and videoBitrateInMbps are mutually exclusive',
      () {
        expect(
          () => Video(
            videoName: 't.mp4',
            targetSizeMb: 10,
            videoBitrateInMbps: 5,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('asserts targetSizeMb is positive', () {
      expect(
        () => Video(videoName: 't.mp4', targetSizeMb: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('videoFps defaults to null and can be set', () {
      expect(Video(videoName: 'test.mp4').videoFps, isNull);
      expect(Video(videoName: 'test.mp4', videoFps: 24).videoFps, 24);
    });

    test('asserts videoFps is positive', () {
      expect(
        () => Video(videoName: 't.mp4', videoFps: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('CompressionResult', () {
    test('OnSuccess contains destinationPath', () {
      const result = OnSuccess(
        destinationPath: '/path/to/video.mp4',
        originalSize: 1000,
        compressedSize: 500,
        duration: 10.0,
        ratio: 50.0,
      );
      expect(result.destinationPath, '/path/to/video.mp4');
      expect(result.originalSize, 1000);
      expect(result.compressedSize, 500);
      expect(result.duration, 10.0);
      expect(result.ratio, 50.0);
      // Defaults to H.264 when not specified.
      expect(result.usedFormat, VideoFormat.h264);
    });

    test('OnSuccess carries the codec actually used', () {
      const result = OnSuccess(
        destinationPath: '/path/to/video.mp4',
        originalSize: 1000,
        compressedSize: 500,
        duration: 10.0,
        ratio: 50.0,
        usedFormat: VideoFormat.h265,
      );
      expect(result.usedFormat, VideoFormat.h265);
    });

    test('OnSuccess targetSizeMet defaults to true and can be set false', () {
      const met = OnSuccess(
        destinationPath: '/path/to/video.mp4',
        originalSize: 1000,
        compressedSize: 500,
        duration: 10.0,
        ratio: 50.0,
      );
      expect(met.targetSizeMet, true);

      const unmet = OnSuccess(
        destinationPath: '/path/to/video.mp4',
        originalSize: 1000,
        compressedSize: 500,
        duration: 10.0,
        ratio: 50.0,
        targetSizeMet: false,
      );
      expect(unmet.targetSizeMet, false);
    });

    test('OnFailure contains message', () {
      const result = OnFailure('Failed to compress');
      expect(result.message, 'Failed to compress');
    });

    test(
      'OnFailure defaults failureType to unknown and carries an explicit one',
      () {
        const a = OnFailure('boom');
        expect(a.failureType, CompressionFailureType.unknown);
        const b = OnFailure(
          'denied',
          failureType: CompressionFailureType.permission,
        );
        expect(b.failureType, CompressionFailureType.permission);
      },
    );

    test('OnCancelled contains isCancelled', () {
      const result = OnCancelled(isCancelled: true);
      expect(result.isCancelled, true);
    });
  });

  group('MediaInfo', () {
    test('fromMap parses all fields', () {
      final info = MediaInfo.fromMap(<String, dynamic>{
        'width': 1920,
        'height': 1080,
        'durationMs': 66000,
        'fileSize': 227712771,
        'bitrate': 27000000,
        'rotation': 90,
        'frameRate': 30.0,
        'mimeType': 'video/mp4',
      });

      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.duration, const Duration(milliseconds: 66000));
      expect(info.fileSize, 227712771);
      expect(info.bitrate, 27000000);
      expect(info.rotation, 90);
      expect(info.frameRate, 30.0);
      expect(info.mimeType, 'video/mp4');
    });

    test('fromMap tolerates missing fields', () {
      final info = MediaInfo.fromMap(<String, dynamic>{});
      expect(info.width, isNull);
      expect(info.height, isNull);
      expect(info.duration, isNull);
      expect(info.bitrate, isNull);
      expect(info.mimeType, isNull);
    });

    test('zero duration maps to null', () {
      final info = MediaInfo.fromMap(<String, dynamic>{'durationMs': 0});
      expect(info.duration, isNull);
    });

    test('non-positive numeric metadata maps to null', () {
      final info = MediaInfo.fromMap(<String, dynamic>{
        'width': 0,
        'height': -1,
        'bitrate': -4,
        'frameRate': 0.0,
        'rotation': 0,
      });
      expect(info.width, isNull);
      expect(info.height, isNull);
      expect(info.bitrate, isNull);
      expect(info.frameRate, isNull);
      // rotation == 0 is valid and must be preserved.
      expect(info.rotation, 0);
    });

    test('displayWidth/displayHeight swap on 90/270 rotation', () {
      final rotated = MediaInfo.fromMap(<String, dynamic>{
        'width': 1920,
        'height': 1080,
        'rotation': 90,
      });
      expect(rotated.displayWidth, 1080);
      expect(rotated.displayHeight, 1920);

      final upright = MediaInfo.fromMap(<String, dynamic>{
        'width': 1920,
        'height': 1080,
        'rotation': 0,
      });
      expect(upright.displayWidth, 1920);
      expect(upright.displayHeight, 1080);
    });

    test('rotation 180 keeps dimensions; 270 swaps them', () {
      final r180 = MediaInfo.fromMap(<String, dynamic>{
        'width': 1920,
        'height': 1080,
        'rotation': 180,
      });
      expect(r180.displayWidth, 1920);
      expect(r180.displayHeight, 1080);

      final r270 = MediaInfo.fromMap(<String, dynamic>{
        'width': 1920,
        'height': 1080,
        'rotation': 270,
      });
      expect(r270.displayWidth, 1080);
      expect(r270.displayHeight, 1920);
    });

    test('fromMap coerces integer bitrate/frameRate', () {
      final info = MediaInfo.fromMap(<String, dynamic>{
        'width': 100,
        'height': 100,
        'bitrate': 5000000,
        'frameRate': 30,
      });
      expect(info.bitrate, 5000000);
      expect(info.frameRate, 30.0);
    });

    test('copyWith and equality', () {
      const a = MediaInfo(width: 100, height: 200, rotation: 0);
      expect(a, equals(a.copyWith(height: 200)));
      expect(a == a.copyWith(width: 999), isFalse);
      expect(a.hashCode, a.copyWith(height: 200).hashCode);
    });
  });

  group('CompressionEstimate', () {
    test('fromMap parses and coerces numeric fields', () {
      final est = CompressionEstimate.fromMap(<String, dynamic>{
        'originalSizeBytes': 1000,
        'estimatedSizeBytes': 250,
        'targetBitrate': 2000000,
        'outputWidth': 1280,
        'outputHeight': 720,
        'estimatedRatio': 75, // int on the wire → coerced to double
      });
      expect(est.originalSizeBytes, 1000);
      expect(est.estimatedSizeBytes, 250);
      expect(est.targetBitrate, 2000000);
      expect(est.outputWidth, 1280);
      expect(est.outputHeight, 720);
      expect(est.estimatedRatio, 75.0);
    });

    test('fromMap defaults missing fields to zero', () {
      final est = CompressionEstimate.fromMap(<String, dynamic>{});
      expect(est.originalSizeBytes, 0);
      expect(est.estimatedSizeBytes, 0);
      expect(est.targetBitrate, 0);
      expect(est.outputWidth, 0);
      expect(est.outputHeight, 0);
      expect(est.estimatedRatio, 0.0);
    });
  });

  group('ThumbnailRequest', () {
    test('default quality is 50', () {
      const r = ThumbnailRequest(positionInMs: 1000);
      expect(r.positionInMs, 1000);
      expect(r.quality, 50);
    });

    test('custom values', () {
      const r = ThumbnailRequest(positionInMs: 2000, quality: 90);
      expect(r.positionInMs, 2000);
      expect(r.quality, 90);
    });
  });
}
