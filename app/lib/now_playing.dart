import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'appearance.dart';
import 'artist.dart';
import 'fx.dart';
import 'lyrics.dart';
import 'models.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

void showQueueSheet(BuildContext context, PlayerController c) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xF216161C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, scroll) => UpNextList(c: c, controller: scroll),
    ),
  );
}

class UpNextList extends StatelessWidget {
  final PlayerController c;
  final ScrollController? controller;

  const UpNextList({super.key, required this.c, this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final count = max(c.queue.length - c.index - 1, 0);
        return ListView.builder(
          controller: controller,
          itemCount: count + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Expanded(child: Text('Up next', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
                    Text(count == 1 ? '1 song' : '$count songs', style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
                  ],
                ),
              );
            }
            final queueIndex = c.index + i;
            return FadeSlideIn(
              index: i,
              child: TrackTile(track: c.queue[queueIndex], c: c, onTap: () => c.jumpTo(queueIndex)),
            );
          },
        );
      },
    );
  }
}

class PlayPauseButton extends StatelessWidget {
  final AudioPlayer player;
  final double size;
  final bool filled;
  final Color glow;

  const PlayPauseButton({super.key, required this.player, required this.size, required this.filled, Color? glow}) : glow = glow ?? const Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (ctx, snap) {
        final s = snap.data;
        final busy = s?.processingState == ProcessingState.loading || s?.processingState == ProcessingState.buffering;
        final playing = s?.playing ?? false;
        final style = VortexStyles.current;
        final color = filled ? style.buttonIcon : Colors.white;
        final icon = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: size * 0.62,
                  height: size * 0.62,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
                )
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), size: size, color: color),
        );
        final onPressed = playing ? player.pause : player.play;
        if (!filled) return IconButton(tooltip: playing ? 'Pause' : 'Play', icon: icon, onPressed: onPressed);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            StyledButtonDecor(style: style, radius: size),
            Container(
              width: size * 2,
              height: size * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                
              ),
              child: IconButton.filled(
                tooltip: playing ? 'Pause' : 'Play',
                style: IconButton.styleFrom(backgroundColor: style.buttonColor),
                icon: icon,
                onPressed: onPressed,
              ),
            ),
          ],
        );
      },
    );
  }
}

class TransportControls extends StatelessWidget {
  final PlayerController c;
  final double scale;
  final Color glow;

