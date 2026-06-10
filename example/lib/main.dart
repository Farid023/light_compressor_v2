import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'utils/file_utils.dart';
import 'video_player.dart';

/// Represents the current state of the video compression process.
enum _CompressionState {
  /// No video selected or compression has been cancelled.
  idle,

  /// Compression is in progress.
  compressing,

  /// Compression completed successfully.
  done,

  /// Compression failed with an error.
  failed,
}

void main() => runApp(const MyApp());

/// The root widget of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF344772),
          ),
        ),
        home: const HomeScreen(),
      );
}

/// The main screen of the app where the user picks and compresses a video.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LightCompressor _lightCompressor = LightCompressor();

  /// Current state of the compression process.
  _CompressionState _state = _CompressionState.idle;

  /// File path of the original selected video.
  String? _filePath;

  /// File path of the successfully compressed video.
  String? _compressedPath;

  /// Error message shown when compression fails.
  String? _failureMessage;

  /// Elapsed time of the compression process in seconds.
  int _duration = 0;

  /// Original video duration.
  double _videoDuration = 0;

  /// Compression ratio.
  double _ratio = 0;

  /// Original video size in bytes, as reported by the compressor.
  int _originalSize = 0;

  /// Compressed video size in bytes, as reported by the compressor.
  int _compressedSize = 0;

  /// Metadata of the selected video (Phase 2 demo).
  MediaInfo? _mediaInfo;

  /// Path to a generated preview thumbnail (Phase 2 demo).
  String? _thumbnailPath;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Compressor Sample'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear Cache',
              onPressed: () async {
                await _lightCompressor.clearCache();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared!')),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_filePath != null) _buildFileInfo(),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _pickVideo,
          foregroundColor: Colors.white,
          label: const Text('Pick Video'),
          icon: const Icon(Icons.video_library),
          backgroundColor: const Color(0xFF377FC2),
        ),
      );

  /// Returns the main body content based on [_state].
  Widget _buildBody(BuildContext context) => switch (_state) {
        _CompressionState.idle => const Center(
            child: Text(
              'Pick a video to compress',
              style: TextStyle(fontSize: 16, color: Colors.black38),
            ),
          ),
        _CompressionState.compressing => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildProgress(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _lightCompressor.cancelCompression,
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  label: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        _CompressionState.done => Center(child: _buildPlayButton(context)),
        _CompressionState.failed => Center(
            child: Text(
              _failureMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
      };

  /// Displays the original file size and, after compression,
  /// the compressed file size and elapsed duration.
  Widget _buildFileInfo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_thumbnailPath != null || _mediaInfo != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_thumbnailPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_thumbnailPath!),
                      width: 120,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (_mediaInfo != null) ...[
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetadata(_mediaInfo!)),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Original: ${formatBytes(_originalSize > 0 ? _originalSize : File(_filePath!).lengthSync(), 2)}',
            style: const TextStyle(fontSize: 16),
          ),
          if (_state == _CompressionState.done && _compressedPath != null) ...[
            const SizedBox(height: 4),
            Text(
              'Compressed: ${formatBytes(_compressedSize, 2)}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Compression Time: $_duration seconds',
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
            const SizedBox(height: 4),
            Text(
              'Video Duration: ${formatDuration(Duration(milliseconds: (_videoDuration * 1000).round()))}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Reduction: ${_ratio.toStringAsFixed(2)}%',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ],
      );

  /// Renders the [MediaInfo] fields returned by `getMediaInfo`.
  Widget _buildMetadata(MediaInfo info) {
    final resolution = (info.displayWidth != null && info.displayHeight != null)
        ? '${info.displayWidth}x${info.displayHeight}'
        : 'unknown';
    final duration =
        info.duration != null ? formatDuration(info.duration!) : '?';
    final mbps = info.bitrate != null
        ? (info.bitrate! / 1000000).toStringAsFixed(2)
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resolution: $resolution', style: const TextStyle(fontSize: 13)),
        Text('Duration: $duration', style: const TextStyle(fontSize: 13)),
        Text('Bitrate: $mbps Mbps', style: const TextStyle(fontSize: 13)),
        if (info.rotation != null)
          Text('Rotation: ${info.rotation}°',
              style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  /// Displays a circular progress indicator with percentage while
  /// compression is running.
  Widget _buildProgress() => StreamBuilder<double>(
        stream: _lightCompressor.onProgressUpdated,
        builder: (context, snapshot) {
          final progress = snapshot.data ?? 0;
          return Column(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.black12,
                      valueColor: const AlwaysStoppedAnimation(Colors.black),
                    ),
                    Center(
                      child: Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Compressing...',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          );
        },
      );

  /// Displays a button to navigate to the [VideoPlayerScreen]
  /// with the compressed video.
  Widget _buildPlayButton(BuildContext context) => OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(path: _compressedPath!),
          ),
        ),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Play Video'),
      );

  /// Opens the file picker, starts video compression, and updates
  /// the UI based on the result.
  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final file = result?.files.first;
    if (file == null) return;

    setState(() {
      _filePath = file.path;
      _state = _CompressionState.compressing;
      _failureMessage = null;
      _compressedPath = null;
      _mediaInfo = null;
      _thumbnailPath = null;
    });

    // Phase 2 demo: read metadata and grab a thumbnail from the middle.
    try {
      final info = await _lightCompressor.getMediaInfo(_filePath!);
      final midpointMs = (info.duration ?? Duration.zero).inMilliseconds ~/ 2;
      final thumbnail = await _lightCompressor.getVideoThumbnail(
        _filePath!,
        positionInMs: midpointMs,
        quality: 80,
      );
      if (mounted) {
        setState(() {
          _mediaInfo = info;
          _thumbnailPath = thumbnail;
        });
      }
    } catch (e) {
      debugPrint('Metadata/thumbnail failed: $e');
    }

    final videoName = 'MyVideo-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final stopwatch = Stopwatch()..start();

    Result? response;
    String? exceptionMessage;

    try {
      response = await _lightCompressor.compressVideo(
        path: _filePath!,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(videoName: videoName),
        android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
        ios: IOSConfig(saveInGallery: false),
      );
    } on PermissionDeniedException catch (e) {
      exceptionMessage = 'Permission Denied: ${e.message}';
    } on UnsupportedVideoException catch (e) {
      exceptionMessage = 'Unsupported Video: ${e.message}';
    } on VideoNotFoundException catch (e) {
      exceptionMessage = 'Video Not Found: ${e.message}';
    } catch (e) {
      exceptionMessage = 'An unexpected error occurred: $e';
    }

    stopwatch.stop();
    _duration = Duration(milliseconds: stopwatch.elapsedMilliseconds).inSeconds;

    setState(() {
      if (exceptionMessage != null) {
        _failureMessage = exceptionMessage;
        _state = _CompressionState.failed;
      } else if (response is OnSuccess) {
        _compressedPath = response.destinationPath;
        _videoDuration = response.duration;
        _ratio = response.ratio;
        _originalSize = response.originalSize;
        _compressedSize = response.compressedSize;
        _state = _CompressionState.done;
      } else if (response is OnFailure) {
        _failureMessage = response.message;
        _state = _CompressionState.failed;
      } else if (response is OnCancelled) {
        debugPrint('Cancelled: ${response.isCancelled}');
        _state = _CompressionState.idle;
        _filePath = null;
      }
    });
  }
}
