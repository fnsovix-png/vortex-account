import 'package:flutter/material.dart';

import 'fx.dart';
import 'models.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

void openArtist(BuildContext context, PlayerController c, String id, String name) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(c: c, id: id, name: name)));
}

void openAlbum(BuildContext context, PlayerController c, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(c: c, id: id)));
}

Future<void> openArtistForTrack(BuildContext context, PlayerController c, Track t) async {
  final name = t.artist.split(', ').first;
  final id = t.artistId;
  if (id != null) {
    openArtist(context, c, id, name);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final (artists, _) = await c.api.browseSearch(name);
    if (!context.mounted) return;
    if (artists.isEmpty) throw 'none';
    openArtist(context, c, artists.first.id, artists.first.name);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text('Couldn\'t find $name'), width: 280));
  }
}

class _PageShell extends StatelessWidget {
  final PlayerController c;
  final Future<Object?> future;
  final Widget Function(BuildContext context, Object? data) builder;

  const _PageShell({required this.c, required this.future, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            AppBackdrop(c: c),
            FutureBuilder<Object?>(
              future: future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('Couldn\'t load this page', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)));
                }
                if (!snap.hasData) return Center(child: EqualizerBars(size: 34, color: AppColors.accent));
                return builder(context, snap.data);
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Glass(
                    radius: 22,
                    blur: 12,
                    child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String art;
  final double radius;
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback? onSubtitle;

  const _Header({required this.art, required this.radius, required this.label, required this.title, required this.subtitle, this.onPlay, this.onShuffle, this.onSubtitle});

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final top = MediaQuery.paddingOf(context).top;
    final info = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: wide ? TextAlign.start : TextAlign.center, style: TextStyle(fontSize: wide ? 44 : 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.08)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onSubtitle,
          child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: wide ? TextAlign.start : TextAlign.center, style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onShuffle,
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white),
              label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ],
    );
    final cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 36, offset: Offset(0, 16))],
      ),
      child: Art(art, size: wide ? 220 : 190, radius: radius),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 18, top + (wide ? 40 : 60), wide ? 40 : 18, 18),
      child: wide
          ? Row(children: [cover, const SizedBox(width: 28), Expanded(child: info)])
          : Column(children: [cover, const SizedBox(height: 18), info]),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final PlayerController c;
  final Track track;
  final int rank;
  final VoidCallback onTap;

  const _RankedRow({required this.c, required this.track, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final playing = c.current?.id == track.id;
    return TrackPress(
      track: track,
      c: c,
      onTap: onTap,
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: playing
                  ? Center(child: PlayingIndicator(c: c))
                  : Text('$rank', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.subtle, fontSize: 15)),
            ),
            const SizedBox(width: 8),
            Art(track.thumbnail, size: 48, radius: 9),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: playing ? AppColors.accent : Colors.white)),
                  Text(track.album ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
                ],
              ),
            ),
            if (track.duration != null)
              Text(formatDuration(Duration(seconds: track.duration!)), style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class AlbumTile extends StatelessWidget {
  final PlayerController c;
  final AlbumCard album;

  const AlbumTile({super.key, required this.c, required this.album});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openAlbum(context, c, album.id),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Art(album.thumbnail, size: 150, radius: 14),
            const SizedBox(height: 8),
            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              [if (album.year != null) album.year!, if (album.artist.isNotEmpty) album.artist].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.subtle, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class ArtistTile extends StatelessWidget {
  final PlayerController c;
  final ArtistCard artist;

  const ArtistTile({super.key, required this.c, required this.artist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openArtist(context, c, artist.id, artist.name),
      child: SizedBox(
        width: 120,
        child: Column(
          children: [
            Art(artist.thumbnail, size: 120, radius: 60),
            const SizedBox(height: 8),
            Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class ArtistScreen extends StatefulWidget {
  final PlayerController c;
  final String id;
  final String name;

  const ArtistScreen({super.key, required this.c, required this.id, required this.name});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late final Future<ArtistPage> _page = widget.c.api.artist(widget.id);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return _PageShell(
      c: c,
      future: _page,
      builder: (context, data) {
        final page = data as ArtistPage;
        final bottom = 40 + MediaQuery.paddingOf(context).bottom;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                art: page.thumbnail,
                radius: 110,
                label: 'Artist',
                title: page.name,
                subtitle: '${page.songs.length} songs • ${page.albums.length} albums',
                onPlay: page.songs.isEmpty ? null : () => c.playList(page.songs, 0),
                onShuffle: page.songs.isEmpty ? null : () => c.shufflePlay(page.songs),
              ),
            ),
            if (page.albums.isNotEmpty) ...[
              const SliverToBoxAdapter(child: _Title('Albums')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 208,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: page.albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (ctx, i) => AlbumTile(c: c, album: page.albums[i]),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: _Title('Top songs')),
            SliverList.builder(
              itemCount: page.songs.length,
              itemBuilder: (ctx, i) => _RankedRow(c: c, track: page.songs[i], rank: i + 1, onTap: () => c.playList(page.songs, i)),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
      },
    );
  }
}

class AlbumScreen extends StatefulWidget {
  final PlayerController c;
  final String id;

  const AlbumScreen({super.key, required this.c, required this.id});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final Future<AlbumPage> _page = widget.c.api.album(widget.id);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return _PageShell(
      c: c,
      future: _page,
      builder: (context, data) {
        final page = data as AlbumPage;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                art: page.thumbnail,
                radius: 8,
                label: 'Album',
                title: page.title,
                subtitle: [page.artist, if (page.year != null) page.year!, '${page.tracks.length} songs'].join(' • '),
                onSubtitle: page.artistId == null ? null : () => openArtist(context, c, page.artistId!, page.artist),
                onPlay: page.tracks.isEmpty ? null : () => c.playList(page.tracks, 0),
                onShuffle: page.tracks.isEmpty ? null : () => c.shufflePlay(page.tracks),
              ),
            ),
            SliverList.builder(
              itemCount: page.tracks.length,
              itemBuilder: (ctx, i) => _RankedRow(c: c, track: page.tracks[i], rank: i + 1, onTap: () => c.playList(page.tracks, i)),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom)),
          ],
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  final String text;

  const _Title(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Text(text, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
    );
  }
}
