import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'kitsu.dart';
import 'models.dart';
import 'player.dart';
import 'theme.dart';
import 'ui.dart';

String _clock(double seconds) {
  final s = seconds.floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final tail = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$tail' : '$m:$tail';
}

/// Lists where to watch a show. In-app sources come first, and they open the Vortex watch page.
class WhereToWatch extends StatelessWidget {
  final Account account;
  final Media media;

  const WhereToWatch({super.key, required this.account, required this.media});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        const Text('Where to watch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 10),
        if (media.links.isEmpty) const Text('No official place to watch this is listed yet.', style: TextStyle(color: Palette.muted)) else ProviderList(account: account, media: media),
      ],
    );
  }
}

class ProviderList extends StatelessWidget {
  final Account account;
  final Media media;
  final WatchLink? current;
  final ValueChanged<WatchLink>? onPick;

  const ProviderList({super.key, required this.account, required this.media, this.current, this.onPick});

  String _describe(WatchLink link) {
    final language = link.audioLabel;
    if (account.isBlocked(link)) return 'Not allowed in your country$language';
    final good = account.verified[media.id]?.contains(link.youtubePlaylist) ?? false;
    if (link.youtubePlaylist != null) return good ? 'Plays in the Vortex player$language' : 'May not be allowed in your country$language';
    if (link.site == 'YouTube') return 'Official channel, opens YouTube$language';
    return 'Opens ${link.site}, may need a subscription$language';
  }

