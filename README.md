# light_compressor_v2

[![Pub Version](https://img.shields.io/pub/v/light_compressor_v2.svg)](https://pub.dev/packages/light_compressor_v2)
[![CI](https://github.com/Farid023/light_compressor_v2/actions/workflows/ci.yml/badge.svg)](https://github.com/Farid023/light_compressor_v2/actions/workflows/ci.yml)
[![Pub Platforms](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS-blue)](https://pub.dev/packages/light_compressor_v2)
[![Pub Likes](https://img.shields.io/pub/likes/light_compressor_v2)](https://pub.dev/packages/light_compressor_v2)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful, easy-to-use video compression plugin for Flutter — for **single videos** and **batches**.

It generates a compressed MP4 with reduced width, height, and bitrate while keeping good visual quality, and also exposes media metadata, thumbnail extraction, and cache cleanup.

## 🛠️ How it Works

Extreme high bitrates are reduced while maintaining good video quality, resulting in a much smaller file size.

* **Quality presets:** choose between 5 compression qualities — `very_low`, `low`, `medium`, `high`, `very_high`. The plugin automatically computes the target bitrate for the output.
* **Minimum bitrate guard:** with `isMinBitrateCheckEnabled` (default **2 Mbps** threshold), the plugin skips compression for low-bitrate or already-compressed videos, avoiding cumulative quality degradation.

---

## ✨ Features

- **Single & batch compression** — compress one video, or many in a single call with per-item results and progress.
- **Five quality presets** — the plugin calculates the optimal bitrate automatically.
- **H.264 & H.265 (HEVC)** — pick the output codec via `videoFormat`; H.265 produces smaller files and automatically falls back to H.264 when the device can't encode it. `OnSuccess.usedFormat` reports the codec actually used.
- **Custom resolution & bitrate** — override width, height, and bitrate when presets aren't enough.
- **Target file size** — compress toward a maximum output size in megabytes via `targetSizeMb`; the compressor solves for the bitrate and reports whether the target was reachable (`OnSuccess.targetSizeMet`). Add `twoPass: true` to re-encode once more when the first pass overshoots, landing closer to the target (`OnSuccess.passesUsed`).
- **Frame-rate control** — downsample the output frame rate via `videoFps` (downsample-only — never duplicates frames).
- **Audio re-encoding** — re-encode the audio track as AAC with a custom bitrate (and sample rate on iOS/macOS) via `AudioConfig`.
- **Lightweight editing** — trim (`trimStartMs` / `trimEndMs`), rotate by a quarter-turn (`rotationDegrees`), and adjust colour (`brightness` / `contrast` / `saturation`) while compressing, via `VideoEdit` — still 100% native (no ffmpeg).
- **Structured success result** — `OnSuccess` carries `originalSize`, `compressedSize`, `duration`, and `ratio` (percentage reduction).
- **Media info** — read width, height, duration, bitrate, rotation, frame rate, and MIME type via `getMediaInfo`.
- **Thumbnail extraction** — grab a JPEG frame at any timecode via `getVideoThumbnail`, or several at once via `getVideoThumbnails`.
- **Compression estimate** — predict the output size, bitrate and resolution *before* compressing via `getCompressionEstimate` (no transcode).
- **Running-state query** — check whether a compression is in progress via `isCompressing`.
- **Progress streams** — real-time percentage for single (`onProgressUpdated`) and per-item + overall for batch (`onBatchUpdate`).
- **Cancellation** — cancel any in-progress compression with a single call.
- **Background execution** — keep compressing while the app is backgrounded or the screen is off via `BackgroundConfig` (Android foreground service; macOS App Nap suppression; not supported on iOS).
- **Typed exceptions** — `PermissionDeniedException`, `UnsupportedVideoException`, `VideoNotFoundException`, and more — react programmatically instead of parsing strings.
- **Minimum bitrate guard** — optionally skip compression for already-low-bitrate videos.
- **Disable audio** — generate silent videos when audio isn't needed.
- **Cache cleanup** — remove temporary files with `clearCache`.
- **iOS / macOS:** Swift Package Manager (SPM) support alongside CocoaPods.
- **Android:** fully Kotlin native layer, Gradle KTS build script.

---

## 📸 Demo

<p align="left">
  <img src="https://raw.githubusercontent.com/Farid023/light_compressor_v2/master/pictures/demo.gif" alt="Demo GIF" width="300" />
</p>

---

## 📱 Platform Support

| iOS | Android | macOS |
|:---:|:-------:|:-----:|
| ✅  |  ✅   |  ✅   |

**Minimum versions:** iOS 11 · Android API 24 · macOS 10.15

---

## 📦 Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  light_compressor_v2: ^1.3.0
```

Then run:

```bash
flutter pub get
```

### iOS / macOS — Podfile

No extra Podfile configuration is required. The plugin ships with both a `.podspec` (CocoaPods) and a `Package.swift` (SPM); Flutter picks the appropriate integration automatically.

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
```

### Compress a single video

```dart
final Result result = await compressor.compressVideo(
  path: '/path/to/source.mp4',
  videoQuality: VideoQuality.medium,
  isMinBitrateCheckEnabled: false,
  video: Video(videoName: 'compressed.mp4'),
  android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: true),
);

if (result is OnSuccess) {
  print('Saved to ${result.destinationPath}');
  print('Reduced by ${result.ratio.toStringAsFixed(1)}% '
      '(${result.originalSize} → ${result.compressedSize} bytes)');
} else if (result is OnFailure) {
  print('Failed: ${result.message}');
} else if (result is OnCancelled) {
  print('Cancelled');
}
```

### Compress a batch of videos

A single failing video does not stop the others — its slot in the returned
list becomes an `OnFailure`. Results are returned in the same order as `paths`.

```dart
final List<Result> results = await compressor.compressVideos(
  paths: ['/path/a.mp4', '/path/b.mp4'],
  videoNames: ['a_compressed.mp4', 'b_compressed.mp4'],
  videoQuality: VideoQuality.medium,
  android: AndroidConfig(saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: false),
);

for (final (int i, Result r) in results.indexed) {
  if (r is OnSuccess) print('Video $i → ${r.destinationPath}');
}
```

By default Android compresses up to two videos at once and Apple starts them
all. Pass `maxConcurrent` to cap that — e.g. `maxConcurrent: 1` for strictly
sequential compression, which lowers peak memory and device heat:

```dart
await compressor.compressVideos(
  paths: paths,
  videoNames: names,
  videoQuality: VideoQuality.medium,
  maxConcurrent: 1, // one video at a time
  android: AndroidConfig(saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: false),
);
```

### Run in the background

Pass a `BackgroundConfig` to keep a compression running while the app is
backgrounded or the screen turns off. Works for both `compressVideo` and
`compressVideos`:

```dart
final result = await compressor.compressVideo(
  path: '/path/to/source.mp4',
  videoQuality: VideoQuality.medium,
  video: Video(videoName: 'compressed.mp4'),
  android: AndroidConfig(saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: true),
  background: const BackgroundConfig(
    notificationTitle: 'Compressing video',
  ),
);
```

Platform behaviour differs significantly:

- **Android** — runs under a foreground service. The ongoing notification shows
  live progress (bar + %), elapsed time, the current file (single) or
  a `done / total` count (batch) and a Cancel action. The title comes from
  `BackgroundConfig`. The plugin declares the service + receiver and requests
  `POST_NOTIFICATIONS` (Android 13+) automatically — no host-app manifest
  changes are needed.
- **macOS** — suppresses App Nap so the process keeps full CPU in the
  background. The notification fields are ignored.
- **iOS** — **not supported.** iOS suspends backgrounded apps within seconds
  and offers no sanctioned way to keep video transcoding running, so passing a
  `BackgroundConfig` has no effect; the compression pauses and resumes when the
  app returns to the foreground.

### Choose the output codec (H.265 / HEVC)

By default the output is H.264 (AVC). Pass `videoFormat: VideoFormat.h265` to
request HEVC, which yields smaller files at comparable quality. It applies to
both `compressVideo` and `compressVideos`:

```dart
final result = await compressor.compressVideo(
  path: '/path/to/source.mp4',
  videoQuality: VideoQuality.medium,
  videoFormat: VideoFormat.h265,
  video: Video(videoName: 'compressed.mp4'),
  android: AndroidConfig(saveAt: SaveAt.Movies),
  ios: IOSConfig(saveInGallery: true),
);

if (result is OnSuccess) {
  // Tells you whether H.265 was honoured or fell back to H.264.
  print('Encoded with ${result.usedFormat.name}');
}
```

`VideoFormat.h265` is used only when the device has a hardware HEVC encoder
(Android excludes software-only encoders; iOS/macOS check the platform's
advertised HEVC support). When it isn't available the compressor **silently
falls back to H.264** rather than failing — always read `OnSuccess.usedFormat`
to know what you got.

### Target a file size, frame rate, or audio bitrate

Set `targetSizeMb` and/or `videoFps` on `Video` (the same fields are flat
parameters on `compressVideos`), and pass an `AudioConfig` as `audio:`:

```dart
final Result result = await compressor.compressVideo(
  path: sourcePath,
  videoQuality: VideoQuality.medium,
  android: AndroidConfig(),
  ios: IOSConfig(),
  video: Video(
    videoName: 'compressed.mp4',
    targetSizeMb: 10, // aim for ≤ 10 MB (mutually exclusive with videoBitrateInMbps)
    twoPass: true,    // re-encode once more if the first pass overshoots 10 MB
    videoFps: 24,     // downsample 30 → 24 fps (downsample-only)
  ),
  audio: const AudioConfig(bitrate: 96000), // re-encode audio to ~96 kbps AAC
);

if (result is OnSuccess && !result.targetSizeMet) {
  // The target was below the quality floor for this resolution; the output is
  // larger than requested. (A future release may auto-drop resolution to fit.)
}
```

`targetSizeMb` is approximate (single-pass is typically within ~10–15%). Add
`twoPass: true` to land closer: the compressor re-encodes a second time only if
the first pass overshot the target (an undershoot is kept as-is), roughly
doubling the time on overshooting clips. `OnSuccess.passesUsed` reports how many
passes ran. `audioSampleRate` is honored on iOS/macOS; **Android re-encodes audio
at the source sample rate** (no resampler), so only the audio `bitrate` applies
there.

### Trim, rotate, and adjust colour

Pass an optional `VideoEdit` as `edit:` to trim to a time range, rotate by a
quarter-turn, and/or adjust colour while compressing (both entry points accept it):

```dart
final Result result = await compressor.compressVideo(
  path: sourcePath,
  videoQuality: VideoQuality.medium,
  android: AndroidConfig(),
  ios: IOSConfig(),
  video: Video(videoName: 'edited.mp4'),
  edit: const VideoEdit(
    trimStartMs: 1000,    // keep from 1s…
    trimEndMs: 5000,      // …to 5s (output duration ≈ 4s, rebased to 0)
    rotationDegrees: 90,  // quarter-turn on top of the source orientation
    saturation: 0.0,      // 0..2 (1 = no change); 0 = grayscale
    brightness: 0.1,      // -1..1 (0 = no change)
  ),
);
```

Trimming is frame-accurate (the clip is re-encoded) and the reported `duration`
reflects the trimmed length. Rotation is a cheap container-metadata turn that
players honour — a 90°/270° turn swaps the displayed dimensions; the stored
frames are not re-rendered. Colour adjustment (`brightness` / `contrast` /
`saturation`, CIColorControls semantics) is baked into the output pixels —
Android via a GL shader, Apple via a `CIColorControls` video composition — so
exact pixel parity across platforms is not guaranteed. Either trim bound is
optional, and an empty `VideoEdit` (or `null`) leaves the video untouched.

### Listen to progress

Single video — a `Stream<double>` from `0` to `100`:

```dart
StreamBuilder<double>(
  stream: compressor.onProgressUpdated,
  builder: (context, snapshot) {
    final percent = snapshot.data ?? 0;
    return Text('${percent.toStringAsFixed(0)}%');
  },
);
```

Batch — per-video and overall progress, plus a completion event per item:

```dart
compressor.onBatchUpdate.listen((BatchEvent event) {
  switch (event) {
    case BatchProgress(:final index, :final overallPercent):
      print('Video $index — overall ${overallPercent.toStringAsFixed(0)}%');
    case BatchItemCompleted(:final index, :final result):
      print('Video $index finished: $result');
  }
});
```

### Cancel compression

```dart
await compressor.cancelCompression();
```

The cancelled job is reported as an `OnCancelled` result on the pending
`compressVideo` / `compressVideos` call.

### Read media info

```dart
final MediaInfo info = await compressor.getMediaInfo('/path/to/video.mp4');
print('${info.displayWidth} × ${info.displayHeight}');
print('Duration: ${info.duration}, bitrate: ${info.bitrate} bps');
```

### Extract a thumbnail

```dart
final String thumbnailPath = await compressor.getVideoThumbnail(
  '/path/to/video.mp4',
  positionInMs: 2000, // grab the frame at 2s
  quality: 80,
);
```

### Estimate the result before compressing

Predict the output **without** running a transcode — handy for showing the user
the expected size up front:

```dart
final CompressionEstimate estimate = await compressor.getCompressionEstimate(
  '/path/to/video.mp4',
  videoQuality: VideoQuality.medium,
);
print('~${estimate.estimatedSizeBytes} bytes, '
    '${estimate.outputWidth}×${estimate.outputHeight}, '
    '~${estimate.estimatedRatio.toStringAsFixed(0)}% smaller');
```

The figures are approximate (single-pass), computed from the same bitrate and
resize math the compressor uses.

### Extract several thumbnails at once

Grab multiple frames in a single native call — more efficient than calling
`getVideoThumbnail` repeatedly. Paths come back in the same order as the requests:

```dart
final List<String> thumbnails = await compressor.getVideoThumbnails(
  '/path/to/video.mp4',
  const <ThumbnailRequest>[
    ThumbnailRequest(positionInMs: 0),
    ThumbnailRequest(positionInMs: 1000, quality: 80),
    ThumbnailRequest(positionInMs: 2000),
  ],
);
```

### Check whether a compression is running

```dart
if (await compressor.isCompressing()) {
  // e.g. disable the "Compress" button
}
```

### Clear cached files

```dart
await compressor.clearCache();
```

### Handle errors

Recognized native failures are thrown as typed exceptions; unclassified
failures are returned as `OnFailure` instead.

```dart
try {
  final info = await compressor.getMediaInfo('/path/to/video.mp4');
  // use info...
} on VideoNotFoundException catch (e) {
  print(e.message);
} on PermissionDeniedException catch (e) {
  print(e.message);
} on LightCompressorException catch (e) {
  print(e.message); // base type — catches any of the above
}
```

---

## 📖 API Reference

### `compressVideo()` → `Future<Result>`

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `path` | `String` | ✅ | — | Absolute path to the source video file. |
| `videoQuality` | `VideoQuality` | ✅ | — | Quality preset: `very_low`, `low`, `medium`, `high`, `very_high`. |
| `android` | `AndroidConfig` | ✅ | — | Android-specific storage configuration. |
| `ios` | `IOSConfig` | ✅ | — | iOS/macOS-specific storage configuration. |
| `video` | `Video` | ✅ | — | Output video configuration (name, resolution, bitrate). |
| `isMinBitrateCheckEnabled` | `bool` | | `true` | Skip compression when source bitrate is below 2 Mbps. |
| `disableAudio` | `bool?` | | `false` | Strip the audio track from the output. |
| `videoFormat` | `VideoFormat` | | `h264` | Output codec: `h264` or `h265` (HEVC). Falls back to H.264 when HEVC isn't supported. See [`VideoFormat`](#videoformat). |
| `background` | `BackgroundConfig?` | | `null` | Keep running while the app is backgrounded. See [`BackgroundConfig`](#backgroundconfig). |
| `audio` | `AudioConfig?` | | `null` | Re-encode the audio track as AAC. See [`AudioConfig`](#audioconfig). |
| `edit` | `VideoEdit?` | | `null` | Trim and/or rotate while compressing. See [`VideoEdit`](#videoedit). |

### `compressVideos()` → `Future<List<Result>>`

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `paths` | `List<String>` | ✅ | — | Source video paths. |
| `videoNames` | `List<String>` | ✅ | — | Output file names; must match `paths` length. |
| `videoQuality` | `VideoQuality` | ✅ | — | Quality preset, shared by every video. |
| `android` | `AndroidConfig` | ✅ | — | Android-specific storage configuration. |
| `ios` | `IOSConfig` | ✅ | — | iOS/macOS-specific storage configuration. |
| `keepOriginalResolution` | `bool` | | `false` | Keep source dimensions instead of downscaling. |
| `videoWidth` / `videoHeight` | `int?` | | `null` | Custom output size (set both together). |
| `videoBitrateInMbps` | `int?` | | `null` | Custom bitrate in Mbps (overrides the preset). |
| `targetSizeMb` | `int?` | | `null` | Compress toward this maximum output size in MB. Mutually exclusive with `videoBitrateInMbps`. See [`Video.targetSizeMb`](#video). |
| `videoFps` | `int?` | | `null` | Downsample the output frame rate (downsample-only). |
| `disableAudio` | `bool` | | `false` | Strip the audio track from every output. |
| `isMinBitrateCheckEnabled` | `bool` | | `true` | Skip compression when source bitrate is below 2 Mbps. |
| `videoFormat` | `VideoFormat` | | `h264` | Output codec for every video: `h264` or `h265` (HEVC). See [`VideoFormat`](#videoformat). |
| `background` | `BackgroundConfig?` | | `null` | Keep the whole batch running while backgrounded. See [`BackgroundConfig`](#backgroundconfig). |
| `audio` | `AudioConfig?` | | `null` | Re-encode the audio track as AAC. See [`AudioConfig`](#audioconfig). |
| `edit` | `VideoEdit?` | | `null` | Trim and/or rotate every video. See [`VideoEdit`](#videoedit). |
| `maxConcurrent` | `int?` | | `null` | Cap how many videos transcode at once (`>= 1`). Unset keeps the platform default (Android 2; Apple starts all). No effect on a single video. |

### `getCompressionEstimate()` → `Future<CompressionEstimate>`

Predicts the output **without transcoding**. The parameters mirror the ones on `compressVideo` that affect the output size.

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `path` | `String` | ✅ | — | Absolute path to the source video. |
| `videoQuality` | `VideoQuality` | ✅ | — | Quality preset to estimate for. |
| `videoFormat` | `VideoFormat` | | `h264` | Output codec. Does **not** change the estimated size — the compressor targets the same bitrate for H.264/H.265. |
| `keepOriginalResolution` | `bool` | | `false` | Keep source dimensions instead of downscaling. |
| `videoWidth` / `videoHeight` | `int?` | | `null` | Custom output size (set both together). |
| `videoBitrateInMbps` | `int?` | | `null` | Custom bitrate in Mbps (overrides the preset). |
| `disableAudio` | `bool` | | `false` | Exclude the audio track from the estimate. |

### `Video`

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `videoName` | `String` | ✅ | — | Output filename (`.mp4` appended automatically if missing). |
| `keepOriginalResolution` | `bool?` | | `false` | Keep source dimensions instead of downscaling. |
| `videoBitrateInMbps` | `int?` | | `null` | Custom bitrate in Mbps (overrides the quality preset). |
| `videoHeight` | `int?` | | `null` | Custom height in pixels. Must be set with `videoWidth`. |
| `videoWidth` | `int?` | | `null` | Custom width in pixels. Must be set with `videoHeight`. |
| `targetSizeMb` | `int?` | | `null` | Target maximum output size in MB. The compressor solves for the video bitrate (clamped to a 2 Mbps floor and the source bitrate). Mutually exclusive with `videoBitrateInMbps`; must be `> 0`. Whether it was achievable is reported by [`OnSuccess.targetSizeMet`](#result-types). Single-pass and approximate. |
| `videoFps` | `int?` | | `null` | Target output frame rate. Downsample-only — a value at or above the source rate leaves it unchanged (frames are never duplicated). Must be `> 0`. |

### `VideoEdit`

Lightweight native edits applied while compressing. Passed as `edit:` to `compressVideo` / `compressVideos`; every field is optional and an empty `VideoEdit` (or `null`) leaves the video untouched.

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `trimStartMs` | `int?` | | `null` | Start of the kept range, in milliseconds (`>= 0`). The output timeline is rebased to `0`. |
| `trimEndMs` | `int?` | | `null` | End of the kept range, in milliseconds. Must be greater than `trimStartMs` (or `0` when no start is given). |
| `rotationDegrees` | `int?` | | `null` | Quarter-turn applied on top of the source orientation: `0`, `90`, `180`, or `270`. Cheap container-metadata rotation — a 90°/270° turn swaps the displayed dimensions. |
| `brightness` | `double?` | | `null` | Brightness in `-1.0..1.0` (`0` = no change), additive. Clamped on the wire. |
| `contrast` | `double?` | | `null` | Contrast in `0.0..2.0` (`1` = no change). Clamped on the wire. |
| `saturation` | `double?` | | `null` | Saturation in `0.0..2.0` (`1` = no change, `0` = grayscale). Clamped on the wire. |

### `AudioConfig`

Re-encodes the audio track as AAC. Passed as `audio:` to `compressVideo` / `compressVideos`; when omitted the source audio is copied through untouched, and it is ignored entirely when `disableAudio` is `true`.

| Parameter | Type | Required | Default | Description |
|-----------|------|:--------:|---------|-------------|
| `bitrate` | `int?` | | `null` | Target AAC bitrate in **bits per second** (e.g. `128000`). Must be `> 0`. |
| `sampleRate` | `int?` | | `null` | Target sample rate in Hz. **iOS/macOS only** — on Android the audio is re-encoded at the source sample rate (no resampler). Must be `> 0`. |

### `AndroidConfig`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `isSharedStorage` | `bool` | `true` | `true` = shared storage (MediaStore); `false` = app-specific directory. |
| `saveAt` | `SaveAt` | `Movies` | Target collection: `Pictures`, `Movies`, or `Downloads`. Ignored when `isSharedStorage` is `false`. |

### `IOSConfig`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `saveInGallery` | `bool` | `true` | Save the compressed video to the photo library. |

### `BackgroundConfig`

Opt into background execution. `notificationTitle` is the Android foreground-service notification title; iOS and macOS ignore it.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `notificationTitle` | `String` | `'Compressing video'` | Title of the Android foreground-service notification. |

### `VideoFormat`

Output codec, written into an MP4/QuickTime container.

| Value | Description |
|-------|-------------|
| `h264` | H.264 / AVC. The widely compatible default. |
| `h265` | H.265 / HEVC. Smaller files at comparable quality; **requires a hardware HEVC encoder** and automatically falls back to `h264` otherwise. Check [`OnSuccess.usedFormat`](#result-types) for the codec actually used. |

### `Result` types

| Type | Properties | Description |
|------|-----------|-------------|
| `OnSuccess` | `destinationPath: String`, `originalSize: int`, `compressedSize: int`, `duration: double`, `ratio: double`, `usedFormat: VideoFormat`, `targetSizeMet: bool` | Output path, byte sizes, duration (seconds), percentage size reduction, the codec actually used, and whether a requested `targetSizeMb` was achievable (`true` when no target was set). |
| `OnFailure` | `message: String`, `failureType: CompressionFailureType` | A failure: a human-readable `message` plus a [`CompressionFailureType`](#compressionfailuretype) category for reacting in code without parsing text. |
| `OnCancelled` | `isCancelled: bool` | Compression was cancelled via `cancelCompression()`. |

### `CompressionFailureType`

The category carried by `OnFailure.failureType`, for reacting to *why* a video failed (including per-item in a batch) without parsing `message`. Defaults to `unknown`.

| Value | Description |
|-------|-------------|
| `permission` | A required permission (e.g. storage) was denied. |
| `unsupported` | The source could not be processed — e.g. no decodable video track or an unsupported format. |
| `notFound` | The source file could not be found or opened. |
| `unknown` | Any other or unclassified failure. |

### `BatchEvent` (from `onBatchUpdate`)

| Type | Properties | Description |
|------|-----------|-------------|
| `BatchProgress` | `index: int`, `percent: double`, `overallPercent: double` | Progress of one video and the batch average. |
| `BatchItemCompleted` | `index: int`, `result: Result` | A video finished; `result` is `OnSuccess` / `OnFailure` / `OnCancelled`. |

### `MediaInfo` (from `getMediaInfo`)

All fields are nullable — a container/device may not expose every value.

| Property | Type | Description |
|----------|------|-------------|
| `width` / `height` | `int?` | Encoded dimensions in pixels (before rotation). |
| `displayWidth` / `displayHeight` | `int?` | Dimensions as displayed (rotation-aware). |
| `duration` | `Duration?` | Total duration. |
| `fileSize` | `int?` | File size in bytes. |
| `bitrate` | `int?` | Bitrate in bits per second. |
| `rotation` | `int?` | Rotation in degrees (`0`, `90`, `180`, `270`). |
| `frameRate` | `double?` | Frames per second. |
| `mimeType` | `String?` | Container MIME type. |

### `CompressionEstimate` (from `getCompressionEstimate`)

A pre-flight prediction. Approximate — no transcode is run.

| Property | Type | Description |
|----------|------|-------------|
| `originalSizeBytes` | `int` | Source file size in bytes. |
| `estimatedSizeBytes` | `int` | Predicted output size in bytes. |
| `targetBitrate` | `int` | Target video bitrate (bps) used for the estimate. |
| `outputWidth` / `outputHeight` | `int` | Predicted output dimensions in pixels. |
| `estimatedRatio` | `double` | Predicted size reduction (`0`–`100`). |

### `ThumbnailRequest` (for `getVideoThumbnails`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `positionInMs` | `int` | — | Frame timecode in milliseconds (clamped to the video duration). |
| `quality` | `int` | `50` | JPEG quality, `0` (smallest) to `100` (best). |

### Exceptions

All extend `LightCompressorException` (catch the base type to handle any):

| Exception | Thrown when |
|-----------|-------------|
| `PermissionDeniedException` | Missing read/write permission. |
| `UnsupportedVideoException` | Unsupported format/codec or missing track. |
| `VideoNotFoundException` | The source video was not found. |
| `MediaInfoException` | Metadata could not be read (`getMediaInfo`). |
| `ThumbnailException` | A frame could not be extracted (`getVideoThumbnail` / `getVideoThumbnails`). |
| `EstimateException` | A compression estimate could not be computed (`getCompressionEstimate`). |

### Other members

| Member | Signature | Description |
|--------|-----------|-------------|
| `onProgressUpdated` | `Stream<double>` | Single-video progress, `0`–`100`. |
| `onBatchUpdate` | `Stream<BatchEvent>` | Per-video + overall progress and completion events during `compressVideos`. |
| `getMediaInfo()` | `Future<MediaInfo>` | Read video metadata. |
| `getVideoThumbnail()` | `Future<String>` | Extract a JPEG frame; returns its file path. |
| `getVideoThumbnails()` | `Future<List<String>>` | Extract several frames in one call; returns paths in request order. |
| `getCompressionEstimate()` | `Future<CompressionEstimate>` | Predict the output size/bitrate/resolution without transcoding. |
| `isCompressing()` | `Future<bool>` | Whether a compression (single or batch) is currently running. |
| `clearCache()` | `Future<void>` | Delete temporary `.mp4` files created during compression. |
| `cancelCompression()` | `Future<void>` | Cancel any running compression. |

---

## ⚙️ Configuration

### iOS / macOS

**SPM vs CocoaPods** — the plugin includes both `Package.swift` and `.podspec`. Flutter ≥ 3.24 uses SPM by default; older versions fall back to CocoaPods automatically.

**Info.plist** — if you use `IOSConfig(saveInGallery: true)`, add the photo library usage description:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to save compressed videos.</string>
```

### Android

**Permissions** — add the appropriate permissions to `AndroidManifest.xml` based on your target API level:

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

**Background execution** — when you pass a `BackgroundConfig`, no manifest changes are required on your side. The plugin already declares the foreground service and the `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` and `POST_NOTIFICATIONS` permissions, which merge into your app automatically; the `POST_NOTIFICATIONS` runtime prompt (Android 13+) is requested for you.

**ProGuard** — no special ProGuard or R8 rules are required.

---

## 🧪 Testing

The plugin ships with two layers of tests:

- **Unit tests** (`test/`) cover the Dart surface: argument forwarding over the method channel, result/event parsing, batch ordering and failure typing, progress-stream coercion, and the typed-exception mapping. They need no device:

  ```bash
  flutter test
  ```

- **Integration tests** (`example/integration_test/`) exercise the **real native pipeline** (Android `MediaCodec` / `MediaMuxer`, Apple `AVFoundation`) on a device, emulator, or simulator — metadata, thumbnails, compression options, progress streams, cancellation, batch resilience, and H.264 / H.265 codec selection with automatic fallback:

  ```bash
  cd example
  flutter test integration_test/plugin_integration_test.dart -d <deviceId>
  flutter test integration_test/hevc_compression_test.dart   -d <deviceId>
  ```

  A short sample clip is bundled at `example/integration_test/assets/sample.mp4`; the tests skip cleanly when it is absent.

`flutter analyze`, formatting, and the unit tests run in [CI](https://github.com/Farid023/light_compressor_v2/actions/workflows/ci.yml) on every push and pull request. Integration tests are run manually, since they need a device.

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

Released under the MIT License — see [LICENSE](LICENSE) for the full text.

MIT © 2025 [Farid Gurbanov](https://github.com/Farid023)
