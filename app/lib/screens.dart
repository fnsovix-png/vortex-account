import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'artist.dart';
import 'branding.dart';
import 'fx.dart';
import 'models.dart';
import 'player_controller.dart';
import 'playlists.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

const _sections = [
  ('Today\'s top hits', 'top hits 2026'),
  ('Throwback classics', 'michael jackson'),
  ('Chill vibes', 'chill lofi'),
  ('Hip-hop essentials', 'hip hop hits'),
];

const _genres = [
  ('Pop', Color(0xFFB14CFF), Color(0xFF5B21B6), Icons.auto_awesome_rounded),
  ('Hip-Hop', Color(0xFFFF8A00), Color(0xFF9A3412), Icons.mic_external_on_rounded),
  ('Rock', Color(0xFFFF2D6F), Color(0xFF7F1D3F), Icons.bolt_rounded),
  ('R&B', Color(0xFF4F7CFF), Color(0xFF1E2A78), Icons.nightlife_rounded),
  ('Latin', Color(0xFF00B8D9), Color(0xFF0B5A8A), Icons.celebration_rounded),
  ('Electronic', Color(0xFF29E37A), Color(0xFF0B6B3C), Icons.graphic_eq_rounded),
  ('K-Pop', Color(0xFFFF5470), Color(0xFF8A1C5C), Icons.favorite_rounded),
  ('Jazz', Color(0xFFC9A36A), Color(0xFF5B3A1E), Icons.piano_rounded),
  ('Lo-fi', Color(0xFF6EC6D9), Color(0xFF28536B), Icons.coffee_rounded),
  ('Anime', Color(0xFFFF4FD8), Color(0xFF7E1FA8), Icons.star_rounded),
];

double shellBottomPad(BuildContext context, PlayerController c) {
  if (isWide(context)) return 24;
  return (c.current == null ? 96 : 176) + MediaQuery.paddingOf(context).bottom;
}

class HomeScreen extends StatefulWidget {
  final PlayerController c;

  const HomeScreen({super.key, required this.c});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, List<Track>> _data = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _error = null);
    await widget.c.prepareServer();
    for (final s in _sections) {
      try {
        final tracks = await widget.c.api.search(s.$2, limit: 12);
        if (mounted) setState(() => _data[s.$1] = tracks);
      } catch (e) {
        if (mounted) setState(() => _error = 'Couldn\'t load music. Check your internet connection.');
      }
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final wide = isWide(context);
    final quick = [...c.recent, ...c.liked.where((l) => !c.recent.any((r) => r.id == l.id))].take(6).toList();
    final firstShelf = _data[_sections.first.$1];
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.accent,
      child: CustomScrollView(
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 18, wide ? 20 : 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!wide) ...[const VortexWordmark(height: 13), const SizedBox(height: 10)],
                          Text(
                            (c.profile?.username ?? '').isEmpty ? _greeting : '$_greeting, ${c.profile!.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: wide ? 38 : 28, letterSpacing: -1.2, height: 1.05),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Profile',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => openProfile(context, c),
                        child: ProfileAvatar(c: c, size: 44),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 18, vertical: 8),
                child: Glass(
                  radius: 8,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Color(0xFFFF7B7B)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ),
            ),
          if (quick.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 18, wide ? 28 : 18, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 60,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => FadeSlideIn(index: i, child: _QuickTile(track: quick[i], c: c, onTap: () => c.playList(quick, i))),
                  childCount: quick.length,
                ),
              ),
            ),
          for (final s in c.shelves)
            SliverToBoxAdapter(child: _Shelf(title: s.title, tracks: s.tracks, c: c)),
          if (c.topArtists.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ShelfTitle('Your top artists'),
                  TopArtistsRow(
                    c: c,
                    padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 18),
                    onTap: (a) => c.requestSearch(a.name),
                  ),
                ],
              ),
            ),
          SliverToBoxAdapter(child: _RankedShelf(title: _sections.first.$1, tracks: firstShelf, c: c)),
          for (final s in _sections.skip(1))
            SliverToBoxAdapter(child: _Shelf(title: s.$1, tracks: _data[s.$1], c: c)),
          SliverToBoxAdapter(child: SizedBox(height: shellBottomPad(context, c))),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final Track track;
  final PlayerController c;
  final VoidCallback onTap;

  const _QuickTile({required this.track, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final current = c.current?.id == track.id;
    return Glass(
      radius: 8,
      blur: 12,
      child: Material(
        color: Colors.transparent,
        child: TrackPress(
          track: track,
          c: c,
          onTap: onTap,
          radius: 8,
          child: Row(
            children: [
              Art(track.thumbnail, size: 60, radius: 0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: current ? AppColors.accent : Colors.white)),
              ),
              if (current) ...[
                const SizedBox(width: 6),
                PlayingIndicator(c: c),
              ],
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfTitle extends StatelessWidget {
  final String title;

  const _ShelfTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final side = isWide(context) ? 28.0 : 18.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 28, side, 14),
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
    );
  }
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: isWide(context) ? 28 : 18),
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (_, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer(width: 160, height: 160, radius: 8),
          SizedBox(height: 10),
          Shimmer(width: 120, height: 12, radius: 6),
          SizedBox(height: 6),
          Shimmer(width: 80, height: 10, radius: 5),
        ],
      ),
    );
  }
}

