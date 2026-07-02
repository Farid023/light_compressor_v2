import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'utils/file_utils.dart';
import 'video_player.dart';

/// Stage of the single-video flow.
enum _Stage { idle, ready, compressing, done, failed }

/// Demonstrates [LightCompressor.getMediaInfo], [LightCompressor.getVideoThumbnail]
/// and [LightCompressor.compressVideo] for a single video.
class SingleCompressView extends StatefulWidget {
  /// Creates a [SingleCompressView].
  const SingleCompressView({super.key, required this.compressor});

  /// The shared compressor instance.
  final LightCompressor compressor;

  @override
  State<SingleCompressView> createState() => _SingleCompressViewState();
}

class _SingleCompressViewState extends State<SingleCompressView>
    with AutomaticKeepAliveClientMixin {
  _Stage _stage = _Stage.idle;
  String? _sourcePath;
  MediaInfo? _info;
  String? _thumbnailPath;
  CompressionEstimate? _estimate;
  List<String> _thumbnails = const <String>[];
  bool _thumbsLoading = false;
  OnSuccess? _result;
  String? _error;
  bool _runInBackground = false;
  bool _twoPass = false;
  VideoFormat _videoFormat = VideoFormat.h264;
  int _rotation = 0;
  double _brightness = 0; // -1..1, 0 = none
  double _contrast = 1; // 0..2, 1 = none
  double _saturation = 1; // 0..2, 1 = none
  final TextEditingController _targetSizeController = TextEditingController();
  final TextEditingController _fpsController = TextEditingController();
  final TextEditingController _audioKbpsController = TextEditingController();
  final TextEditingController _trimStartController = TextEditingController();
  final TextEditingController _trimEndController = TextEditingController();

  @override
  void dispose() {
    _targetSizeController.dispose();
    _fpsController.dispose();
    _audioKbpsController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.first.path;
    if (path == null) return;

    _targetSizeController.clear();
    _fpsController.clear();
    _audioKbpsController.clear();
    _trimStartController.clear();
    _trimEndController.clear();
    setState(() {
      _stage = _Stage.ready;
      _sourcePath = path;
      _info = null;
      _thumbnailPath = null;
      _estimate = null;
      _thumbnails = const <String>[];
      _result = null;
      _error = null;
      _rotation = 0;
      _brightness = 0;
      _contrast = 1;
      _saturation = 1;
    });

    // Read metadata, grab a preview frame from the middle of the video, and
    // predict the compressed size (getCompressionEstimate runs no transcode).
    try {
      final info = await widget.compressor.getMediaInfo(path);
      final midpointMs = (info.duration ?? Duration.zero).inMilliseconds ~/ 2;
      final thumbnail = await widget.compressor.getVideoThumbnail(
        path,
        positionInMs: midpointMs,
        quality: 80,
      );
      final estimate = await widget.compressor.getCompressionEstimate(
        path,
        videoQuality: VideoQuality.medium,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _thumbnailPath = thumbnail;
        _estimate = estimate;
      });
    } catch (e) {
      debugPrint('Metadata/thumbnail/estimate failed: $e');
    }
  }

  /// Generates a strip of evenly-spaced thumbnails via [getVideoThumbnails]
  /// (one native round-trip).
  Future<void> _loadThumbnails() async {
    final path = _sourcePath;
    if (path == null) return;
    setState(() => _thumbsLoading = true);

    final totalMs = (_info?.duration ?? Duration.zero).inMilliseconds;
    final requests = <ThumbnailRequest>[
      for (int i = 0; i < 5; i++)
        ThumbnailRequest(
          positionInMs: totalMs > 0 ? (totalMs * i) ~/ 5 : 0,
          quality: 60,
        ),
    ];
    try {
      final paths = await widget.compressor.getVideoThumbnails(path, requests);
      if (!mounted) return;
      setState(() {
        _thumbnails = paths;
        _thumbsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _thumbsLoading = false);
      debugPrint('Thumbnails failed: $e');
    }
  }

  Future<void> _compress() async {
    final path = _sourcePath;
    if (path == null) return;

    setState(() {
      _stage = _Stage.compressing;
      _error = null;
    });

    final videoName = 'LC-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final parsedTarget = int.tryParse(_targetSizeController.text.trim());
    final targetSizeMb =
        (parsedTarget != null && parsedTarget > 0) ? parsedTarget : null;
    final parsedFps = int.tryParse(_fpsController.text.trim());
    final videoFps = (parsedFps != null && parsedFps > 0) ? parsedFps : null;
    final parsedAudioKbps = int.tryParse(_audioKbpsController.text.trim());
    final audio = (parsedAudioKbps != null && parsedAudioKbps > 0)
        ? AudioConfig(bitrate: parsedAudioKbps * 1000)
        : null;
    final parsedTrimStart = int.tryParse(_trimStartController.text.trim());
    final parsedTrimEnd = int.tryParse(_trimEndController.text.trim());
    final trimStartMs = (parsedTrimStart != null && parsedTrimStart > 0)
        ? parsedTrimStart
        : null;
    final trimEndMs =
        (parsedTrimEnd != null && parsedTrimEnd > (trimStartMs ?? 0))
            ? parsedTrimEnd
            : null;
    final hasColor = _brightness != 0 || _contrast != 1 || _saturation != 1;
    final edit =
        (trimStartMs != null || trimEndMs != null || _rotation != 0 || hasColor)
            ? VideoEdit(
                trimStartMs: trimStartMs,
                trimEndMs: trimEndMs,
                rotationDegrees: _rotation != 0 ? _rotation : null,
                brightness: _brightness != 0 ? _brightness : null,
                contrast: _contrast != 1 ? _contrast : null,
                saturation: _saturation != 1 ? _saturation : null,
              )
            : null;
    try {
      final result = await widget.compressor.compressVideo(
        path: path,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        video: Video(
          videoName: videoName,
          targetSizeMb: targetSizeMb,
          videoFps: videoFps,
          twoPass: _twoPass,
        ),
        android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
        ios: IOSConfig(saveInGallery: false),
        videoFormat: _videoFormat,
        background: _runInBackground ? const BackgroundConfig() : null,
        audio: audio,
        edit: edit,
      );
      if (!mounted) return;
      setState(() {
        if (result is OnSuccess) {
          _result = result;
          _stage = _Stage.done;
        } else if (result is OnFailure) {
          _error = result.message;
          _stage = _Stage.failed;
        } else {
          _stage = _Stage.ready;
        }
      });
    } on LightCompressorException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _stage = _Stage.failed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _stage = _Stage.failed;
        });
      }
    }
  }

  Widget _colorSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: _stage == _Stage.compressing ? null : onChanged,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      );

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _stage == _Stage.compressing ? null : _pickVideo,
          icon: const Icon(Icons.video_call_outlined),
          label: const Text('Pick a video'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Run in background'),
          subtitle: const Text(
            'Keep compressing when the app is backgrounded or the screen is off',
          ),
          value: _runInBackground,
          onChanged: _stage == _Stage.compressing
              ? null
              : (value) => setState(() => _runInBackground = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use H.265 (HEVC)'),
          subtitle: const Text(
            'Smaller files where supported; falls back to H.264 otherwise',
          ),
          value: _videoFormat == VideoFormat.h265,
          onChanged: _stage == _Stage.compressing
              ? null
              : (value) => setState(
                    () => _videoFormat =
                        value ? VideoFormat.h265 : VideoFormat.h264,
                  ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextField(
            controller: _targetSizeController,
            enabled: _stage != _Stage.compressing,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max output size (MB) — optional',
              helperText:
                  'Compress to about this size; blank uses medium quality',
              isDense: true,
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Two-pass (precise size)'),
          subtitle: const Text(
            'Re-encode once more if the first pass overshoots the max size '
            '(needs a max size; about doubles the time)',
          ),
          value: _twoPass,
          onChanged: _stage == _Stage.compressing
              ? null
              : (value) => setState(() => _twoPass = value),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _fpsController,
            enabled: _stage != _Stage.compressing,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Output FPS — optional',
              helperText:
                  'Downsample to about this rate; blank keeps the source',
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _audioKbpsController,
            enabled: _stage != _Stage.compressing,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Audio bitrate (kbps) — optional',
              helperText:
                  'Re-encode AAC at this bitrate; blank copies the source',
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _trimStartController,
                  enabled: _stage != _Stage.compressing,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Trim start (ms)',
                    helperText: 'Optional',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _trimEndController,
                  enabled: _stage != _Stage.compressing,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Trim end (ms)',
                    helperText: 'Optional',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const Text('Rotate'),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('0°')),
                    ButtonSegment(value: 90, label: Text('90°')),
                    ButtonSegment(value: 180, label: Text('180°')),
                    ButtonSegment(value: 270, label: Text('270°')),
                  ],
                  selected: {_rotation},
                  onSelectionChanged: _stage == _Stage.compressing
                      ? null
                      : (Set<int> s) => setState(() => _rotation = s.first),
                ),
              ),
            ],
          ),
        ),
        _colorSlider(
          'Brightness',
          _brightness,
          -1,
          1,
          (double v) => setState(() => _brightness = v),
        ),
        _colorSlider(
          'Contrast',
          _contrast,
          0,
          2,
          (double v) => setState(() => _contrast = v),
        ),
        _colorSlider(
          'Saturation',
          _saturation,
          0,
          2,
          (double v) => setState(() => _saturation = v),
        ),
        if (_info != null || _thumbnailPath != null) ...[
          const SizedBox(height: 16),
          _PreviewCard(info: _info, thumbnailPath: _thumbnailPath),
        ],
        if (_estimate != null) ...[
          const SizedBox(height: 12),
          _EstimateCard(estimate: _estimate!),
        ],
        if (_sourcePath != null) ...[
          const SizedBox(height: 12),
          _ThumbnailStrip(
            thumbnails: _thumbnails,
            loading: _thumbsLoading,
            onGenerate: _stage == _Stage.compressing ? null : _loadThumbnails,
          ),
        ],
        const SizedBox(height: 16),
        ..._buildStage(context),
      ],
    );
  }

  List<Widget> _buildStage(BuildContext context) {
    switch (_stage) {
      case _Stage.idle:
        return const [
          _Hint('Pick a video to inspect and compress it.'),
        ];
      case _Stage.ready:
        return [
          FilledButton.tonalIcon(
            onPressed: _compress,
            icon: const Icon(Icons.compress),
            label: const Text('Compress'),
          ),
        ];
      case _Stage.compressing:
        return [
          _buildProgress(),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: widget.compressor.cancelCompression,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ),
        ];
      case _Stage.done:
        return [_ResultCard(result: _result!)];
      case _Stage.failed:
        return [
          _Hint(_error ?? 'Compression failed', isError: true),
        ];
    }
  }

  Widget _buildProgress() => StreamBuilder<CompressionProgress>(
        stream: widget.compressor.onProgressDetail,
        builder: (context, snapshot) {
          final CompressionProgress? detail = snapshot.data;
          final double progress = detail?.percent ?? 0;
          return Center(
            child: Column(
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress > 0 ? progress / 100 : null,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.black12,
                      ),
                      Center(
                        child: Text(
                          '${progress.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _progressLabel(detail),
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
          );
        },
      );

  /// Builds the under-the-dial label: estimated time remaining and live output
  /// size when the platform reports them, otherwise a plain "Compressing…".
  String _progressLabel(CompressionProgress? detail) {
    if (detail == null) return 'Compressing…';
    final List<String> parts = <String>[];
    if (detail.etaMs != null) {
      parts.add('~${(detail.etaMs! / 1000).ceil()}s left');
    }
    if ((detail.bytesProcessed ?? 0) > 0) {
      parts.add(formatBytes(detail.bytesProcessed!, 1));
    }
    return parts.isEmpty ? 'Compressing…' : parts.join(' • ');
  }
}

/// Shows the picked video's thumbnail and metadata.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({this.info, this.thumbnailPath});

  final MediaInfo? info;
  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbnailPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(thumbnailPath!),
                    width: 130,
                    height: 86,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(width: 12),
              if (info != null) Expanded(child: _Metadata(info: info!)),
            ],
          ),
        ),
      );
}

