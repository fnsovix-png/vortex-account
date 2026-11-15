import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool get canPlayInApp => true;

class PlayerStatus {
  final bool playing;
  final bool buffering;
  final bool ended;
  final double position;
  final double duration;
  final int? error;
  final bool ready;
  final int? episodesInSource;
  final int? index;

  const PlayerStatus({this.playing = false, this.buffering = true, this.ended = false, this.position = 0, this.duration = 0, this.error, this.ready = false, this.episodesInSource, this.index});
}

class YouTubeHandle {
  void play() {}
  void pause() {}
  void seek(double seconds) {}
  void captions(bool on) {}
  void item(int index, double start) {}
}

class _Frame extends StatefulWidget {
  final String url;

  const _Frame({required this.url});

  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  static int _count = 0;
  late String _view;

  void _register() {
    _view = 'official-player-${++_count}';
    final url = widget.url;
    ui_web.platformViewRegistry.registerViewFactory(_view, (int _) {
      return web.HTMLIFrameElement()
        ..src = url
        ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen'
        ..allowFullscreen = true
        ..referrerPolicy = 'strict-origin-when-cross-origin'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(_Frame old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _register();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(key: ValueKey(_view), viewType: _view);
}

/// In a browser YouTube draws its own controls, since pages can't sit on top of its frame reliably.
class YouTubeView extends StatelessWidget {
  final String playlist;
  final int index;
  final double start;
  final YouTubeHandle handle;
  final ValueChanged<PlayerStatus> onStatus;

  const YouTubeView({super.key, required this.playlist, required this.index, required this.start, required this.handle, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final list = Uri.encodeQueryComponent(playlist);
    return _Frame(url: 'https://www.youtube-nocookie.com/embed/videoseries?list=$list&index=$index&start=${start.floor()}&rel=0&playsinline=1&autoplay=1');
  }
}

const bool playerHasOwnControls = true;
