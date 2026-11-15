import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'fx.dart';
import 'models.dart';
import 'player_controller.dart';
import 'playlists.dart';
import 'theme.dart';

class Art extends StatelessWidget {
  final String url;
  final double size;
  final double radius;

  const Art(this.url, {super.key, required this.size, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        Api.instance.artUrl(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: AppColors.card,
          child: Icon(Icons.music_note, color: AppColors.subtle, size: size * 0.45),
        ),
      ),
    );
  }
}

class PlayingIndicator extends StatelessWidget {
  final PlayerController c;
  final Color? color;

  const PlayingIndicator({super.key, required this.c, this.color});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: c.player.playingStream,
      initialData: c.player.playing,
      builder: (ctx, snap) => EqualizerBars(size: 16, color: color ?? AppColors.accent, active: snap.data ?? false),
    );
  }
}

class TrackPress extends StatefulWidget {
  final Track track;
  final PlayerController c;
  final VoidCallback onTap;
  final Widget child;
  final double radius;

  const TrackPress({super.key, required this.track, required this.c, required this.onTap, required this.child, this.radius = 8});

  @override
  State<TrackPress> createState() => _TrackPressState();
}

class _TrackPressState extends State<TrackPress> {
  bool _pressed = false;

  void _showActions() {
    HapticFeedback.mediumImpact();
    showTrackActions(context, widget.c, widget.track, widget.onTap);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.radius),
        onTap: widget.onTap,
        onLongPress: _showActions,
        onSecondaryTap: _showActions,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        child: widget.child,
      ),
    );
  }
}

class TrackTile extends StatelessWidget {
  final Track track;
  final PlayerController c;
  final VoidCallback onTap;

  const TrackTile({super.key, required this.track, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final playing = c.current?.id == track.id;
    return TrackPress(
      track: track,
      c: c,
      onTap: onTap,
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Art(track.thumbnail, size: 52, radius: 10),
                if (playing)
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(10)),
                    child: PlayingIndicator(c: c),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: playing ? AppColors.accent : Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [track.artist, if (track.album != null) track.album].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.subtle, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz, color: AppColors.subtle),
              onPressed: () => showTrackActions(context, c, track, onTap),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTrackActions(BuildContext context, PlayerController c, Track track, VoidCallback onPlay) {
  final messenger = ScaffoldMessenger.of(context);
  void notify(String text) {
    messenger.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 1), width: 260));
  }

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      void act(VoidCallback action) {
        Navigator.of(ctx).pop();
        action();
      }

      final liked = c.isLiked(track);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 16))],
                      ),
                      child: Art(track.artUrl, size: 220, radius: 20),
                    ),
                    const SizedBox(height: 16),
                    Text(track.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(track.artist, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xE624242C), borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _ActionRow(Icons.play_arrow_rounded, 'Play now', () => act(onPlay)),
                          _ActionRow(Icons.playlist_play_rounded, 'Play next', () => act(() {
                                c.playNext(track);
                                notify('Playing next');
                              })),
                          _ActionRow(Icons.queue_music_rounded, 'Add to queue', () => act(() {
                                c.addToQueue(track);
                                notify('Added to queue');
                              })),
                          _ActionRow(Icons.playlist_add_rounded, 'Add to playlist', () {
                            Navigator.of(ctx).pop();
                            showAddToPlaylist(context, c, track);
                          }),
                          _ActionRow(
                            liked ? Icons.favorite : Icons.favorite_border,
                            liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                            () => act(() => c.toggleLike(track)),
                            color: liked ? AppColors.accent : Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.88, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionRow(this.icon, this.label, this.onTap, {this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}
