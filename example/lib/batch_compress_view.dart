import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'theme.dart';
import 'utils/file_utils.dart';
import 'video_player.dart';
import 'widgets.dart';

/// One row in the batch list.
class _Item {
  _Item(this.name);

  final String name;
  double percent = 0;
  Result? result;
  String? thumbnailPath;
}

/// Demonstrates [LightCompressor.compressVideos] with per-video progress and
/// completion driven by [LightCompressor.onBatchUpdate].
class BatchCompressView extends StatefulWidget {
  /// Creates a [BatchCompressView].
  const BatchCompressView({super.key, required this.compressor});

  /// The shared compressor instance.
  final LightCompressor compressor;

  @override
  State<BatchCompressView> createState() => _BatchCompressViewState();
}

class _BatchCompressViewState extends State<BatchCompressView>
    with AutomaticKeepAliveClientMixin {
  List<_Item> _items = <_Item>[];
  List<String> _paths = <String>[];
  double _overall = 0;
  bool _running = false;
  bool _runInBackground = false;
  VideoFormat _videoFormat = VideoFormat.h264;
  int? _maxConcurrent;
  StreamSubscription<BatchEvent>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Picks the source videos and shows them in the list. It does NOT start
  /// compressing — the user configures the options first, then presses
  /// "Compress" ([_startCompression]).
  Future<void> _pickVideos() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    final List<PlatformFile>? files = result?.files;
    if (files == null || files.isEmpty) return;

    await _subscription?.cancel();
    setState(() {
      _paths = <String>[for (final PlatformFile f in files) f.path!];
      _items = <_Item>[for (final PlatformFile f in files) _Item(f.name)];
      _overall = 0;
      _running = false;
    });

    // Load preview thumbnails in the background; they fill in as they arrive.
    for (int i = 0; i < _paths.length; i++) {
      unawaited(_loadThumbnail(i, _paths[i]));
    }
  }

  /// Compresses the already-picked videos with the current options.
  Future<void> _startCompression() async {
    if (_paths.isEmpty || _running) return;

    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final List<String> names = <String>[
      for (int i = 0; i < _paths.length; i++) 'Batch-$stamp-$i.mp4',
    ];

    setState(() {
      // Reset any previous run's per-item state so a re-run starts clean.
      for (final _Item item in _items) {
        item
          ..percent = 0
          ..result = null;
      }
      _overall = 0;
      _running = true;
    });

    await _subscription?.cancel();
    _subscription = widget.compressor.onBatchUpdate.listen((BatchEvent event) {
      if (!mounted) return;
      setState(() {
        if (event is BatchProgress) {
          if (event.index < _items.length) {
            _items[event.index].percent = event.percent;
          }
          _overall = event.overallPercent;
        } else if (event is BatchItemCompleted) {
          if (event.index < _items.length) {
            _items[event.index]
              ..result = event.result
              ..percent = 100;
          }
        }
      });
    });

    try {
      await widget.compressor.compressVideos(
        paths: _paths,
        videoNames: names,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
        ios: IOSConfig(saveInGallery: false),
        videoFormat: _videoFormat,
        maxConcurrent: _maxConcurrent,
        background: _runInBackground ? const BackgroundConfig() : null,
      );
    } catch (e) {
      debugPrint('Batch error: $e');
    } finally {
      await _subscription?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _overall = 100;
        });
      }
    }
  }

  Future<void> _loadThumbnail(int index, String path) async {
    try {
      final String thumb = await widget.compressor.getVideoThumbnail(
        path,
        positionInMs: 0,
        quality: 60,
      );
      if (mounted && index < _items.length) {
        setState(() => _items[index].thumbnailPath = thumb);
      }
    } catch (_) {
      // Best-effort preview; ignore failures.
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.video_library_outlined,
        title: 'No videos selected',
        message: 'Pick multiple videos to compress them together as a '
            'batch, with per-video and overall progress.',
        buttonLabel: 'Pick videos',
        buttonIcon: Icons.video_library_outlined,
        onPressed: _pickVideos,
      );
    }

    final int completed = _items.where((_Item i) => i.result != null).length;
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
              _BatchOptions(
                enabled: !_running,
                videoFormat: _videoFormat,
                onVideoFormatChanged: (VideoFormat v) =>
                    setState(() => _videoFormat = v),
                maxConcurrent: _maxConcurrent,
                onMaxConcurrentChanged: (int? v) =>
                    setState(() => _maxConcurrent = v),
                runInBackground: _runInBackground,
                onRunInBackgroundChanged: (bool v) =>
                    setState(() => _runInBackground = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_running || _overall > 0) ...<Widget>[
                _OverallProgress(
                  overall: _overall,
                  completed: completed,
                  total: _items.length,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              SectionHeader('Videos (${_items.length})'),
              const SizedBox(height: AppSpacing.sm),
              ...<Widget>[
                for (final _Item item in _items)
                  _ItemTile(item: item, running: _running),
              ],
            ],
          ),
        ),
        _BottomActionBar(
          running: _running,
          onPick: _running ? null : _pickVideos,
          onCompress: _running ? null : _startCompression,
          onCancel: widget.compressor.cancelCompression,
        ),
      ],
    );
  }
}

