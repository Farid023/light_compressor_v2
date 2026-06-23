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

    test('OnFailure contains message', () {
      const result = OnFailure('Failed to compress');
      expect(result.message, 'Failed to compress');
    });

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

    test('copyWith and equality', () {
      const a = MediaInfo(width: 100, height: 200, rotation: 0);
      expect(a, equals(a.copyWith(height: 200)));
      expect(a == a.copyWith(width: 999), isFalse);
      expect(a.hashCode, a.copyWith(height: 200).hashCode);
    });
  });
}
