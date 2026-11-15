import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'account.dart';
import 'anilist.dart';
import 'library.dart';
import 'models.dart';
import 'theme.dart';
import 'ui.dart';

class HomeScreen extends StatefulWidget {
  final Account account;
  final void Function({bool playsHere, String? genre}) onDiscover;

  const HomeScreen({super.key, required this.account, required this.onDiscover});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _data;
  List<Media> _native = const [];
  String? _error;
  Color _color = Palette.purple;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await widget.account.loadVerified().catchError((Object _) {});
      final data = await AniList.home();
      final native = await AniList.byIds(widget.account.verified.keys.toList()).catchError((Object _) => const <Media>[]);
      if (mounted) {
        setState(() {
          _data = data;
          _native = native;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _surprise(HomeData data) {
    final seen = <int>{};
    final pool = _native.where((m) => seen.add(m.id)).toList();
    if (pool.isEmpty) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0xE609090F),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _Surprise(account: widget.account, pool: pool),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final data = _data;
    if (_error != null && data == null) return ErrorBox(message: _error!, onRetry: _load);
    if (data == null) {
      return ListView(
        children: [
          Skeleton(height: MediaQuery.sizeOf(context).height * 0.62),
          const SizedBox(height: 30),
          const RowSkeleton(),
          const RowSkeleton(),
        ],
      );
    }
    final heroes = (_native.isNotEmpty ? _native : data.trending).where((m) => m.cover.isNotEmpty).take(6).toList();
    return Ambient(
      color: _color,
      child: Stack(
        children: [
          ListenableBuilder(
        listenable: a,
        builder: (context, _) {
          final watching = a.list.values.where((e) => e.status == 'watching').toList()..sort((x, y) => y.updated - x.updated);
          return RefreshIndicator(
            onRefresh: _load,
            color: Palette.purple,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (heroes.isNotEmpty)
                  _Hero(
                    account: a,
                    items: heroes,
                    onColor: (c) => setState(() => _color = c),
                    onSurprise: () => _surprise(data),
                    onSearch: () => widget.onDiscover(),
                  ),
                if (watching.isNotEmpty) ...[
                  const SectionTitle('Continue watching'),
                  SizedBox(
                    height: 142,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
                      itemCount: watching.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _ContinueTile(account: a, entry: watching[i]),
                    ),
                  ),
                ],
                if (_native.isNotEmpty) ...[
                  SectionTitle('Watch now', subtitle: 'Confirmed playing in the Vortex player', onMore: () => widget.onDiscover(playsHere: true)),
                  AnimeRow(account: a, items: _native, scope: 'native'),
                  _SurpriseBanner(items: _native, onTap: () => _surprise(data)),
                ],
                const SectionTitle('Most popular', subtitle: 'The purple tag marks what plays here'),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
                    itemCount: math.min(10, data.popular.length),
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => RankCard(account: a, media: data.popular[i], rank: i + 1),
                  ),
                ),
                const SectionTitle('Pick a mood'),
                _Moods(data: data, onPick: (genre) => widget.onDiscover(genre: genre)),
                const SectionTitle('Comfort shows', subtitle: 'Gentle ones for slow days'),
                AnimeRow(account: a, items: data.comfort, scope: 'comfort'),
                const SectionTitle('Something funny'),
                AnimeRow(account: a, items: data.laughs, scope: 'laughs'),
                SectionTitle('Trending worldwide', onMore: () => widget.onDiscover()),
                AnimeRow(account: a, items: data.trending, scope: 'trending'),
                const SectionTitle('Airing this season'),
                AnimeRow(account: a, items: data.airing, scope: 'airing'),
                const SectionTitle('Highest rated ever'),
                AnimeRow(account: a, items: data.top, scope: 'top'),
                const SectionTitle('Coming soon'),
                AnimeRow(account: a, items: data.upcoming, scope: 'upcoming'),
              ],
            ),
          );
        },
      ),
          // Keeps the clock readable over whatever scrolls beneath it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + 8,
            child: const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE609090F), Color(0x0009090F)])))),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatefulWidget {
  final Account account;
  final List<Media> items;
  final ValueChanged<Color> onColor;
  final VoidCallback onSurprise;
  final VoidCallback onSearch;

  const _Hero({required this.account, required this.items, required this.onColor, required this.onSurprise, required this.onSearch});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((s) {
      if (s == AnimationStatus.completed && _pages.hasClients) {
        _pages.animateToPage((_index + 1) % widget.items.length, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
      }
    });
    _clock.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onColor(showColor(widget.items.first.color)));
  }

  @override
  void dispose() {
    _clock.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _changed(int i) {
    setState(() => _index = i);
    _clock.forward(from: 0);
    widget.onColor(showColor(widget.items[i].color));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final side = pageSide(context);
    final height = math.min(size.height * 0.7, isWide(context) ? 560.0 : 620.0);
    final m = widget.items[_index];
    final saved = a.entry(m.id) != null;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              if (n.dragDetails != null) _clock.stop();
              return false;
            },
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.62, 1], colors: [Colors.white, Colors.white, Colors.transparent]).createShader(r),
              child: PageView.builder(
              controller: _pages,
              itemCount: widget.items.length,
              onPageChanged: _changed,
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pages,
                builder: (_, child) {
                  final page = _pages.hasClients && _pages.position.haveDimensions ? _pages.page ?? 0 : 0.0;
                  return ClipRect(child: Transform.translate(offset: Offset((page - i) * size.width * 0.3, 0), child: child));
                },
                child: Image.network(isWide(context) ? (widget.items[i].banner ?? widget.items[i].cover) : widget.items[i].cover, fit: BoxFit.cover, alignment: const Alignment(0, -0.4), errorBuilder: (_, _, _) => Container(color: Palette.card)),
              ),
            ),
            ),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.2, 0.45, 0.78, 1],
                  colors: [Color(0xB309090F), Color(0x0009090F), Color(0x0009090F), Color(0xA609090F), Color(0x0009090F)],
                ),
              ),
            ),
          ),
          Positioned(
            left: side,
            right: side - 6,
            top: top + 6,
            child: Row(
              children: [
                const Wordmark(),
                const Spacer(),
                IconButton(tooltip: 'My Library', onPressed: () => go(context, MyLibraryScreen(prefs: a.prefs)), icon: const Icon(Icons.video_library_rounded)),
                IconButton(tooltip: 'Surprise me', onPressed: widget.onSurprise, icon: const Icon(Icons.casino_rounded)),
                IconButton(tooltip: 'Search', onPressed: widget.onSearch, icon: const Icon(Icons.search_rounded)),
              ],
            ),
          ),
          Positioned(
            left: side,
            right: side,
            bottom: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation), child: child),
                  ),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                  child: Column(
                    key: ValueKey(m.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Bebas', fontSize: isWide(context) ? 72 : 54, height: 0.95, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(
                        [if (m.score != null) '${m.score}% liked', if (m.formatLabel.isNotEmpty) m.formatLabel, ...m.genres.take(2)].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xE6FFFFFF), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Palette.background, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => playAnime(context, a, m.id),
                        icon: const Icon(Icons.play_arrow_rounded, size: 26),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(backgroundColor: const Color(0x331C1830), side: const BorderSide(color: Color(0x55FFFFFF)), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => openAnime(context, a, m.id, preview: m),
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                        label: const Text('Details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: saved ? 'On your list' : 'Add to your list',
                      style: IconButton.styleFrom(backgroundColor: const Color(0x331C1830), padding: const EdgeInsets.all(13), side: const BorderSide(color: Color(0x55FFFFFF)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: saved
                          ? null
                          : () => a.setStatus(m, 'planning').catchError((Object _) {
                                if (context.mounted) toast(context, 'Check your internet connection and try again.');
                              }),
                      icon: Icon(saved ? Icons.check_rounded : Icons.add_rounded, color: saved ? Palette.bright : Colors.white),
                    ),
                  ],
                ),
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: _clock,
                  builder: (_, _) => Row(
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(value: i < _index ? 1 : (i == _index ? _clock.value : 0), minHeight: 3, color: Colors.white, backgroundColor: const Color(0x33FFFFFF)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueTile extends StatelessWidget {
  final Account account;
  final ListEntry entry;

  const _ContinueTile({required this.account, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final total = e.episodes;
    return Semantics(
      button: true,
      label: 'Continue ${e.title}',
      child: Pressable(
        onTap: () => playAnime(context, account, e.id),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 250,
            height: 142,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(e.cover, fit: BoxFit.cover, alignment: const Alignment(0, -0.5), cacheWidth: 500, errorBuilder: (_, _, _) => Container(color: Palette.card)),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x0009090F), Color(0xF009090F)]))),
                const Center(child: Icon(Icons.play_circle_fill_rounded, size: 44, color: Colors.white)),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('Episode ${e.progress + 1}', style: const TextStyle(color: Palette.lavender, fontSize: 11.5, fontWeight: FontWeight.w600)),
                      if (total != null && total > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: (e.progress / total).clamp(0.0, 1.0), minHeight: 3, color: Palette.purple, backgroundColor: const Color(0x33FFFFFF)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three fanned posters inviting you to let the app choose.
class _SurpriseBanner extends StatelessWidget {
  final List<Media> items;
  final VoidCallback onTap;

  const _SurpriseBanner({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    final fan = items.take(3).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 26, side, 0),
      child: Semantics(
        button: true,
        label: 'Surprise me',
        child: Pressable(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            height: 130,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Palette.purple, borderRadius: BorderRadius.circular(14)),
            child: Stack(
              children: [
                for (var i = 0; i < fan.length; i++)
                  Positioned(
                    right: 12.0 + (fan.length - 1 - i) * 38,
                    top: 14,
                    child: Transform.rotate(angle: (i - 1) * 0.16, child: Artwork(fan[i].cover, width: 74, height: 108, radius: 8)),
                  ),
                const Positioned(
                  left: 18,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CAN\'T PICK?', style: TextStyle(fontFamily: 'Bebas', fontSize: 34, height: 1)),
                      SizedBox(height: 4),
                      Row(children: [Icon(Icons.casino_rounded, size: 16), SizedBox(width: 5), Text('Surprise me', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Moods extends StatelessWidget {
  final HomeData data;
  final ValueChanged<String> onPick;

  const _Moods({required this.data, required this.onPick});

  static const _moods = [('Comfort', 'Slice of Life', Color(0xFF3FA796)), ('Laugh', 'Comedy', Color(0xFFE8A33D)), ('Hype', 'Action', Color(0xFFE5484D)), ('Feels', 'Drama', Color(0xFF5B8DEF)), ('Romance', 'Romance', Color(0xFFE85D9E)), ('Mystery', 'Mystery', Color(0xFF8B5CF6))];

  @override
  Widget build(BuildContext context) {
    final seen = <int>{};
    String? art(String genre) {
      for (final m in [...data.popular, ...data.comfort, ...data.laughs, ...data.top]) {
        if (m.genres.contains(genre) && seen.add(m.id)) return m.cover;
      }
      return null;
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
        itemCount: _moods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (label, genre, color) = _moods[i];
          final cover = art(genre);
          return Semantics(
            button: true,
            label: label,
            child: Pressable(
              onTap: () => onPick(genre),
              child: Container(
                width: 150,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null) Positioned(right: -14, top: -8, bottom: -8, child: Transform.rotate(angle: 0.14, child: Artwork(cover, width: 74, radius: 6))),
                    Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.bottomLeft, child: Text(label.toUpperCase(), style: const TextStyle(fontFamily: 'Bebas', fontSize: 25, height: 1)))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Surprise extends StatefulWidget {
  final Account account;
  final List<Media> pool;

  const _Surprise({required this.account, required this.pool});

  @override
  State<_Surprise> createState() => _SurpriseState();
}

class _SurpriseState extends State<_Surprise> {
  final _random = math.Random();
  late Media _shown;
  Timer? _timer;
  bool _spinning = true;

  @override
  void initState() {
    super.initState();
    _shown = widget.pool[_random.nextInt(widget.pool.length)];
    _spin();
  }

  void _spin() {
    _timer?.cancel();
    setState(() => _spinning = true);
    var delay = 70;
    void step() {
      if (!mounted) return;
      setState(() => _shown = widget.pool[_random.nextInt(widget.pool.length)]);
      delay = (delay * 1.22).round();
      if (delay > 480) {
        setState(() => _spinning = false);
        return;
      }
      _timer = Timer(Duration(milliseconds: delay), step);
    }

    step();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _shown;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_spinning ? 'CHOOSING' : 'TONIGHT YOU\'RE WATCHING', style: const TextStyle(fontFamily: 'Bebas', fontSize: 26, color: Palette.bright, letterSpacing: 1)),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 90),
                    child: Container(
                      key: ValueKey(m.id),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: showColor(m.color).withValues(alpha: 0.55), blurRadius: 50)]),
                      child: Artwork(m.cover, width: 220, height: 320, radius: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(m.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: _spinning ? null : _spin, child: const Text('Spin again'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _spinning
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  playAnime(context, widget.account, m.id);
                                },
                          child: const Text('Play it'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