/// The bottom-pinned actions: re-pick videos plus the primary Compress button,
/// which swaps to Cancel while a batch is running.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.running,
    required this.onPick,
    required this.onCompress,
    required this.onCancel,
  });

  final bool running;
  final VoidCallback? onPick;
  final VoidCallback? onCompress;
  final VoidCallback onCancel;

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
        child: Row(
          children: <Widget>[
            IconButton.outlined(
              onPressed: onPick,
              icon: const Icon(Icons.add),
              tooltip: 'Pick different videos',
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: running
                  ? OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    )
                  : FilledButton.icon(
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

/// Compact batch-wide options: codec, max-concurrent chips and background
/// switch, shown above the video list before compression starts.
class _BatchOptions extends StatelessWidget {
  const _BatchOptions({
    required this.enabled,
    required this.videoFormat,
    required this.onVideoFormatChanged,
    required this.maxConcurrent,
    required this.onMaxConcurrentChanged,
    required this.runInBackground,
    required this.onRunInBackgroundChanged,
  });

  final bool enabled;
  final VideoFormat videoFormat;
  final ValueChanged<VideoFormat> onVideoFormatChanged;
  final int? maxConcurrent;
  final ValueChanged<int?> onMaxConcurrentChanged;
  final bool runInBackground;
  final ValueChanged<bool> onRunInBackgroundChanged;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            title: const Text('Options'),
            subtitle: const Text('Codec, concurrency, background'),
            children: <Widget>[
              CodecSelector(
                value: videoFormat,
                onChanged: enabled ? onVideoFormatChanged : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Max concurrent'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final int? value in const <int?>[null, 1, 2, 3])
                    ChoiceChip(
                      label: Text(value == null ? 'Auto' : '$value'),
                      selected: maxConcurrent == value,
                      onSelected:
                          enabled ? (_) => onMaxConcurrentChanged(value) : null,
                    ),
                ],
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

/// The overall batch progress bar and completion count.
class _OverallProgress extends StatelessWidget {
  const _OverallProgress({
    required this.overall,
    required this.completed,
    required this.total,
  });

  final double overall;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: overall / 100,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Overall ${overall.toStringAsFixed(0)}% • $completed/$total',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single batch row with a thumbnail, progress ring / status icon, name and
/// a size-comparison or error subtitle.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.running});

  final _Item item;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final Result? result = item.result;
    final String? playPath =
        result is OnSuccess ? result.destinationPath : null;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: _Thumbnail(path: item.thumbnailPath),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _Subtitle(item: item, result: result),
        trailing: _Trailing(
          percent: item.percent,
          result: result,
          running: running,
        ),
        onTap: playPath != null
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        VideoPlayerScreen(path: playPath),
                  ),
                )
            : null,
      ),
    );
  }
}

/// The batch row's thumbnail, with a themed placeholder.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? currentPath = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: currentPath == null
          ? _placeholder(scheme)
          : Image.file(
              File(currentPath),
              width: 56,
              height: 40,
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
        width: 56,
        height: 40,
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.movie_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      );
}

/// The trailing progress ring (while running) or terminal status icon.
class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.percent,
    required this.result,
    required this.running,
  });

  final double percent;
  final Result? result;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Result? currentResult = result;
    if (currentResult == null) {
      // Before compression starts, show a neutral "queued" marker — only spin
      // once the batch is actually running.
      if (!running) {
        return Icon(Icons.schedule_outlined, color: scheme.onSurfaceVariant);
      }
      return SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: percent > 0 ? percent / 100 : null,
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
        ),
      );
    }
    if (currentResult is OnSuccess) {
      return Icon(Icons.play_circle, size: 28, color: scheme.primary);
    }
    if (currentResult is OnCancelled) {
      return Icon(Icons.cancel, color: scheme.tertiary);
    }
    return Icon(Icons.error, color: scheme.error);
  }
}

/// The subtitle line: idle "Ready", live percentage while running, or a size
/// comparison / failure message / "Cancelled" once finished.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.item, required this.result});

  final _Item item;
  final Result? result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Result? currentResult = result;
    if (currentResult == null) {
      return Text(
        item.percent > 0
            ? 'Compressing… ${item.percent.toStringAsFixed(0)}%'
            : 'Ready',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    if (currentResult is OnSuccess) {
      return Row(
        children: <Widget>[
          Text(formatBytes(currentResult.originalSize, 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Icon(Icons.arrow_right_alt,
                size: 16, color: scheme.onSurfaceVariant),
          ),
          Text(formatBytes(currentResult.compressedSize, 1)),
          Text(
            '  −${currentResult.ratio.toStringAsFixed(0)}%',
            style:
                TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    if (currentResult is OnFailure) {
      return Text(
        currentResult.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.error),
      );
    }
    return Text('Cancelled', style: TextStyle(color: scheme.tertiary));
  }
}
