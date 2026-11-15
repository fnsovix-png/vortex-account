import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

void openPlaylist(BuildContext context, PlayerController c, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistScreen(c: c, id: id)));
}

Future<String?> askPlaylistName(BuildContext context, {String initial = '', String title = 'New playlist'}) {
  final name = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: name,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        decoration: const InputDecoration(hintText: 'Playlist name', counterText: ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

Future<void> showAddToPlaylist(BuildContext context, PlayerController c, Track track) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Add to playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const SizedBox(width: 44, height: 44, child: Icon(Icons.add_rounded)),
              title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final name = await askPlaylistName(ctx);
                if (name == null || name.isEmpty) return;
                try {
                  final created = await c.createPlaylist(name);
                  await c.addToPlaylist(created.id, track);
                  messenger.showSnackBar(SnackBar(content: Text('Added to $name'), width: 280));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e'), width: 300));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            for (final p in c.playlists)
              ListTile(
                leading: PlaylistCover(c: c, playlist: p, size: 44, radius: 6),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_count(p.tracks.length)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await c.addToPlaylist(p.id, track);
                    messenger.showSnackBar(SnackBar(content: Text('Added to ${p.name}'), width: 280));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e'), width: 300));
                  }
                },
              ),
          ],
        ),
      ),
    ),
  );
}

String _count(int n) => n == 1 ? '1 song' : '$n songs';

class PlaylistCover extends StatelessWidget {
  final PlayerController c;
  final Playlist playlist;
  final double size;
  final double radius;

  const PlaylistCover({super.key, required this.c, required this.playlist, required this.size, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final version = playlist.cover;
    final Widget child;
    if (version != null) {
      child = Image.network(c.api.playlistCoverUrl(playlist.id, version), key: ValueKey(version), width: size, height: size, fit: BoxFit.cover, cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil());
    } else {
      final art = playlist.tracks.map((t) => t.thumbnail).where((t) => t.isNotEmpty).toSet().take(4).toList();
      if (art.length >= 4) {
        final cell = size / 2;
        child = Wrap(children: [for (final a in art) Art(a, size: cell, radius: 0)]);
      } else if (art.isNotEmpty) {
        child = Art(art.first, size: size, radius: 0);
      } else {
        child = ColoredBox(
          color: AppColors.card,
          child: SizedBox(width: size, height: size, child: Icon(Icons.music_note_rounded, size: size * 0.42, color: AppColors.subtle)),
        );
      }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: size, height: size, child: child));
  }
}

class PlaylistScreen extends StatefulWidget {
  final PlayerController c;
  final String id;

  const PlaylistScreen({super.key, required this.c, required this.id});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), width: 300));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Playlist p) async {
    final name = await askPlaylistName(context, initial: p.name, title: 'Rename playlist');
    if (name != null && name.isNotEmpty && name != p.name) _run(() => widget.c.renamePlaylist(p.id, name));
  }

  Future<void> _delete(Playlist p) async {
    final navigator = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete ${p.name}?', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('The songs stay on Vortex. Only this playlist goes away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => widget.c.deletePlaylist(p.id));
    navigator.pop();
  }

  void _setCover(Playlist p, Uint8List bytes) => _run(() => widget.c.setPlaylistCover(p.id, bytes));

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = c.playlists.where((x) => x.id == widget.id).firstOrNull;
        if (p == null) return const Scaffold(backgroundColor: AppColors.background);
        final wide = isWide(context);
        final coverSize = wide ? 200.0 : 180.0;
        final cover = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ImageDropZone(
            onImage: (b) => _setCover(p, b),
            builder: (active) => Stack(
              children: [
                PlaylistCover(c: c, playlist: p, size: coverSize, radius: 0),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: active ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: const ColoredBox(
                        color: Color(0xB3000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded),
                              SizedBox(height: 4),
                              Text('Change cover', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        final info = Column(
          crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _rename(p),
              child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: wide ? TextAlign.start : TextAlign.center, style: TextStyle(fontSize: wide ? 40 : 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1)),
            ),
            const SizedBox(height: 4),
            Text(_count(p.tracks.length), style: const TextStyle(color: AppColors.subtle)),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  tooltip: 'Play',
                  iconSize: 28,
                  style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: p.tracks.isEmpty ? null : () => c.playList(p.tracks, 0),
                ),
                IconButton(tooltip: 'Shuffle', icon: const Icon(Icons.shuffle_rounded), onPressed: p.tracks.isEmpty ? null : () => c.shufflePlay(p.tracks)),
                IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_rounded), onPressed: () => _rename(p)),
                if (p.cover != null) IconButton(tooltip: 'Remove cover', icon: const Icon(Icons.hide_image_rounded), onPressed: () => _run(() => c.removePlaylistCover(p.id))),
                IconButton(tooltip: 'Delete playlist', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(p)),
              ],
            ),
          ],
        );
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AppBackdrop(c: c),
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, MediaQuery.paddingOf(context).top + 60, wide ? 32 : 18, 18),
                      child: wide
                          ? Row(children: [cover, const SizedBox(width: 24), Expanded(child: info)])
                          : Column(children: [cover, const SizedBox(height: 16), info]),
                    ),
                  ),
                  if (p.tracks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Press and hold any song, then choose Add to playlist.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.subtle)),
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: p.tracks.length,
                      itemBuilder: (ctx, i) => Row(
                        children: [
                          Expanded(child: TrackTile(track: p.tracks[i], c: c, onTap: () => c.playList(p.tracks, i))),
                          IconButton(tooltip: 'Remove from playlist', icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.subtle), onPressed: () => _run(() => c.removeFromPlaylist(p.id, p.tracks[i].id))),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom)),
                ],
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                  ),
                ),
              ),
              if (_busy) Align(alignment: Alignment.topCenter, child: LinearProgressIndicator(minHeight: 2, color: AppColors.accent, backgroundColor: Colors.transparent)),
            ],
          ),
        );
      },
    );
  }
}
