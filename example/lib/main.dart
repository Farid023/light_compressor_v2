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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Compressor Sample'),
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
          Text(
            'Original: ${formatBytes(File(_filePath!).lengthSync(), 2)}',
            style: const TextStyle(fontSize: 16),
          ),
          if (_state == _CompressionState.done && _compressedPath != null) ...[
            const SizedBox(height: 4),
            Text(
              'Compressed: ${formatBytes(File(_compressedPath!).lengthSync(), 2)}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Duration: $_duration seconds',
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
          ],
        ],
      );

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
    });

    final videoName = 'MyVideo-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final stopwatch = Stopwatch()..start();

    final response = await _lightCompressor.compressVideo(
      path: _filePath!,
      videoQuality: VideoQuality.medium,
      isMinBitrateCheckEnabled: false,
      video: Video(videoName: videoName),
      android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
      ios: IOSConfig(saveInGallery: false),
    );

    stopwatch.stop();
    _duration = Duration(milliseconds: stopwatch.elapsedMilliseconds).inSeconds;

    setState(() {
      if (response is OnSuccess) {
        _compressedPath = response.destinationPath;
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
