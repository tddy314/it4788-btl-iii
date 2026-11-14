import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_states.dart';
import 'post_models.dart';

class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.initial = 0});
  final List<PostMedia> media;
  final int initial;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _index = widget.initial;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_index + 1}/${widget.media.length}')),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.media.length,
      onPageChanged: (v) => setState(() => _index = v),
      itemBuilder: (context, i) => widget.media[i].isVideo
          ? PostVideo(url: widget.media[i].url, active: i == _index)
          : InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: AppNetworkImage(
                  url: widget.media[i].url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
    ),
  );
}

class PostVideo extends StatefulWidget {
  const PostVideo({super.key, required this.url, required this.active});
  final String url;
  final bool active;
  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() => _error = null);
    final next = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = next;
    try {
      await next.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      next.addListener(_changed);
      setState(() {});
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Không tải được video. Video cần kết nối mạng; hãy thử lại khi có Internet.',
        );
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_controller?.value.hasError == true) {
      _error = 'Video bị gián đoạn. Kiểm tra kết nối rồi thử lại.';
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(PostVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) unawaited(_controller?.pause());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_error != null) return AppErrorState(message: _error!, onRetry: _load);
    if (c == null || !c.value.isInitialized) {
      return const AppLoadingState(message: 'Đang tải video…');
    }
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: c.value.aspectRatio > 0
                  ? c.value.aspectRatio
                  : 16 / 9,
              child: VideoPlayer(c),
            ),
            VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: const EdgeInsets.all(16),
            ),
            if (c.value.isBuffering) const LinearProgressIndicator(),
            IconButton.filled(
              tooltip: c.value.isPlaying ? 'Tạm dừng' : 'Phát video',
              onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
          ],
        ),
      ),
    );
  }
}