class _TrackCard extends StatefulWidget {
  final Track track;
  final PlayerController c;
  final VoidCallback onTap;
  double get size => c.cardSize;

  const _TrackCard({required this.track, required this.c, required this.onTap});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final current = widget.c.current?.id == t.id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TrackPress(
        track: t,
        c: widget.c,
        onTap: widget.onTap,
        radius: 8,
        child: SizedBox(
          width: widget.size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Color(_hover ? 0x99000000 : 0x55000000), blurRadius: _hover ? 26 : 14, offset: const Offset(0, 10))],
                ),
                child: Stack(
                  children: [
                    Art(t.artUrl, size: widget.size, radius: 8),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: AnimatedOpacity(
                        opacity: _hover || current ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedScale(
                          scale: _hover || current ? 1 : 0.7,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 12, offset: Offset(0, 4))],
                            ),
                            child: current ? PlayingIndicator(c: widget.c, color: Colors.black) : const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: current ? AppColors.accent : Colors.white)),
              const SizedBox(height: 1),
              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  final String title;
  final List<Track>? tracks;
  final PlayerController c;

  const _Shelf({required this.title, required this.tracks, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShelfTitle(title),
        SizedBox(
          height: c.cardSize + 66,
          child: tracks == null
              ? const _ShelfSkeleton()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: isWide(context) ? 28 : 18),
                  itemCount: tracks!.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (ctx, i) => FadeSlideIn(
                    index: i,
                    child: _TrackCard(track: tracks![i], c: c, onTap: () => c.playList(tracks!, i)),
                  ),
                ),
        ),
      ],
    );
  }
}

class _RankedShelf extends StatelessWidget {
  final String title;
  final List<Track>? tracks;
  final PlayerController c;

  const _RankedShelf({required this.title, required this.tracks, required this.c});

