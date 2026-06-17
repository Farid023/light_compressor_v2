import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'utils/file_utils.dart';
import 'video_player.dart';

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
  double _overall = 0;
  bool _running = false;
  bool _runInBackground = false;
  StreamSubscription<BatchEvent>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _pickAndCompress() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return;

    final paths = [for (final f in files) f.path!];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final names = [
      for (var i = 0; i < paths.length; i++) 'Batch-$stamp-$i.mp4'
    ];

    setState(() {
      _items = [for (final f in files) _Item(f.name)];
      _overall = 0;
      _running = true;
    });

    // Load preview thumbnails in the background; they fill in as they arrive.
    for (var i = 0; i < paths.length; i++) {
      unawaited(_loadThumbnail(i, paths[i]));
    }

    await _subscription?.cancel();
    _subscription = widget.compressor.onBatchUpdate.listen((event) {
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
        paths: paths,
        videoNames: names,
        videoQuality: VideoQuality.medium,
        isMinBitrateCheckEnabled: false,
        android: AndroidConfig(isSharedStorage: true, saveAt: SaveAt.Movies),
        ios: IOSConfig(saveInGallery: false),
        background: _runInBackground
            ? const BackgroundConfig()
            : null,
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
      final thumb = await widget.compressor.getVideoThumbnail(
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
    final completed = _items.where((i) => i.result != null).length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _running ? null : _pickAndCompress,
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('Pick videos'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Run in background'),
            subtitle: const Text(
              'Keep compressing when the app is backgrounded or the screen is off',
            ),
            value: _runInBackground,
            onChanged: _running
                ? null
                : (value) => setState(() => _runInBackground = value),
          ),
          if (_running) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _overall / 100,
                minHeight: 8,
                backgroundColor: Colors.black12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall ${_overall.toStringAsFixed(0)}% • '
                  '$completed/${_items.length}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                OutlinedButton.icon(
                  onPressed: widget.compressor.cancelCompression,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Pick multiple videos to compress them as a batch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black45, fontSize: 15),
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ItemTile(item: _items[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A single batch row with progress and status.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final result = item.result;
    final playPath = result is OnSuccess ? result.destinationPath : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: _thumbnail(),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(result),
      trailing: _trailing(result),
      onTap: playPath != null
          ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VideoPlayerScreen(path: playPath),
                ),
              )
          : null,
    );
  }

  Widget _thumbnail() => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: item.thumbnailPath != null
            ? Image.file(
                File(item.thumbnailPath!),
                width: 56,
                height: 40,
                fit: BoxFit.cover,
              )
            : Container(
                width: 56,
                height: 40,
                color: Colors.black12,
                child: const Icon(
                  Icons.movie_outlined,
                  size: 18,
                  color: Colors.black38,
                ),
              ),
      );

  Widget _trailing(Result? result) {
    if (result == null) {
      return SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: item.percent > 0 ? item.percent / 100 : null,
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
        ),
      );
    }
    if (result is OnSuccess) {
      return const Icon(Icons.play_circle, size: 28);
    }
    if (result is OnCancelled) {
      return const Icon(Icons.cancel, color: Colors.orange);
    }
    return const Icon(Icons.error, color: Colors.red);
  }

  Widget _subtitle(Result? result) {
    if (result == null) {
      return Text('Compressing… ${item.percent.toStringAsFixed(0)}%');
    }
    if (result is OnSuccess) {
      return Row(
        children: [
          Text(formatBytes(result.originalSize, 1)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.arrow_right_alt, size: 16),
          ),
          Text(formatBytes(result.compressedSize, 1)),
          Text('  −${result.ratio.toStringAsFixed(0)}%'),
        ],
      );
    }
    if (result is OnFailure) {
      return Text(result.message, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return const Text('Cancelled');
  }
}
