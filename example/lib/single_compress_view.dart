import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'theme.dart';
import 'utils/file_utils.dart';
import 'video_player.dart';
import 'widgets.dart';

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

  // Basic options.
  VideoQuality _quality = VideoQuality.medium;
  VideoFormat _videoFormat = VideoFormat.h264;

  // Advanced options.
  bool _runInBackground = false;
  bool _twoPass = false;
  int _rotation = 0;
  double _brightness = 0; // -1..1, 0 = none
  double _contrast = 1; // 0..2, 1 = none
  double _saturation = 1; // 0..2, 1 = none
  final TextEditingController _targetSizeController = TextEditingController();
  final TextEditingController _fpsController = TextEditingController();
  final TextEditingController _audioKbpsController = TextEditingController();
  final TextEditingController _trimStartController = TextEditingController();
  final TextEditingController _trimEndController = TextEditingController();

  bool get _isBusy => _stage == _Stage.compressing;

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
    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.video);
    final String? path = result?.files.first.path;
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
      final MediaInfo info = await widget.compressor.getMediaInfo(path);
      final int midpointMs =
          (info.duration ?? Duration.zero).inMilliseconds ~/ 2;
      final String thumbnail = await widget.compressor.getVideoThumbnail(
        path,
        positionInMs: midpointMs,
        quality: 80,
      );
      final CompressionEstimate estimate =
          await widget.compressor.getCompressionEstimate(
        path,
        videoQuality: _quality,
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

  /// Re-runs the pre-flight estimate when the quality changes, so the
  /// "estimated output" card stays in sync with the selected preset.
  Future<void> _refreshEstimate() async {
    final String? path = _sourcePath;
    if (path == null) return;
    try {
      final CompressionEstimate estimate =
          await widget.compressor.getCompressionEstimate(
        path,
        videoQuality: _quality,
        videoFormat: _videoFormat,
      );
      if (!mounted) return;
      setState(() => _estimate = estimate);
    } catch (e) {
      debugPrint('Estimate refresh failed: $e');
    }
  }

  /// Generates a strip of evenly-spaced thumbnails via [getVideoThumbnails]
  /// (one native round-trip).
  Future<void> _loadThumbnails() async {
    final String? path = _sourcePath;
    if (path == null) return;
    setState(() => _thumbsLoading = true);

    final int totalMs = (_info?.duration ?? Duration.zero).inMilliseconds;
    final List<ThumbnailRequest> requests = <ThumbnailRequest>[
      for (int i = 0; i < 5; i++)
        ThumbnailRequest(
          positionInMs: totalMs > 0 ? (totalMs * i) ~/ 5 : 0,
          quality: 60,
        ),
    ];
    try {
      final List<String> paths =
          await widget.compressor.getVideoThumbnails(path, requests);
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
    final String? path = _sourcePath;
    if (path == null) return;

    setState(() {
      _stage = _Stage.compressing;
      _error = null;
    });

    final String videoName = 'LC-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final int? parsedTarget = int.tryParse(_targetSizeController.text.trim());
    final int? targetSizeMb =
        (parsedTarget != null && parsedTarget > 0) ? parsedTarget : null;
    final int? parsedFps = int.tryParse(_fpsController.text.trim());
    final int? videoFps =
        (parsedFps != null && parsedFps > 0) ? parsedFps : null;
    final int? parsedAudioKbps = int.tryParse(_audioKbpsController.text.trim());
    final AudioConfig? audio = (parsedAudioKbps != null && parsedAudioKbps > 0)
        ? AudioConfig(bitrate: parsedAudioKbps * 1000)
        : null;
    final int? parsedTrimStart = int.tryParse(_trimStartController.text.trim());
    final int? parsedTrimEnd = int.tryParse(_trimEndController.text.trim());
    final int? trimStartMs = (parsedTrimStart != null && parsedTrimStart > 0)
        ? parsedTrimStart
        : null;
    final int? trimEndMs =
        (parsedTrimEnd != null && parsedTrimEnd > (trimStartMs ?? 0))
            ? parsedTrimEnd
            : null;
    final bool hasColor =
        _brightness != 0 || _contrast != 1 || _saturation != 1;
    final VideoEdit? edit =
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
      final Result result = await widget.compressor.compressVideo(
        path: path,
        videoQuality: _quality,
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_stage == _Stage.idle) {
      return EmptyState(
        icon: Icons.movie_creation_outlined,
        title: 'No video selected',
        message: 'Pick a video to inspect its metadata and compress it '
            'with native codecs.',
        buttonLabel: 'Pick a video',
        buttonIcon: Icons.video_call_outlined,
        onPressed: _pickVideo,
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            children: <Widget>[
              _PreviewCard(info: _info, thumbnailPath: _thumbnailPath),
              if (_estimate != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _EstimateCard(estimate: _estimate!),
              ],
              const SizedBox(height: AppSpacing.md),
              _ThumbnailStrip(
                thumbnails: _thumbnails,
                loading: _thumbsLoading,
                onGenerate: _isBusy ? null : _loadThumbnails,
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      QualitySelector(
                        value: _quality,
                        onChanged: _isBusy
                            ? null
                            : (VideoQuality v) {
                                setState(() => _quality = v);
                                unawaited(_refreshEstimate());
                              },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      CodecSelector(
                        value: _videoFormat,
                        onChanged: _isBusy
                            ? null
                            : (VideoFormat v) {
                                setState(() => _videoFormat = v);
                                unawaited(_refreshEstimate());
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _AdvancedOptions(
                enabled: !_isBusy,
                runInBackground: _runInBackground,
                onRunInBackgroundChanged: (bool v) =>
                    setState(() => _runInBackground = v),
                twoPass: _twoPass,
                onTwoPassChanged: (bool v) => setState(() => _twoPass = v),
                targetSizeController: _targetSizeController,
                fpsController: _fpsController,
                audioKbpsController: _audioKbpsController,
                trimStartController: _trimStartController,
                trimEndController: _trimEndController,
                rotation: _rotation,
                onRotationChanged: (int v) => setState(() => _rotation = v),
                brightness: _brightness,
                onBrightnessChanged: (double v) =>
                    setState(() => _brightness = v),
                contrast: _contrast,
                onContrastChanged: (double v) => setState(() => _contrast = v),
                saturation: _saturation,
                onSaturationChanged: (double v) =>
                    setState(() => _saturation = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              ..._buildStage(context),
            ],
          ),
        ),
        _BottomActionBar(
          stage: _stage,
          onPick: _pickVideo,
          onCompress: _compress,
          onCancel: widget.compressor.cancelCompression,
          progressStream: widget.compressor.onProgressDetail,
        ),
      ],
    );
  }

  List<Widget> _buildStage(BuildContext context) {
    switch (_stage) {
      case _Stage.idle:
      case _Stage.ready:
        return const <Widget>[];
      case _Stage.compressing:
        // Progress is shown in the pinned bottom bar (always visible), so the
        // scrollable body shows nothing extra while compressing.
        return const <Widget>[];
      case _Stage.done:
        return <Widget>[_ResultCard(result: _result!)];
      case _Stage.failed:
        return <Widget>[_ErrorCard(message: _error ?? 'Compression failed')];
    }
  }
}

/// The bottom-pinned action area: "Compress" while ready, or a compact live
/// progress row (bar + label + small Cancel) while compressing — always
/// visible, so progress never requires scrolling.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.stage,
    required this.onPick,
    required this.onCompress,
    required this.onCancel,
    required this.progressStream,
  });

  final _Stage stage;
  final VoidCallback onPick;
  final VoidCallback onCompress;
  final VoidCallback onCancel;
  final Stream<CompressionProgress> progressStream;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: stage == _Stage.compressing
            ? _CompressingBar(stream: progressStream, onCancel: onCancel)
            : Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    onPressed: onPick,
                    icon: const Icon(Icons.video_call_outlined),
                    tooltip: 'Pick another video',
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCompress,
                      icon: const Icon(Icons.compress),
                      label: const Text('Compress'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A compact live-progress row for the bottom bar: percent + ETA/bytes over a
/// slim linear bar, with a small Cancel button.
class _CompressingBar extends StatelessWidget {
  const _CompressingBar({required this.stream, required this.onCancel});

  final Stream<CompressionProgress> stream;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return StreamBuilder<CompressionProgress>(
      stream: stream,
      builder: (
        BuildContext context,
        AsyncSnapshot<CompressionProgress> snapshot,
      ) {
        final CompressionProgress? detail = snapshot.data;
        final double progress = detail?.percent ?? 0;
        final String extra = _progressExtra(detail);
        return Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    extra.isEmpty
                        ? '${progress.toStringAsFixed(0)}%'
                        : '${progress.toStringAsFixed(0)}%  •  $extra',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress / 100 : null,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton.outlined(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
            ),
          ],
        );
      },
    );
  }
}

/// Formats the live ETA + output size for the progress label (empty when the
/// platform hasn't reported either yet).
String _progressExtra(CompressionProgress? detail) {
  if (detail == null) return '';
  final List<String> parts = <String>[];
  if (detail.etaMs != null) {
    parts.add('~${(detail.etaMs! / 1000).ceil()}s left');
  }
  if ((detail.bytesProcessed ?? 0) > 0) {
    parts.add(formatBytes(detail.bytesProcessed!, 1));
  }
  return parts.join(' • ');
}

/// The collapsible "Advanced options" section: target size + two-pass, output
/// fps, audio bitrate, trim range, rotation and colour adjustments, plus the
/// background-execution switch.
class _AdvancedOptions extends StatelessWidget {
  const _AdvancedOptions({
    required this.enabled,
    required this.runInBackground,
    required this.onRunInBackgroundChanged,
    required this.twoPass,
    required this.onTwoPassChanged,
    required this.targetSizeController,
    required this.fpsController,
    required this.audioKbpsController,
    required this.trimStartController,
    required this.trimEndController,
    required this.rotation,
    required this.onRotationChanged,
    required this.brightness,
    required this.onBrightnessChanged,
    required this.contrast,
    required this.onContrastChanged,
    required this.saturation,
    required this.onSaturationChanged,
  });

  final bool enabled;
  final bool runInBackground;
  final ValueChanged<bool> onRunInBackgroundChanged;
  final bool twoPass;
  final ValueChanged<bool> onTwoPassChanged;
  final TextEditingController targetSizeController;
  final TextEditingController fpsController;
  final TextEditingController audioKbpsController;
  final TextEditingController trimStartController;
  final TextEditingController trimEndController;
  final int rotation;
  final ValueChanged<int> onRotationChanged;
  final double brightness;
  final ValueChanged<double> onBrightnessChanged;
  final double contrast;
  final ValueChanged<double> onContrastChanged;
  final double saturation;
  final ValueChanged<double> onSaturationChanged;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            title: const Text('Advanced options'),
            subtitle: const Text(
              'Target size, FPS, audio, trim, rotate, colour, background',
            ),
            children: <Widget>[
              NumberField(
                controller: targetSizeController,
                enabled: enabled,
                label: 'Max output size',
                suffixText: 'MB',
                helperText: 'Optional — blank uses the selected quality',
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Two-pass (precise size)'),
                subtitle: const Text(
                  'Re-encode once more if pass 1 overshoots the max size '
                  '(needs a max size; about doubles the time)',
                ),
                value: twoPass,
                onChanged: enabled ? onTwoPassChanged : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              NumberField(
                controller: fpsController,
                enabled: enabled,
                label: 'Output frame rate',
                suffixText: 'fps',
                helperText: 'Optional — downsample only',
              ),
              const SizedBox(height: AppSpacing.md),
              NumberField(
                controller: audioKbpsController,
                enabled: enabled,
                label: 'Audio bitrate',
                suffixText: 'kbps',
                helperText: 'Optional — AAC re-encode',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NumberField(
                      controller: trimStartController,
                      enabled: enabled,
                      label: 'Trim start (ms)',
                      helperText: 'Optional',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: NumberField(
                      controller: trimEndController,
                      enabled: enabled,
                      label: 'Trim end (ms)',
                      helperText: 'Optional',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Rotate'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('0°')),
                  ButtonSegment<int>(value: 90, label: Text('90°')),
                  ButtonSegment<int>(value: 180, label: Text('180°')),
                  ButtonSegment<int>(value: 270, label: Text('270°')),
                ],
                selected: <int>{rotation},
                onSelectionChanged:
                    enabled ? (Set<int> s) => onRotationChanged(s.first) : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Colour adjust'),
              const SizedBox(height: AppSpacing.sm),
              LabeledSlider(
                label: 'Brightness',
                value: brightness,
                min: -1,
                max: 1,
                onChanged: enabled ? onBrightnessChanged : null,
              ),
              LabeledSlider(
                label: 'Contrast',
                value: contrast,
                min: 0,
                max: 2,
                onChanged: enabled ? onContrastChanged : null,
              ),
              LabeledSlider(
                label: 'Saturation',
                value: saturation,
                min: 0,
                max: 2,
                onChanged: enabled ? onSaturationChanged : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Run in background'),
                subtitle: const Text(
                  'Keep compressing when the app is backgrounded or the '
                  'screen is off',
                ),
                value: runInBackground,
                onChanged: enabled ? onRunInBackgroundChanged : null,
              ),
            ],
          ),
        ),
      );
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumbnail(path: thumbnailPath, width: 130, height: 86),
              const SizedBox(width: AppSpacing.md),
              if (info != null) Expanded(child: _Metadata(info: info!)),
            ],
          ),
        ),
      );
}