/// Renders [MediaInfo] fields as a small key/value list.
class _Metadata extends StatelessWidget {
  const _Metadata({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final resolution = (info.displayWidth != null && info.displayHeight != null)
        ? '${info.displayWidth} × ${info.displayHeight}'
        : '—';
    final duration =
        info.duration != null ? formatDuration(info.duration!) : '—';
    final bitrate = info.bitrate != null
        ? '${(info.bitrate! / 1000000).toStringAsFixed(2)} Mbps'
        : '—';
    final size = info.fileSize != null ? formatBytes(info.fileSize!, 2) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Resolution', resolution),
        _row('Duration', duration),
        _row('Bitrate', bitrate),
        _row('Size', size),
        if (info.rotation != null && info.rotation != 0)
          _row('Rotation', '${info.rotation}°'),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Shows compression statistics and a play button.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final OnSuccess result;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  const Text(
                    'Compressed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Original: ${formatBytes(result.originalSize, 2)}'),
              Text('Compressed: ${formatBytes(result.compressedSize, 2)}'),
              Text('Reduction: ${result.ratio.toStringAsFixed(1)}%'),
              Text(
                'Codec: ${result.usedFormat == VideoFormat.h265 ? 'H.265 (HEVC)' : 'H.264 (AVC)'}',
              ),
              Text(
                'Duration: ${formatDuration(Duration(milliseconds: (result.duration * 1000).round()))}',
              ),
              if (result.passesUsed > 1)
                Text('Encoded in ${result.passesUsed} passes'),
              if (!result.targetSizeMet)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Target size could not be met — used the resolution floor.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        VideoPlayerScreen(path: result.destinationPath),
                  ),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ],
          ),
        ),
      );
}

