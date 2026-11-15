import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'fx.dart';
import 'models.dart';
import 'now_playing.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

const _introThreshold = Duration(milliseconds: 2500);

void openLyrics(BuildContext context, PlayerController c) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => LyricsScreen(c: c),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

class LyricsScreen extends StatelessWidget {
  final PlayerController c;

  const LyricsScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.current;
        if (t == null) return const SizedBox.shrink();
        final wide = isWide(context);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AppBackdrop(c: c),
              SafeArea(child: wide ? _wide(context, t) : _phone(context, t)),
            ],
          ),
        );
      },
    );
  }

  Widget _phone(BuildContext context, Track t) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              IconButton(tooltip: 'Back', icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.pop(context)),
              Art(t.thumbnail, size: 48, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
                  ],
                ),
              ),
              LikeButton(c: c, t: t),
            ],
          ),
        ),
        Expanded(child: LyricsPane(key: ValueKey(t.id), c: c, track: t, fontSize: 28)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SeekBar(c: c, seed: t.id, fallback: t.duration, compact: true),
              TransportControls(c: c, scale: 0.8, glow: c.tint.value),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context, Track t) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: LayoutBuilder(
                builder: (ctx, box) {
                  final size = min(min(box.maxWidth - 120, 440.0), max(box.maxHeight - 260, 160.0));
                  return Center(
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: max(size, 320),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 24))],
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 340),
                                child: Art(t.artUrl, key: ValueKey(t.id), size: size, radius: 18),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SeekBar(c: c, seed: t.id, fallback: t.duration, compact: true),
                            const SizedBox(height: 12),
                            Text(t.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                            const SizedBox(height: 2),
                            Text(t.artist, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0xCCFFFFFF))),
                            const SizedBox(height: 10),
                            TransportControls(c: c, scale: 0.8, glow: c.tint.value),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(flex: 6, child: LyricsPane(key: ValueKey(t.id), c: c, track: t, fontSize: 40)),
          ],
        ),
        Positioned(
          left: 12,
          top: 8,
          child: IconButton(tooltip: 'Back', icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.pop(context)),
        ),
      ],
    );
  }
}

class LyricsPane extends StatefulWidget {
  final PlayerController c;
  final Track track;
  final double fontSize;

  const LyricsPane({super.key, required this.c, required this.track, required this.fontSize});