  @override
  Widget build(BuildContext context) {
    final inApp = account.playable(media);
    final rest = media.links.where((l) => !inApp.contains(l)).toList();
    final seen = <String, int>{};
    String nameOf(WatchLink l) {
      final base = l.youtubePlaylist != null ? 'Official stream' : l.site;
      final n = seen[base] = (seen[base] ?? 0) + 1;
      return n > 1 ? '$base $n' : base;
    }

    return Column(
      children: [
        for (final link in [...inApp, ...rest])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () {
                if (!inApp.contains(link) || !canPlayInApp) {
                  openExternal(context, link.url);
                } else if (onPick != null) {
                  onPick!(link);
                } else {
                  go(context, WatchScreen(account: account, media: media, source: link));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: identical(link, current) ? Palette.purple.withValues(alpha: 0.16) : Palette.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: identical(link, current) ? Palette.purple : Palette.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(nameOf(link), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                              if (account.verified[media.id]?.contains(link.youtubePlaylist) ?? false) ...[const SizedBox(width: 8), const PlaysTag()],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(_describe(link), style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(inApp.contains(link) && canPlayInApp ? Icons.play_circle_fill_rounded : Icons.open_in_new_rounded, color: Palette.bright, size: 24),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Vortex watch page. Everything plays here, through each service's official player.
class WatchScreen extends StatefulWidget {
  final Account account;
  final Media media;
  final WatchLink? source;
  final int? episode;

  const WatchScreen({super.key, required this.account, required this.media, this.source, this.episode});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final _youtube = YouTubeHandle();
  WatchLink? _source;
  late int _episode;
  bool _full = false;
  String? _notice;

  PlayerStatus _status = const PlayerStatus();
  bool _controls = true;
  bool _captions = false;
  double? _dragging;
  Timer? _hide;
  Timer? _nextTimer;
  Timer? _startCheck;
  int? _nextIn;
  DateTime _lastSave = DateTime.now();
  bool _markedDone = false;
  int? _ripple;
  int? _goingTo;
  ShowExtras? _extras;

  Account get _a => widget.account;
  Media get _m => widget.media;
  int? get _total => _m.knownEpisodes;

  @override
  void initState() {
    super.initState();
    final done = _a.entry(_m.id)?.progress ?? 0;
    final total = _total;
    _episode = widget.episode ?? (total != null && done >= total ? 1 : done + 1);
    _source = widget.source ?? _firstSource();
    _goingTo = _episode;
    _watchStart();
    if (_source != null && _a.entry(_m.id) == null) _guard(_a.setStatus(_m, 'watching'));
    _loadExtras();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _scheduleHide();
  }

  /// A stream nobody has confirmed gets a fair try, then Vortex moves on instead of spinning forever.
  void _watchStart() {
    _startCheck?.cancel();
    final source = _source;
    if (source?.youtubePlaylist == null || (_a.verified[_m.id]?.contains(source!.youtubePlaylist) ?? false)) return;
    _startCheck = Timer(const Duration(seconds: 15), () {
      if (mounted && _source == source && !_status.playing && _status.duration <= 0) _handleError(150);
    });
  }

  @override
  void dispose() {
    _startCheck?.cancel();
    _hide?.cancel();
    _nextTimer?.cancel();
    _savePosition();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  WatchLink? _firstSource() {
    if (!canPlayInApp) return null;
    final remembered = _a.lastSource(_m.id);
    final sources = _a.playable(_m);
    for (final s in sources) {
      if (s.url == remembered) return s;
    }
    return sources.isEmpty ? null : sources.first;
  }

  void _pick(WatchLink link) {
    _savePosition();
    _a.rememberSource(_m.id, link.url);
    _goingTo = _episode;
    setState(() {
      _source = link;
      _notice = null;
      _status = const PlayerStatus();
    });
    _watchStart();
  }

  void _savePosition() {
    if (_source?.youtubePlaylist == null || _status.duration <= 0) return;
    _a.savePosition(_m.id, _episode, _status.position);
  }

  void _setFull(bool value) {
    if (value) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    setState(() => _full = value);
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && _status.playing && _dragging == null) setState(() => _controls = false);
    });
  }

  void _touch() {
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _loadExtras() {
    Kitsu.forShow(_m.id, from: _episode - 1).then((e) {
      if (mounted && e != null) setState(() => _extras = e);
    });
  }

  void _onStatus(PlayerStatus s) {
    if (!mounted) return;
    if (s.error != null && _status.error == null) {
      _handleError(s.error!);
      return;
    }
    // The playlist rolls on by itself when an episode ends, so follow it and count the one just finished.
    final at = s.index;
    if (at != null && at >= 0 && s.playing) {
      if (_goingTo != null) {
        if (at + 1 == _goingTo) _goingTo = null;
      } else if (at + 1 != _episode) {
        final finished = at + 1 > _episode ? _episode : null;
        setState(() {
          _episode = at + 1;
          _markedDone = false;
        });
        _loadExtras();
        if (finished != null && finished > (_a.entry(_m.id)?.progress ?? 0)) _guard(_a.markWatchedUpTo(_m, finished));
        _touch();
      }
    }
    final d = s.duration;
    if (d > 0 && !_markedDone && (s.ended || s.position / d >= 0.92)) {
      _markedDone = true;
      if (_episode > (_a.entry(_m.id)?.progress ?? 0)) _guard(_a.markWatchedUpTo(_m, _episode));
    }
    if (s.ended && !_status.ended) _offerNext();
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) {
      _lastSave = DateTime.now();
      if (d > 0) _a.savePosition(_m.id, _episode, s.position);
    }
    if (s.playing && !_status.playing) _scheduleHide();
    setState(() => _status = s);
  }

  void _handleError(int code) {
    final blocked = code == 100 || code == 101 || code == 150 || code == 153;
    final source = _source;
    if (blocked && source != null) _a.markBlocked(source);
    final remaining = _a.playable(_m);
    setState(() {
      _status = const PlayerStatus();
      _source = remaining.isEmpty ? null : remaining.first;
      _goingTo = _episode;
      _notice = blocked
          ? (remaining.isEmpty ? 'This show isn\'t allowed to play in your country here.' : 'That copy isn\'t allowed in your country, so Vortex switched to another.')
          : 'That video wouldn\'t play. Try another option below.';
    });
    _watchStart();
  }

  void _guard(Future<void> action) {
    action.catchError((Object _) {
      if (mounted) toast(context, 'Check your internet connection and try again.');
    });
  }

  /// Episodes this source really has, which can be fewer than the show's full count.
  int? get _limit {
    final inSource = _source?.youtubePlaylist == null ? null : _status.episodesInSource;
    if (inSource != null && inSource > 0) return _total == null ? inSource : (inSource < _total! ? inSource : _total);
    return _total;
  }

  bool get _hasNext => _limit == null || _episode < _limit!;

  void _go(int episode) {
    _savePosition();
    _nextTimer?.cancel();
    final youtube = _source?.youtubePlaylist != null;
    if (youtube) _goingTo = episode;
    _loadExtras();
    setState(() {
      _episode = episode;
      _nextIn = null;
      _markedDone = false;
      _status = const PlayerStatus();
    });
    if (youtube) _youtube.item(episode - 1, _a.position(_m.id, episode));
    _touch();
  }

  void _offerNext() {
    if (!_hasNext) return;
    setState(() => _nextIn = 8);
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final left = (_nextIn ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        _go(_episode + 1);
      } else {
        setState(() => _nextIn = left);
      }
    });
  }

  void _skip(double by) {
    final target = (_status.position + by).clamp(0.0, _status.duration);
    _youtube.seek(target);
    setState(() {
      _status = PlayerStatus(playing: _status.playing, buffering: _status.buffering, position: target, duration: _status.duration, ready: _status.ready);
      _ripple = by > 0 ? 1 : -1;
    });
    Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _ripple = null);
    });
    _touch();
  }

  void _togglePlay() {
    _status.playing ? _youtube.pause() : _youtube.play();
    _touch();
  }

  // YouTube stage

  Widget _stage(WatchLink link) {
    final disabled = _status.duration <= 0;
    final total = _status.duration;
    final at = _dragging ?? _status.position;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: YouTubeView(
            key: ValueKey(link.youtubePlaylist),
            playlist: link.youtubePlaylist!,
            index: _episode - 1,
            start: _a.position(_m.id, _episode),
            handle: _youtube,
            onStatus: _onStatus,
          ),
        ),
        if (!playerHasOwnControls) ...[
          // While hidden, the lower corner stays free so YouTube's own Skip ad button can be pressed.
          Positioned.fill(
            bottom: _controls ? 0 : 90,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _controls ? setState(() => _controls = false) : _touch(),
              onDoubleTapDown: (d) {
                final half = context.size == null ? 0 : (_full ? MediaQuery.sizeOf(context).width : MediaQuery.sizeOf(context).width) / 2;
                _skip(d.localPosition.dx > half ? 10 : -10);
              },
              onDoubleTap: () {},
            ),
          ),
          if (_ripple != null)
            Align(
              alignment: _ripple! > 0 ? const Alignment(0.7, 0) : const Alignment(-0.7, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                child: Icon(_ripple! > 0 ? Icons.forward_10_rounded : Icons.replay_10_rounded, size: 30),
              ),
            ),
          IgnorePointer(
            ignoring: !_controls,
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _status.playing ? Colors.transparent : const Color(0x8C000000),
                  gradient: _status.playing ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.3, 0.65, 1], colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)]) : null,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          IconButton(tooltip: 'Back', onPressed: () => _full ? _setFull(false) : Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: _status.playing ? 1 : 0,
                              duration: const Duration(milliseconds: 160),
                              child: Text('${_m.title}  ·  Episode $_episode', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Back 10 seconds', iconSize: 34, onPressed: disabled ? null : () => _skip(-10), icon: const Icon(Icons.replay_10_rounded)),
                          const SizedBox(width: 14),
                          _PlayButton(playing: _status.playing, buffering: _status.buffering && !_status.playing, onTap: _togglePlay),
                          const SizedBox(width: 14),
                          IconButton(tooltip: 'Forward 10 seconds', iconSize: 34, onPressed: disabled ? null : () => _skip(10), icon: const Icon(Icons.forward_10_rounded)),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 4,
                      bottom: 2,
                      child: Row(
                        children: [
                          Text(_clock(at), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor: Palette.purple,
                                inactiveTrackColor: const Color(0x55FFFFFF),
                                thumbColor: Colors.white,
                                overlayColor: Palette.purple.withValues(alpha: 0.25),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: total <= 0 ? 0 : at.clamp(0.0, total),
                                max: total <= 0 ? 1 : total,
                                onChangeStart: (_) => _hide?.cancel(),
                                onChanged: total <= 0 ? null : (v) => setState(() => _dragging = v),
                                onChangeEnd: (v) {
                                  _youtube.seek(v);
                                  setState(() => _dragging = null);
                                  _scheduleHide();
                                },
                              ),
                            ),
                          ),
                          Text(_clock(total), style: const TextStyle(fontSize: 12, color: Color(0xCCFFFFFF), fontFeatures: [FontFeature.tabularFigures()])),
                          IconButton(
                            tooltip: _captions ? 'Turn captions off' : 'Turn captions on',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => _captions = !_captions);
                              _youtube.captions(_captions);
                              _touch();
                            },
                            icon: Icon(_captions ? Icons.closed_caption_rounded : Icons.closed_caption_off_rounded, color: _captions ? Palette.bright : Colors.white),
                          ),
                          IconButton(
                            tooltip: _full ? 'Exit full screen' : 'Full screen',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _setFull(!_full),
                            icon: Icon(_full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_nextIn != null)
            Positioned(
              right: 12,
              bottom: 60,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Palette.line)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Episode ${_episode + 1} in $_nextIn', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        _nextTimer?.cancel();
                        setState(() => _nextIn = null);
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(onPressed: () => _go(_episode + 1), child: const Text('Play')),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _episodeStrip() {
    final count = _limit;
    final done = _a.entry(_m.id)?.progress ?? 0;
    final last = count ?? (_episode + 12);
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
        itemCount: last,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final n = i + 1;
          final current = n == _episode;
          return Pressable(
            onTap: () => _source?.youtubePlaylist != null ? _go(n) : setState(() => _episode = n),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current ? Palette.purple : Palette.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: current ? Palette.purple : Palette.line),
              ),
              child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: current ? Colors.white : (n <= done ? Palette.lavender : Colors.white))),
            ),
          );
        },
      ),
    );
  }

  Widget _noticeBar() {
    if (_notice == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: pageSide(context), vertical: 10),
      color: Palette.card,
      child: Text(_notice!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _info() {
    final total = _total;
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 30),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Episode $_episode${total == null ? '' : ' of $total'}', style: const TextStyle(color: Palette.lavender, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_m.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1.15)),
              if (_extras?.episodes[_episode]?.title.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_extras!.episodes[_episode]!.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (_extras?.episodes[_episode]?.synopsis.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_extras!.episodes[_episode]!.synopsis, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.45))),
              if (_a.verifiedAudio[_m.id] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Confirmed: ${_a.verifiedAudio[_m.id]}', style: const TextStyle(color: Palette.lavender, fontSize: 12.5, fontWeight: FontWeight.w600))),
              if (_limit != null && _total != null && _limit! < _total!) Padding(padding: const EdgeInsets.only(top: 6), child: Text('This source has the first $_limit episodes.', style: const TextStyle(color: Palette.lavender, fontSize: 12.5))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: _episode > 1 ? () => _go(_episode - 1) : null, icon: const Icon(Icons.skip_previous_rounded), label: const Text('Previous')),
                  FilledButton.icon(onPressed: _hasNext ? () => _go(_episode + 1) : null, icon: const Icon(Icons.skip_next_rounded), label: const Text('Next episode')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _episodeStrip(),
        Padding(
          padding: EdgeInsets.fromLTRB(pageSide(context), 24, pageSide(context), 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ProviderList(account: _a, media: _m, current: _source, onPick: _pick),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nothing() {
    return ListView(
      padding: EdgeInsets.fromLTRB(pageSide(context), 24, pageSide(context), 30),
      children: [
        const Text('CAN\'T PLAY IN VORTEX YET', style: TextStyle(fontFamily: 'Bebas', fontSize: 38, height: 1)),
        const SizedBox(height: 6),
        Text(
          _m.links.isEmpty ? 'No official source for this show is listed yet.' : 'No source lets this show play in the Vortex player where you are. These official options have it.',
          style: const TextStyle(color: Palette.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (_m.links.isNotEmpty) ProviderList(account: _a, media: _m),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final Widget content;
    if (source == null) {
      content = Scaffold(
        appBar: AppBar(backgroundColor: Palette.background, scrolledUnderElevation: 0, title: Text(_m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        body: Column(children: [_noticeBar(), Expanded(child: _nothing())]),
      );
    } else {
      final size = MediaQuery.sizeOf(context);
      final wide = isWide(context);
      final stageWidth = size.width;
      final fit = stageWidth * 9 / 16;
      final height = _full ? size.height : (wide && fit > size.height * 0.68 ? size.height * 0.68 : fit);
      content = Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_full,
          bottom: false,
          left: !_full,
          right: !_full,
          child: Column(
            children: [
              SizedBox(width: double.infinity, height: height, child: _stage(source)),
              if (!_full) ...[_noticeBar(), Expanded(child: ColoredBox(color: Palette.background, child: _info()))],
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _full) _setFull(false);
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _TogglePlay(),
          SingleActivator(LogicalKeyboardKey.keyK): _TogglePlay(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _Seek(10),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _Seek(-10),
          SingleActivator(LogicalKeyboardKey.keyF): _ToggleFull(),
        },
        child: Actions(
          actions: {
            _TogglePlay: CallbackAction<_TogglePlay>(onInvoke: (_) => _togglePlay()),
            _Seek: CallbackAction<_Seek>(onInvoke: (i) => _skip(i.by)),
            _ToggleFull: CallbackAction<_ToggleFull>(onInvoke: (_) => _setFull(!_full)),
          },
          child: Focus(autofocus: true, child: content),
        ),
      ),
    );
  }

}

class _TogglePlay extends Intent {
  const _TogglePlay();
}

class _ToggleFull extends Intent {
  const _ToggleFull();
}

class _Seek extends Intent {
  final double by;

  const _Seek(this.by);
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final bool buffering;
  final VoidCallback onTap;

  const _PlayButton({required this.playing, required this.buffering, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Palette.purple, shape: BoxShape.circle),
          child: buffering
              ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), size: 38),
                ),
        ),
      ),
    );
  }
}