/// Shows the pre-flight [CompressionEstimate] (predicted, no transcode).
class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.estimate});

  final CompressionEstimate estimate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.calculate_outlined),
                  SizedBox(width: 8),
                  Text(
                    'Estimated output',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Predicted size: ${formatBytes(estimate.estimatedSizeBytes, 2)}',
              ),
              Text(
                'Resolution: ${estimate.outputWidth} × ${estimate.outputHeight}',
              ),
              Text(
                'Bitrate: ${(estimate.targetBitrate / 1000000).toStringAsFixed(2)} Mbps',
              ),
              Text(
                  'Reduction: ~${estimate.estimatedRatio.toStringAsFixed(0)}%'),
              const SizedBox(height: 4),
              const Text(
                'Approximate — computed without transcoding (medium quality).',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
}

/// A "Generate" button plus the resulting horizontal filmstrip, demonstrating
/// [LightCompressor.getVideoThumbnails] (several frames in one call).
class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({
    required this.thumbnails,
    required this.loading,
    required this.onGenerate,
  });

  final List<String> thumbnails;
  final bool loading;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thumbnails',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : onGenerate,
                    icon: const Icon(Icons.burst_mode_outlined, size: 18),
                    label: const Text('Generate'),
                  ),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (thumbnails.isEmpty)
                const Text(
                  'Extract several frames in one call (getVideoThumbnails).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                )
              else
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: thumbnails.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (BuildContext context, int index) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(thumbnails[index]),
                        width: 108,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// A centered hint or error message.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: isError ? Colors.red : Colors.black45,
          ),
        ),
      );
}