/// A thumbnail image with a themed placeholder, error, and loading builder.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.path,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final String? path;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? currentPath = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: currentPath == null
          ? _placeholder(scheme)
          : Image.file(
              File(currentPath),
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) =>
                  _placeholder(scheme),
            ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.movie_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      );
}

/// Renders [MediaInfo] fields as a small key/value list.
class _Metadata extends StatelessWidget {
  const _Metadata({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final String resolution =
        (info.displayWidth != null && info.displayHeight != null)
            ? '${info.displayWidth} × ${info.displayHeight}'
            : '—';
    final String duration =
        info.duration != null ? formatDuration(info.duration!) : '—';
    final String bitrate = info.bitrate != null
        ? '${(info.bitrate! / 1000000).toStringAsFixed(2)} Mbps'
        : '—';
    final String size =
        info.fileSize != null ? formatBytes(info.fileSize!, 2) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StatRow('Resolution', resolution),
        StatRow('Duration', duration),
        StatRow('Bitrate', bitrate),
        StatRow('Size', size),
        if (info.rotation != null && info.rotation != 0)
          StatRow('Rotation', '${info.rotation}°'),
      ],
    );
  }
}

/// Shows compression statistics and a play button.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final OnSuccess result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.check_circle, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Compressed',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                ReductionBadge(ratio: result.ratio),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child:
                      StatRow('Original', formatBytes(result.originalSize, 2)),
                ),
                Icon(Icons.arrow_right_alt, color: scheme.onSurfaceVariant),
                Expanded(
                  child: StatRow(
                    'Compressed',
                    formatBytes(result.compressedSize, 2),
                  ),
                ),
              ],
            ),
            StatRow(
              'Codec',
              result.usedFormat == VideoFormat.h265
                  ? 'H.265 (HEVC)'
                  : 'H.264 (AVC)',
            ),
            StatRow(
              'Duration',
              formatDuration(
                Duration(milliseconds: (result.duration * 1000).round()),
              ),
            ),
            if (result.passesUsed > 1)
              StatRow('Passes', '${result.passesUsed}'),
            if (!result.targetSizeMet)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: scheme.error),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Target size could not be met — used the bitrate floor.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
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
}

/// Shows an error message for a failed compression.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the pre-flight [CompressionEstimate] (predicted, no transcode).
class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.estimate});

  final CompressionEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.calculate_outlined, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Estimated output',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            StatRow(
              'Predicted size',
              formatBytes(estimate.estimatedSizeBytes, 2),
            ),
            StatRow(
              'Resolution',
              '${estimate.outputWidth} × ${estimate.outputHeight}',
            ),
            StatRow(
              'Bitrate',
              '${(estimate.targetBitrate / 1000000).toStringAsFixed(2)} Mbps',
            ),
            StatRow(
              'Reduction',
              '~${estimate.estimatedRatio.toStringAsFixed(0)}%',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Approximate — computed without transcoding.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('Thumbnails',
                    style: Theme.of(context).textTheme.titleSmall),
                TextButton.icon(
                  onPressed: loading ? null : onGenerate,
                  icon: const Icon(Icons.burst_mode_outlined, size: 18),
                  label: const Text('Generate'),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (thumbnails.isEmpty)
              Text(
                'Extract several frames in one call (getVideoThumbnails).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: thumbnails.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (BuildContext context, int index) => _Thumbnail(
                    path: thumbnails[index],
                    width: 108,
                    height: 72,
                    borderRadius: 6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
