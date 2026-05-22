import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A screen that plays a compressed video from the given [path].
///
/// Provides basic playback controls: play/pause, seek forward/backward by 10
/// seconds, and a progress slider with timestamps.
class VideoPlayerScreen extends StatefulWidget {
  /// Creates a [VideoPlayerScreen] with the given video [path].
  const VideoPlayerScreen({super.key, required this.path});

  /// The file system path of the video to play.
  final String path;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller.play();
      });

    // Rebuild the widget on every controller update (e.g. position change).
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Seeks the video position by the given [offset] relative to the current
  /// position. Accepts negative values for rewinding.
  void _seekBy(Duration offset) {
    final newPosition = _controller.value.position + offset;
    _controller.seekTo(newPosition);
  }

  /// Formats a [Duration] as `mm:ss`.
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: _controller.value.isInitialized
              ? Column(
                  children: [
                    // Video occupies all available vertical space.
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                    // Playback controls pinned to the bottom.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Column(
                        children: [
                          // Progress slider.
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.black,
                              inactiveTrackColor: Colors.black12,
                              thumbColor: Colors.black,
                              overlayColor: Colors.black12,
                              trackHeight: 1,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: _controller.value.position.inSeconds
                                  .toDouble(),
                              min: 0,
                              max: _controller.value.duration.inSeconds
                                  .toDouble(),
                              onChanged: (value) => _controller
                                  .seekTo(Duration(seconds: value.toInt())),
                            ),
                          ),
                          // Current position / total duration timestamps.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(
                                    _controller.value.position)),
                                Text(_formatDuration(
                                    _controller.value.duration)),
                              ],
                            ),
                          ),
                          // Rewind, play/pause, and forward buttons.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.replay_10,
                                    color: Colors.black),
                                onPressed: () =>
                                    _seekBy(const Duration(seconds: -10)),
                              ),
                              IconButton(
                                iconSize: 48,
                                icon: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_circle
                                      : Icons.play_circle,
                                  color: Colors.black,
                                ),
                                onPressed: () => setState(() {
                                  _controller.value.isPlaying
                                      ? _controller.pause()
                                      : _controller.play();
                                }),
                              ),
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.forward_10,
                                    color: Colors.black),
                                onPressed: () =>
                                    _seekBy(const Duration(seconds: 10)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
}
