# light_compressor_v2

[![Pub Version](https://img.shields.io/pub/v/light_compressor_v2.svg)](https://pub.dev/packages/light_compressor_v2)
[![Pub Platforms](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS-blue)](https://pub.dev/packages/light_compressor_v2)
[![Pub Likes](https://img.shields.io/pub/likes/light_compressor_v2)](https://pub.dev/packages/light_compressor_v2)

A powerful, easy-to-use video compression plugin for Flutter. Forked from [light_compressor](https://pub.dev/packages/light_compressor) and modernized by [Farid Gurbanov](https://github.com/Farid023).

This plugin generates a compressed MP4 video with modified width, height, and bitrate. It is built on top of the native [LightCompressor](https://github.com/AbedElazizShe/LightCompressor) library for Android and [LightCompressor_iOS](https://github.com/AbedElazizShe/LightCompressor_iOS) for iOS and macOS.

## 🛠️ How it Works

Extreme high bitrates are reduced while maintaining good video quality, resulting in a much smaller file size.

* **Quality Presets:** You can choose between 5 compression qualities: `very_low`, `low`, `medium`, `high`, or `very_high`. The plugin automatically handles generating the correct bitrate for the output video.
* **Minimum Bitrate Guard:** The plugin checks if you want to enforce a minimum bitrate threshold (default is **2 Mbps**) via `isMinBitrateCheckEnabled`. This prevents low-resolution or already compressed videos from being compressed repeatedly, avoiding cumulative quality degradation.

---

## ✨ Features

- **Five quality presets** — `very_low`, `low`, `medium`, `high`, `very_high` — the plugin calculates the optimal bitrate automatically.
- **Custom resolution & bitrate** — override width, height, and bitrate directly when presets aren't enough.
- **Minimum bitrate guard** — optionally skip compression for already-low-bitrate videos to avoid quality degradation.
- **Streamable output** — produce MP4 files with the moov atom placed at the front for fast playback start.
- **Progress stream** — listen to real-time compression percentage via a Dart `Stream<double>`.
- **Cancellation** — cancel any in-progress compression with a single call.
- **Disable audio** — generate silent videos when audio isn't needed.
- **iOS / macOS: Swift Package Manager (SPM)** support alongside CocoaPods.
- **Android: fully Kotlin** native layer — no Java dependencies, Gradle KTS build script.
- **Updated example app** with Material 3, file picker, and video player.

---

## 📸 Demo

<p align="left">
  <img src="https://raw.githubusercontent.com/Farid023/light_compressor_v2/master/pictures/demo.gif" alt="Demo GIF" width="300" />
</p>

---

## 📱 Platform Support

| iOS | Android | macOS | Web | Windows | Linux |
|:---:|:-------:|:-----:|:---:|:-------:|:-----:|
| ✅  |   ✅    |  ✅   | ❌  |   ❌    |  ❌   |

**Minimum versions:** iOS 11 · Android API 24 · macOS 10.15

---

## 📦 Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  light_compressor_v2: ^1.0.1
```

Then run:

```bash
flutter pub get
```

### iOS / macOS — Podfile

No extra Podfile configuration is required. The plugin ships with both a `.podspec` (CocoaPods) and a `Package.swift` (SPM). Flutter will pick the appropriate integration automatically.

### Android — minSdk

The plugin requires **minSdk 24**. If your app targets a lower SDK, update your `android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        minSdk = 24
    }
}
```

---

## 🚀 Usage

```dart
import 'package:light_compressor_v2/light_compressor_v2.dart';

final compressor = LightCompressor();

// Start compression
final Result response = await compressor.compressVideo(
  path: '/path/to/source.mp4',
  videoQuality: VideoQuality.medium,
  isMinBitrateCheckEnabled: false,
  video: Video(videoName: 'compressed_output.mp4'),
  android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: true),
);

// Handle result
if (response is OnSuccess) {
  print('Compressed to: ${response.destinationPath}');
} else if (response is OnFailure) {
  print('Error: ${response.message}');
} else if (response is OnCancelled) {
  print('Cancelled: ${response.isCancelled}');
}
```

### Listening to progress

```dart
StreamBuilder<double>(
  stream: compressor.onProgressUpdated,
  builder: (context, snapshot) {
    final percent = snapshot.data ?? 0;
    return Text('${percent.toStringAsFixed(0)}%');
  },
);
```

### Cancelling compression

```dart
compressor.cancelCompression();
```

---

## 📖 API Reference

### `LightCompressor.compressVideo()`

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `path` | `String` | ✅ | — | Absolute path to the source video file. |
| `videoQuality` | `VideoQuality` | ✅ | — | Quality preset: `very_low`, `low`, `medium`, `high`, `very_high`. |
| `android` | `AndroidConfig` | ✅ | — | Android-specific storage configuration. |
| `ios` | `IOSConfig` | ✅ | — | iOS/macOS-specific storage configuration. |
| `video` | `Video` | ✅ | — | Output video configuration (name, resolution, bitrate). |
| `isMinBitrateCheckEnabled` | `bool` | | `true` | Skip compression when source bitrate is below 2 Mbps. |
| `disableAudio` | `bool?` | | `false` | Strip audio track from the output. |

### `Video`

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `videoName` | `String` | ✅ | — | Output filename (`.mp4` appended automatically if missing). |
| `keepOriginalResolution` | `bool?` | | `false` | Keep source dimensions instead of downscaling. |
| `videoBitrateInMbps` | `int?` | | `null` | Custom bitrate in Mbps (overrides quality preset). |
| `videoHeight` | `int?` | | `null` | Custom height in pixels. Must be set with `videoWidth`. |
| `videoWidth` | `int?` | | `null` | Custom width in pixels. Must be set with `videoHeight`. |

### `AndroidConfig`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `isSharedStorage` | `bool` | `true` | `true` = shared storage (MediaStore); `false` = app-specific directory. |
| `saveAt` | `SaveAt` | `Movies` | Target collection: `Pictures`, `Movies`, or `Downloads`. Ignored when `isSharedStorage` is `false`. |

### `IOSConfig`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `saveInGallery` | `bool` | `true` | Save the compressed video to the photo library. |

### `Result` types

| Type | Properties | Description |
|------|-----------|-------------|
| `OnSuccess` | `destinationPath: String` | Compression completed; contains the output file path. |
| `OnFailure` | `message: String` | Compression failed; contains the error message. |
| `OnCancelled` | `isCancelled: bool` | Compression was cancelled via `cancelCompression()`. |

### Other members

| Member | Signature | Description |
|--------|-----------|-------------|
| `onProgressUpdated` | `Stream<double>` | Emits compression progress from `0` to `100`. |
| `cancelCompression()` | `Future<Map<String, dynamic>?>` | Cancels any running compression. |

---

## ⚙️ Configuration

### iOS / macOS

**SPM vs CocoaPods** — The plugin includes both `Package.swift` and `.podspec`. Flutter ≥ 3.24 uses SPM by default; older versions fall back to CocoaPods automatically.

**Info.plist** — If you use `IOSConfig(saveInGallery: true)`, add the photo library usage description:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to save compressed videos.</string>
```

### Android

**Permissions** — Add the appropriate permissions to `AndroidManifest.xml` based on your target API level:

```xml
<!-- API < 29 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28"
    tools:ignore="ScopedStorage" />

<!-- API 29–32 -->
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- API ≥ 33 -->
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

**ProGuard** — No special ProGuard or R8 rules are required.

---

## 🤝 Contributing

Contributions are welcome! To get started:

1. Fork the repository: [github.com/Farid023/light_compressor_v2](https://github.com/Farid023/light_compressor_v2)
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes and **run the example app** to verify:
   ```bash
   cd example
   flutter run
   ```
4. Open a Pull Request with a clear description of the change.

Please report bugs via [GitHub Issues](https://github.com/Farid023/light_compressor_v2/issues). Include the device name, OS version, and whether the issue reproduces in the example app.

---

## 📄 License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

MIT © 2020 [AbedElaziz Shehadeh](https://github.com/AbedElazizShe), 2025 [Farid Gurbanov](https://github.com/Farid023)