  @override
  State<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends State<LyricsPane> with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker((_) => _tick());
  Lyrics? _lyrics;
  List<LyricLine> _lines = [];
  List<GlobalKey> _keys = [];
  bool _failed = false;
  int _active = -1;
  DateTime? _manualUntil;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lyrics = await widget.c.api.lyrics(widget.track);
      if (!mounted) return;
      final lines = [...lyrics.synced];
      if (lines.isNotEmpty && lines.first.time >= _introThreshold) {
        lines.insert(0, const LyricLine(Duration.zero, ''));
      }
      setState(() {
        _lyrics = lyrics;
        _lines = lines;
        _keys = [for (final _ in lines) GlobalKey()];
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _tick() {
    final position = widget.c.player.position;
    _position.value = position;
    if (_lines.isEmpty) return;
    var index = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    if (index != _active) {
      setState(() => _active = index);
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  void _follow() {
    final manual = _manualUntil;
    if (manual != null && DateTime.now().isBefore(manual)) return;
    if (_active < 0 || _active >= _keys.length) return;
    final context = _keys[_active].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 780), curve: Curves.easeOutQuart);
  }

  Duration _lineEnd(int i) {
    if (i + 1 < _lines.length) return _lines[i + 1].time;
    return widget.c.player.duration ?? _lines[i].time + const Duration(seconds: 5);
  }

  void _seekTo(LyricLine line) {
    _manualUntil = null;
    widget.c.player.seek(line.time);
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = _lyrics;
    if (_failed) return _message(Icons.cloud_off_rounded, 'Couldn\'t load lyrics');
    if (lyrics == null) {
      return Center(child: const EqualizerBars(size: 34, color: Colors.white));
    }
    if (lyrics.isEmpty) return _message(Icons.music_off_rounded, 'No lyrics for this song');
    final horizontal = isWide(context) ? 28.0 : 24.0;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.1, 0.84, 1],
      ).createShader(rect),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          _manualUntil = DateTime.now().add(const Duration(seconds: 4));
          return false;
        },
        child: LayoutBuilder(
          builder: (ctx, box) => SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(horizontal, box.maxHeight * 0.3, horizontal, box.maxHeight * 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _lines.isEmpty ? _plainLines(lyrics) : _syncedLines(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _plainLines(Lyrics lyrics) {
    return [
      for (final line in lyrics.plain)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(line, style: TextStyle(fontSize: widget.fontSize * 0.8, fontWeight: FontWeight.w800, height: 1.2, color: const Color(0xD9FFFFFF), letterSpacing: -0.4)),
        ),
    ];
  }

  List<Widget> _syncedLines() {
    return [
      for (var i = 0; i < _lines.length; i++)
        KeyedSubtree(
          key: _keys[i],
          child: _lines[i].isBreak
              ? _BreakDots(active: i == _active, position: _position, start: _lines[i].time, end: _lineEnd(i))
              : _LyricRow(
                  text: _lines[i].text,
                  fontSize: widget.fontSize,
                  distance: _active < 0 ? i + 1 : (i - _active).abs(),
                  active: i == _active,
                  position: _position,
                  start: _lines[i].time,
                  end: _lineEnd(i),
                  onTap: () => _seekTo(_lines[i]),
                ),
        ),
    ];
  }

  Widget _message(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: const Color(0x99FFFFFF)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _LyricRow extends StatefulWidget {
  final String text;
  final double fontSize;
  final int distance;
  final bool active;
  final ValueNotifier<Duration> position;
  final Duration start;
  final Duration end;
  final VoidCallback onTap;

  const _LyricRow({
    required this.text,
    required this.fontSize,
    required this.distance,
    required this.active,
    required this.position,
    required this.start,
    required this.end,
    required this.onTap,
  });

  @override
  State<_LyricRow> createState() => _LyricRowState();
}

class _LyricRowState extends State<_LyricRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final focus = widget.active || _hover;
    final ripple = Duration(milliseconds: 460 + min(widget.distance, 6) * 70);
    final sigma = focus ? 0.0 : min(widget.distance * 0.9, 4.5);
    final opacity = widget.active ? 1.0 : (_hover ? 0.85 : max(0.46 - widget.distance * 0.035, 0.2));
    final style = TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w900, height: 1.18, letterSpacing: -0.8, color: Colors.white);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.fontSize * 0.34),
          child: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
            tween: Tween(end: sigma),
            duration: ripple,
            curve: Curves.easeOutCubic,
            builder: (ctx, blur, child) => blur < 0.05
                ? child!
                : ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: child),
            child: AnimatedOpacity(
              opacity: opacity,
              duration: ripple,
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: widget.active ? 1 : 0.94,
                alignment: Alignment.centerLeft,
                duration: ripple,
                curve: Curves.easeOutBack,
                child: widget.active
                    ? ValueListenableBuilder<Duration>(
                        valueListenable: widget.position,
                        builder: (ctx, position, child) {
                          final span = max((widget.end - widget.start).inMilliseconds, 1);
                          final progress = ((position - widget.start).inMilliseconds / span).clamp(0.0, 1.0);
                          return ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (rect) => LinearGradient(
                              colors: const [Colors.white, Colors.white, Color(0x73FFFFFF)],
                              stops: [0, progress * 1.15, min(progress * 1.15 + 0.14, 1)],
                            ).createShader(rect),
                            child: child,
                          );
                        },
                        child: Text(widget.text, style: style),
                      )
                    : Text(widget.text, style: style),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BreakDots extends StatelessWidget {
  final bool active;
  final ValueNotifier<Duration> position;
  final Duration start;
  final Duration end;

  const _BreakDots({required this.active, required this.position, required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: !active
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: ValueListenableBuilder<Duration>(
                valueListenable: position,
                builder: (ctx, value, _) {
                  final span = max((end - start).inMilliseconds, 1);
                  final progress = ((value - start).inMilliseconds / span).clamp(0.0, 1.0);
                  final time = value.inMilliseconds / 1000;
                  return Row(
                    children: [
                      for (var i = 0; i < 3; i++) _dot(i, progress, time),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _dot(int i, double progress, double time) {
    final fill = ((progress * 3) - i).clamp(0.0, 1.0);
    final breath = 1 + 0.14 * sin(time * 3.2 + i * 0.9);
    final exit = progress > 0.92 ? (1 - (progress - 0.92) / 0.08).clamp(0.0, 1.0) : 1.0;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Transform.translate(
        offset: Offset(0, -3 * fill * sin(time * 3.2 + i * 0.9).abs()),
        child: Transform.scale(
          scale: breath * exit,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.28 + 0.72 * fill),
              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.4 * fill), blurRadius: 14)],
            ),
          ),
        ),
      ),
    );
  }
}
