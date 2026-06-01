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
      const result = OnSuccess('/path/to/video.mp4');
      expect(result.destinationPath, '/path/to/video.mp4');
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
}