  @override
  Widget build(BuildContext context) {
    final ranked = tracks?.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShelfTitle(title),
        SizedBox(
          height: c.cardSize + 66,
          child: ranked == null
              ? const _ShelfSkeleton()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: isWide(context) ? 28 : 18),
                  itemCount: ranked.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) => FadeSlideIn(
                    index: i,
                    child: SizedBox(
                      width: c.cardSize + 54,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 42,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 120,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -8,
                                foreground: Paint()
                                  ..style = PaintingStyle.stroke
                                  ..strokeWidth = 2.5
                                  ..color = const Color(0x80FFFFFF),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 54,
                            top: 0,
                            child: _TrackCard(track: ranked[i], c: c, onTap: () => c.playList(ranked, i)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  final PlayerController c;

  const SearchScreen({super.key, required this.c});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Track> _results = [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;
  int _suggestId = 0;
  List<String> _suggestions = [];
  List<ArtistCard> _artists = [];
  List<AlbumCard> _albums = [];

  @override
  void initState() {
    super.initState();
    widget.c.searchRequest.addListener(_onSearchRequest);
  }

  @override
  void dispose() {
    widget.c.searchRequest.removeListener(_onSearchRequest);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchRequest() {
    final q = widget.c.searchRequest.value;
    if (q != null) _searchFor(q);
  }

  Future<void> _loadSuggestions(String q) async {
    final id = ++_suggestId;
    try {
      final s = await widget.c.api.suggest(q);
      if (mounted && id == _suggestId) setState(() => _suggestions = s.where((e) => e.toLowerCase() != q.trim().toLowerCase()).toList());
    } catch (_) {}
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().isEmpty) {
      _requestId++;
      _suggestId++;
      setState(() {
        _results = [];
        _artists = [];
        _albums = [];
        _suggestions = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(q);
      _run(q);
    });
  }

  void _pickSuggestion(String q) {
    _debounce?.cancel();
    _suggestId++;
    _controller.text = q;
    setState(() => _suggestions = []);
    _run(q);
  }

  Widget _suggestionChips(double side) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side, vertical: 4),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => FadeSlideIn(
          index: i,
          child: Glass(
            radius: 8,
            blur: 10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _pickSuggestion(_suggestions[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.north_east_rounded, size: 14, color: AppColors.subtle),
                      const SizedBox(width: 6),
                      Text(_suggestions[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _run(String q) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      widget.c.api.browseSearch(q).then((value) {
        if (mounted && id == _requestId) {
          setState(() {
            _artists = value.$1;
            _albums = value.$2;
          });
        }
      }).catchError((_) {});
      final r = await widget.c.api.search(q);
      if (mounted && id == _requestId) setState(() => _results = r);
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = 'Couldn\'t search right now. Try again.');
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  void _searchFor(String q) {
    _controller.text = q;
    _onChanged(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final empty = _controller.text.trim().isEmpty;
    final side = isWide(context) ? 28.0 : 18.0;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 18, side, 12),
            child: const Text('Search', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Glass(
              radius: 8,
              opacity: 0.1,
              child: Material(
                color: Colors.transparent,
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  onSubmitted: _run,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Songs, artists, albums',
                    hintStyle: const TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w500),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white),
                    suffixIcon: empty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => _searchFor('')),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_suggestions.isNotEmpty) _suggestionChips(side),
          SizedBox(
            height: 2,
            child: _loading ? LinearProgressIndicator(color: AppColors.accent, backgroundColor: Colors.transparent, minHeight: 2) : null,
          ),
          if (_error != null)
            Padding(padding: EdgeInsets.symmetric(horizontal: side, vertical: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF7B7B), fontWeight: FontWeight.w600))),
          Expanded(child: empty ? _browse(side) : _resultsList(c, side)),
        ],
      ),
    );
  }

  Widget _resultsList(PlayerController c, double side) {
    if (_results.isEmpty) {
      return Center(
        child: Text(_loading ? 'Searching...' : 'No results', style: const TextStyle(color: AppColors.subtle)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: shellBottomPad(context, c)),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(side, 8, side, 12),
                child: FadeSlideIn(child: _TopResult(track: _results.first, c: c, onTap: () => c.playList(_results, 0))),
              ),
              if (_artists.isNotEmpty) ...[
                const _ShelfTitle('Artists'),
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: side),
                    itemCount: _artists.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (ctx, a) => ArtistTile(c: c, artist: _artists[a]),
                  ),
                ),
              ],
              if (_albums.isNotEmpty) ...[
                const _ShelfTitle('Albums'),
                SizedBox(
                  height: 208,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: side),
                    itemCount: _albums.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (ctx, a) => AlbumTile(c: c, album: _albums[a]),
                  ),
                ),
              ],
              const _ShelfTitle('Songs'),
            ],
          );
        }
        return FadeSlideIn(
          index: i,
          child: TrackTile(track: _results[i], c: c, onTap: () => c.playList(_results, i)),
        );
      },
    );
  }

  Widget _browse(double side) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 12, side, 14),
          sliver: const SliverToBoxAdapter(child: Text('Browse all', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4))),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              childAspectRatio: 1.55,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => FadeSlideIn(index: i, child: _GenreTile(genre: _genres[i], onTap: () => _searchFor('${_genres[i].$1} hits'))),
              childCount: _genres.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: shellBottomPad(context, widget.c))),
      ],
    );
  }
}

class _TopResult extends StatelessWidget {
  final Track track;
  final PlayerController c;
  final VoidCallback onTap;