  const TransportControls({super.key, required this.c, this.scale = 1, Color? glow}) : glow = glow ?? const Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Toggle(icon: Icons.shuffle_rounded, label: c.shuffle ? 'Shuffle on' : 'Shuffle off', active: c.shuffle, size: 24 * scale, onTap: c.toggleShuffle),
        IconButton(tooltip: 'Previous', iconSize: 40 * scale, icon: const Icon(Icons.skip_previous_rounded), onPressed: c.previous),
        PlayPauseButton(player: c.player, size: 34 * scale, filled: true, glow: glow),
        IconButton(tooltip: 'Next', iconSize: 40 * scale, icon: const Icon(Icons.skip_next_rounded), onPressed: c.hasNext ? c.next : null),
        _Toggle(
          icon: c.repeat == RepeatSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          label: c.repeatLabel,
          active: c.repeat != RepeatSetting.off,
          size: 24 * scale,
          onTap: c.cycleRepeat,
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final double size;
  final VoidCallback onTap;

  const _Toggle({required this.icon, required this.label, required this.active, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: label, iconSize: size, icon: Icon(icon, color: active ? AppColors.accent : Colors.white), onPressed: onTap),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? 5 : 0,
          height: active ? 5 : 0,
          decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

class LikeButton extends StatelessWidget {
  final PlayerController c;
  final Track t;
  final double size;

  const LikeButton({super.key, required this.c, required this.t, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final liked = c.isLiked(t);
    return IconButton(
      tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      onPressed: () => c.toggleLike(t),
      icon: TweenAnimationBuilder<double>(
        key: ValueKey(liked),
        tween: Tween(begin: liked ? 0.5 : 1, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (ctx, v, child) => Transform.scale(scale: v, child: child),
        child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: size, color: liked ? AppColors.accent : Colors.white),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  final PlayerController c;
  final VoidCallback onOpen;

  const MiniPlayer({super.key, required this.c, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = c.current!;
    return GestureDetector(
      onTap: onOpen,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onOpen();
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200 && c.hasNext) c.next();
        if (v > 200) c.previous();
      },
      child: Glass(
        radius: 10,
        opacity: 0.08,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
              child: Row(
                children: [
                  Hero(tag: 'art', child: Art(t.thumbnail, size: 44, radius: 11)),
                  const SizedBox(width: 12),
                  Expanded(child: _SwitchingTitle(t, titleSize: 14, artistSize: 12)),
                  LikeButton(c: c, t: t),
                  PlayPauseButton(player: c.player, size: 30, filled: false),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: StreamBuilder<Duration>(
                stream: c.player.positionStream,
                builder: (ctx, snap) {
                  final total = c.player.duration?.inMilliseconds ?? 0;
                  final pos = snap.data?.inMilliseconds ?? 0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                      minHeight: 3,
                      color: AppColors.accent,
                      backgroundColor: const Color(0x22FFFFFF),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchingTitle extends StatelessWidget {
  final Track t;
  final double titleSize;
  final double artistSize;

  const _SwitchingTitle(this.t, {required this.titleSize, required this.artistSize});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: Column(
        key: ValueKey(t.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: titleSize, letterSpacing: -0.2)),
          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.subtle, fontSize: artistSize)),
        ],
      ),
    );
  }
}

class DesktopPlayerBar extends StatelessWidget {
  final PlayerController c;
  final VoidCallback onOpen;

  const DesktopPlayerBar({super.key, required this.c, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = c.current!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Glass(
        radius: 10,
        opacity: 0.06,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: SizedBox(
          height: 82,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    InkWell(
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(14),
                      child: Hero(tag: 'art', child: Art(t.thumbnail, size: 66, radius: 14)),
                    ),
                    const SizedBox(width: 14),
                    Flexible(child: _SwitchingTitle(t, titleSize: 15, artistSize: 13)),
                    LikeButton(c: c, t: t, size: 20),
                  ],
                ),
              ),
              SizedBox(
                width: 500,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 300, child: TransportControls(c: c, scale: 0.6)),
                    SeekBar(c: c, seed: t.id, fallback: t.duration, compact: true),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(tooltip: 'Lyrics', icon: const Icon(Icons.lyrics_rounded), onPressed: () => openLyrics(context, c)),
                    IconButton(tooltip: 'Up next', icon: const Icon(Icons.queue_music_rounded), onPressed: () => showQueueSheet(context, c)),
                    _VolumeSlider(player: c.player),
                    IconButton(tooltip: 'Now playing', icon: const Icon(Icons.open_in_full_rounded, size: 20), onPressed: onOpen),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final AudioPlayer player;

  const _VolumeSlider({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.volumeStream,
      builder: (ctx, snap) {
        final volume = snap.data ?? player.volume;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(volume == 0 ? Icons.volume_off_rounded : VortexStyles.current.volumeIcon, size: 20, color: VortexStyles.current.kind == DecorKind.none ? AppColors.subtle : AppColors.accent),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderTheme.of(ctx).copyWith(thumbShape: StyleThumbShape(VortexStyles.current), thumbColor: Colors.white),
                child: Slider(value: volume.clamp(0.0, 1.0), onChanged: player.setVolume),
              ),
            ),
          ],
        );
      },
    );
  }
}

class NowPlayingScreen extends StatelessWidget {
  final PlayerController c;

  const NowPlayingScreen({super.key, required this.c});

  void _optionsSheet<T>(BuildContext context, String title, List<T> options, String Function(T) label, bool Function(T) selected, ValueChanged<T> onPick, {Widget? extra}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF216161C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final o in options)
              ListTile(
                title: Text(label(o), style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: selected(o) ? Icon(Icons.check_rounded, color: AppColors.accent) : null,
                onTap: () {
                  onPick(o);
                  Navigator.pop(ctx);
                },
              ),
            ?extra,
          ],
        ),
      ),
    );
  }

  void _sleepSheet(BuildContext context) {
    _optionsSheet<int>(
      context,
      'Sleep timer',
      const [15, 30, 45, 60, 90],
      (m) => '$m minutes',
      (_) => false,
      (m) => c.setSleepTimer(Duration(minutes: m)),
      extra: c.sleepAt == null
          ? null
          : Builder(
              builder: (ctx) => ListTile(
                title: Text('Turn off timer', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                onTap: () {
                  c.setSleepTimer(null);
                  Navigator.pop(ctx);
                },
              ),
            ),
    );
  }

  void _speedSheet(BuildContext context) {
    _optionsSheet<double>(context, 'Playback speed', const [0.75, 1.0, 1.25, 1.5, 2.0], (s) => '${s}x', (s) => c.speed == s, c.setSpeed);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.current;
        if (t == null) return const SizedBox.shrink();
        final wide = isWide(context);
        return ValueListenableBuilder<Color>(
          valueListenable: c.tint,
          builder: (context, tint, _) => Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              fit: StackFit.expand,
              children: [
                AppBackdrop(c: c),
                SafeArea(
                  child: Column(
                    children: [
                      _Header(onBack: () => Navigator.pop(context), onUpNext: wide ? null : () => showQueueSheet(context, c)),
                      Expanded(child: wide ? _wideBody(context, t, tint) : _phoneBody(context, t, tint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _details(Track t, Color tint) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                child: Column(
                  key: ValueKey(t.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                    const SizedBox(height: 2),
                    Builder(
                      builder: (ctx) => InkWell(
                        onTap: () => openArtistForTrack(ctx, c, t),
                        child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0xCCFFFFFF), fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            LikeButton(c: c, t: t, size: 28),
          ],
        ),
        const SizedBox(height: 10),
        SeekBar(c: c, seed: t.id, fallback: t.duration),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(c.error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF7B7B), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 6),
        TransportControls(c: c, glow: tint),
      ],
    );
  }

  Widget _pills(BuildContext context, Track t, {required bool showUpNext}) {
    return Row(
      children: [
        Expanded(child: _Pill(Icons.lyrics_rounded, 'Lyrics', () => openLyrics(context, c))),
        const SizedBox(width: 8),
        if (showUpNext) ...[
          Expanded(child: _Pill(Icons.queue_music_rounded, 'Up next', () => showQueueSheet(context, c))),
          const SizedBox(width: 8),
        ],
        Expanded(child: _Pill(Icons.bedtime_rounded, c.sleepAt == null ? 'Timer' : 'Timer on', () => _sleepSheet(context), active: c.sleepAt != null)),
        const SizedBox(width: 8),
        Expanded(child: _Pill(Icons.speed_rounded, c.speed == 1 ? 'Speed' : '${c.speed}x', () => _speedSheet(context), active: c.speed != 1)),
        const SizedBox(width: 8),
        Expanded(child: _Pill(Icons.more_horiz_rounded, 'More', () => showTrackActions(context, c, t, () => c.player.seek(Duration.zero)))),
      ],
    );
  }

  Widget _phoneBody(BuildContext context, Track t, Color tint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (ctx, box) {
          final size = min(box.maxWidth - 24, max(box.maxHeight - 330, 140.0));
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CoverStage(c: c, t: t, size: size, tint: tint),
                  _details(t, tint),
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: _pills(context, t, showUpNext: true)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _wideBody(BuildContext context, Track t, Color tint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, box) {
                final size = min(min(box.maxWidth - 80, 460.0), max(box.maxHeight - 400, 160.0));
                return Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: size + 40, child: Center(child: CoverStage(c: c, t: t, size: size, tint: tint))),
                          const SizedBox(height: 12),
                          _details(t, tint),
                          const SizedBox(height: 14),
                          _pills(context, t, showUpNext: false),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 32),
          SizedBox(
            width: 390,
            child: Glass(radius: 24, opacity: 0.06, child: Material(color: Colors.transparent, child: UpNextList(c: c))),
          ),
        ],
      ),
    );
  }
}

class CoverStage extends StatelessWidget {
  final PlayerController c;
  final Track t;
  final double size;
  final Color tint;

  const CoverStage({super.key, required this.c, required this.t, required this.size, required this.tint});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: c.player.playingStream,
      initialData: c.player.playing,
      builder: (ctx, snap) {
        final playing = snap.data ?? false;
        return GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200 && c.hasNext) c.next();
            if (v > 200) c.previous();
          },
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (c.showRing)
                Positioned(
                  left: -size * 0.15,
                  top: -size * 0.15,
                  width: size * 1.3,
                  height: size * 1.3,
                  child: IgnorePointer(child: VortexRing(size: size * 1.3, tint: tint, active: playing)),
                ),
              AnimatedScale(
                scale: playing ? 1 : 0.9,
                duration: const Duration(milliseconds: 480),
                curve: Curves.easeOutBack,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                                            const BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 18)),
                    ],
                  ),
                  child: Hero(
                    tag: 'art',
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 340),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: Tween(begin: 0.93, end: 1.0).animate(anim), child: child),
                      ),
                      child: Art(t.artUrl, key: ValueKey(t.id), size: size, radius: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onUpNext;

  const _Header({required this.onBack, required this.onUpNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(tooltip: 'Back', icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: onBack),
            ),
          ),
          const Text('Now playing', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: onUpNext == null
                  ? const SizedBox.shrink()
                  : TextButton.icon(
                      onPressed: onUpNext,
                      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                      icon: const Icon(Icons.queue_music_rounded, size: 18),
                      label: const Text('Up next', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _Pill(this.icon, this.label, this.onTap, {this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : Colors.white;
    return Glass(
      radius: 8,
      blur: 14,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SeekBar extends StatefulWidget {
  final PlayerController c;
  final String seed;
  final int? fallback;
  final bool compact;

  const SeekBar({super.key, required this.c, required this.seed, required this.fallback, this.compact = false});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = widget.c.player;
    const timeStyle = TextStyle(fontSize: 12, color: Color(0xB3FFFFFF), fontFeatures: [FontFeature.tabularFigures()]);
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (ctx, snap) {
        final total = player.duration ?? Duration(seconds: widget.fallback ?? 0);
        final totalMs = total.inMilliseconds < 1 ? 1 : total.inMilliseconds;
        final live = (snap.data?.inMilliseconds ?? 0) / totalMs;
        final progress = (_drag ?? live).clamp(0.0, 1.0);
        final posMs = (progress * totalMs).toInt();
        final elapsed = formatDuration(Duration(milliseconds: posMs));
        final remaining = '-${formatDuration(Duration(milliseconds: totalMs - posMs))}';
        void onEnd(double v) {
          player.seek(Duration(milliseconds: (v * totalMs).toInt()));
          setState(() => _drag = null);
        }

        final wave = widget.c.showWave
            ? WaveSeekBar(
                seed: widget.seed,
                progress: progress,
                height: widget.compact ? 24 : 48,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: onEnd,
              )
            : SliderTheme(
                data: SliderTheme.of(ctx).copyWith(thumbShape: StyleThumbShape(VortexStyles.current)),
                child: Slider(value: progress, onChanged: (v) => setState(() => _drag = v), onChangeEnd: onEnd),
              );
        if (widget.compact) {
          return Row(
            children: [
              Text(elapsed, style: timeStyle),
              const SizedBox(width: 10),
              Expanded(child: wave),
              const SizedBox(width: 10),
              Text(remaining, style: timeStyle),
            ],
          );
        }
        return Column(
          children: [
            wave,
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(elapsed, style: timeStyle), Text(remaining, style: timeStyle)],
            ),
          ],
        );
      },
    );
  }
}