  const _TopResult({required this.track, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 10,
      child: Material(
        color: Colors.transparent,
        child: TrackPress(
          track: track,
          c: c,
          onTap: onTap,
          radius: 10,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Art(track.artUrl, size: 96, radius: 16),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top result', style: TextStyle(color: AppColors.subtle, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
                      const SizedBox(height: 3),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreTile extends StatelessWidget {
  final (String, Color, Color, IconData) genre;
  final VoidCallback onTap;

  const _GenreTile({required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: Color.lerp(genre.$3, AppColors.card, 0.25),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(genre.$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  final PlayerController c;

  const LibraryScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final side = isWide(context) ? 28.0 : 18.0;
    return DefaultTabController(
      length: 3,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, 18, side, 12),
              child: const Text('Your Library', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                labelColor: Colors.black,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                unselectedLabelColor: Colors.white,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                splashBorderRadius: BorderRadius.circular(20),
                tabs: const [Tab(height: 38, text: 'Playlists'), Tab(height: 38, text: 'Liked Songs'), Tab(height: 38, text: 'Recent')],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                children: [
                  _playlists(context, side),
                  _list(context, c.liked, 'Liked Songs', Icons.favorite_rounded, const [Color(0xFF2FBF71), Color(0xFF0E5C38)], 'No liked songs yet', 'Press and hold any song to save it.'),
                  _list(context, c.recent, 'Recently played', Icons.history_rounded, const [Color(0xFF7C5CFF), Color(0xFF2E1F8F)], 'Nothing played yet', 'Songs you play will show up here.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlists(BuildContext context, double side) {
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 4, side, shellBottomPad(context, c)),
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final name = await askPlaylistName(context);
            if (name == null || name.isEmpty) return;
            final created = await c.createPlaylist(name);
            if (context.mounted) openPlaylist(context, c, created.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add_rounded),
                ),
                const SizedBox(width: 14),
                const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ),
        for (final p in c.playlists)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => openPlaylist(context, c, p.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  PlaylistCover(c: c, playlist: p, size: 56, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(p.tracks.length == 1 ? '1 song' : '${p.tracks.length} songs', style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _list(BuildContext context, List<Track> tracks, String title, IconData icon, List<Color> colors, String emptyTitle, String emptyText) {
    final side = isWide(context) ? 28.0 : 18.0;
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: const Color(0x55FFFFFF)),
              const SizedBox(height: 14),
              Text(emptyTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.subtle)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: shellBottomPad(context, c)),
      itemCount: tracks.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(side, 6, side, 12),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 44, color: const Color(0xE6FFFFFF)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        Text(tracks.length == 1 ? '1 song' : '${tracks.length} songs', style: const TextStyle(color: Color(0xE6FFFFFF), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: c.shuffle ? 'Shuffle on' : 'Shuffle off',
                    icon: Icon(Icons.shuffle_rounded, color: c.shuffle ? AppColors.accent : Colors.white),
                    onPressed: c.toggleShuffle,
                  ),
                  IconButton.filled(
                    tooltip: 'Play',
                    iconSize: 30,
                    style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => c.playList(tracks, 0),
                  ),
                ],
              ),
            ),
          );
        }
        final index = i - 1;
        return FadeSlideIn(
          index: index,
          child: TrackTile(track: tracks[index], c: c, onTap: () => c.playList(tracks, index)),
        );
      },
    );
  }
}

Future<void> showServerDialog(BuildContext context, PlayerController c) async {
  final server = TextEditingController(text: c.api.server);
  final isPhone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  final Pairing? pairing = isPhone ? null : await c.api.pairing();
  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Vortex server', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: server, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://...')),
              const SizedBox(height: 6),
              const Text('Changing this signs you out.', style: TextStyle(color: AppColors.subtle, fontSize: 12)),
              if (pairing != null) ...[
                const SizedBox(height: 16),
                _CopyRow('Address on this network', pairing.url),
                _CopyRow('Get the app', '${pairing.url}/download'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  final value = server.text.trim().replaceAll(RegExp(r'/+$'), '');
  if (saved == true && value.isNotEmpty && value != c.api.server) {
    c.setServer(value);
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;

  const _CopyRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText('$label: $value', style: const TextStyle(fontSize: 13, color: AppColors.subtle)),
        ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ],
    );
  }
}
