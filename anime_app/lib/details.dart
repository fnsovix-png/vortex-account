import 'package:flutter/material.dart';

import 'account.dart';
import 'anilist.dart';
import 'kitsu.dart';
import 'models.dart';
import 'theme.dart';
import 'ui.dart';
import 'watch.dart';

class DetailsScreen extends StatefulWidget {
  final Account account;
  final int id;
  final Media? preview;
  final String? heroTag;

  const DetailsScreen({super.key, required this.account, required this.id, this.preview, this.heroTag});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Media? _media;
  String? _error;
  bool _expanded = false;
  bool _solid = false;
  ShowExtras? _extras;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final solid = _scroll.offset > 170;
      if (solid != _solid) setState(() => _solid = solid);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await AniList.detail(widget.id);
      if (mounted) setState(() => _media = m);
      final done = widget.account.entry(widget.id)?.progress ?? 0;
      Kitsu.forShow(widget.id, from: done).then((e) {
        if (mounted && e != null) setState(() => _extras = e);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _guard(Future<void> action) {
    action.catchError((Object _) {
      if (mounted) toast(context, 'Check your internet connection and try again.');
    });
  }

  void _pickStatus(Media m) {
    final a = widget.account;
    final current = a.entry(m.id);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 8), child: Align(alignment: Alignment.centerLeft, child: Text('ADD TO YOUR LIST', style: TextStyle(fontFamily: 'Bebas', fontSize: 26)))),
            for (final s in listStatuses.entries)
              ListTile(
                title: Text(s.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: current?.status == s.key ? const Icon(Icons.check_rounded, color: Palette.bright) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  _guard(a.setStatus(m, s.key));
                },
              ),
            if (current != null)
              ListTile(
                title: const Text('Remove from list', style: TextStyle(color: Palette.danger, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheet);
                  _guard(a.removeEntry(m.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  String _airing(int seconds) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final m = _media ?? widget.preview;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: _solid ? Palette.background : Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: AnimatedOpacity(
          opacity: _solid ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Text(m?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      body: m == null
          ? ColoredBox(color: Palette.background, child: _error != null ? ErrorBox(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(color: Palette.purple)))
          : Ambient(
              color: showColor(m.color),
              child: ListenableBuilder(listenable: widget.account, builder: (context, _) => _content(m)),
            ),
    );
  }

  Widget _content(Media m) {
    final a = widget.account;
    final side = pageSide(context);
    final entry = a.entry(m.id);
    final top = MediaQuery.paddingOf(context).top;
    final wide = isWide(context);
    final accent = showColor(m.color);
    final bannerHeight = 250 + top;
    final season = [if (m.season != null) '${m.season![0]}${m.season!.substring(1).toLowerCase()}', if (m.year != null) '${m.year}'].join(' ');
    final loaded = _media != null;
    final progress = entry?.progress ?? 0;
    final total = m.knownEpisodes;
    final single = m.format == 'MOVIE' || total == 1;
    final next = total != null && progress >= total ? 1 : progress + 1;
    final canPlay = a.playable(m).isNotEmpty;
    final playLabel = !canPlay && loaded ? 'See where to watch' : !a.playsInVortex(m.id) && loaded ? 'Try the official stream' : single ? 'Play' : (progress > 0 && (total == null || progress < total) ? 'Continue episode $next' : 'Play episode $next');
    final cover = Artwork(m.cover, width: wide ? 170 : 122, height: wide ? 246 : 178);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Stack(
          children: [
            SizedBox(
              height: bannerHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((m.banner ?? m.cover).isNotEmpty) Image.network(m.banner ?? m.cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.25, 1], colors: [const Color(0xA609090F), const Color(0x1A09090F), Palette.background.withValues(alpha: 0.98)]),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, bannerHeight - 110, side, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10))]),
                    child: widget.heroTag == null ? cover : Hero(tag: widget.heroTag!, child: cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title.toUpperCase(), style: TextStyle(fontFamily: 'Bebas', fontSize: wide ? 52 : 36, height: 0.98, letterSpacing: 0.4)),
                        if (m.native != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.native!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(side, 16, side, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (m.score != null) _Fact(icon: Icons.star_rounded, text: '${m.score}%', iconColor: const Color(0xFFFFC857)),
                  if (m.formatLabel.isNotEmpty) _Fact(text: m.formatLabel),
                  if (m.episodes != null) _Fact(text: '${m.episodes} eps'),
                  if (m.statusLabel.isNotEmpty) _Fact(text: m.statusLabel),
                  if (season.isNotEmpty) _Fact(text: season),
                ],
              ),
              if (m.nextEpisode != null && m.nextAiringAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Episode ${m.nextEpisode} airs ${_airing(m.nextAiringAt!)}', style: const TextStyle(color: Palette.lavender, fontSize: 13, fontWeight: FontWeight.w600))),
              if (m.studios.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.studios.join(', '), style: const TextStyle(color: Palette.muted, fontSize: 12.5))),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Palette.background, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: loaded ? () => go(context, WatchScreen(account: a, media: m)) : null,
                  icon: Icon(canPlay || !loaded ? Icons.play_arrow_rounded : Icons.travel_explore_rounded, size: 26),
                  label: Text(playLabel),
                ),
              ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => _pickStatus(m),
                      icon: Icon(entry == null ? Icons.add_rounded : Icons.check_rounded, size: 20),
                      label: Text(entry == null ? 'Add to list' : listStatuses[entry.status] ?? 'On your list'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: entry?.favorite == true ? 'Remove from favorites' : 'Add to favorites',
                    style: IconButton.styleFrom(padding: const EdgeInsets.all(13), side: const BorderSide(color: Palette.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => _guard(a.toggleFavorite(m)),
                    icon: Icon(entry?.favorite == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: entry?.favorite == true ? Palette.bright : Colors.white),
                  ),
                ],
              ),
              ),
              if (a.verifiedAudio[m.id] != null) Padding(padding: const EdgeInsets.only(top: 14), child: _Fact(icon: Icons.verified_rounded, text: 'Confirmed: ${a.verifiedAudio[m.id]}', iconColor: Palette.free)),
              if ((_extras?.subLabel.isNotEmpty ?? false) || (_extras?.dubLabel.isNotEmpty ?? false)) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (_extras!.subLabel.isNotEmpty) _Fact(icon: Icons.subtitles_rounded, text: 'Subtitles: ${_extras!.subLabel}', iconColor: Palette.bright),
                    if (_extras!.dubLabel.isNotEmpty) _Fact(icon: Icons.record_voice_over_rounded, text: 'Audio: ${_extras!.dubLabel}', iconColor: Palette.bright),
                  ],
                ),
              ],
              if (m.genres.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(m.genres.join('  ·  '), style: TextStyle(color: Color.lerp(accent, Colors.white, 0.55), fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
              if (m.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(m.description, maxLines: _expanded ? null : 4, overflow: _expanded ? null : TextOverflow.ellipsis, style: const TextStyle(height: 1.5, fontSize: 13.5, color: Color(0xE6FFFFFF))),
                    ),
                  ),
                ),
              ],
              if (loaded) ...[
                WhereToWatch(account: a, media: m),
                if (!single) _Episodes(account: a, media: m, extras: _extras, onError: _guard),
              ],
            ],
          ),
        ),
        if (m.related.isNotEmpty) ...[
          const SectionTitle('Related'),
          AnimeRow(account: a, items: m.related, scope: 'rel-${m.id}'),
        ],
        if (m.recommended.isNotEmpty) ...[
          const SectionTitle('If you like this'),
          AnimeRow(account: a, items: m.recommended, scope: 'rec-${m.id}'),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;

  const _Fact({required this.text, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0x1FFFFFFF))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: iconColor), const SizedBox(width: 3)],
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Episodes extends StatelessWidget {
  final Account account;
  final Media media;
  final ShowExtras? extras;
  final void Function(Future<void>) onError;

  const _Episodes({required this.account, required this.media, required this.extras, required this.onError});

  @override
  Widget build(BuildContext context) {
    final m = media;
    final byNumber = {for (final e in m.streamEpisodes) if (e.number != null) e.number!: e};
    final count = m.knownEpisodes ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    final done = account.entry(m.id)?.progress ?? 0;
    final shown = count > 40 ? 40 : count;
    final first = count > 40 ? (done + 1).clamp(1, count - 39) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        const Text('Episodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        Text('$done of $count watched', style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (var n = first; n < first + shown; n++)
          _EpisodeRow(
            number: n,
            episode: byNumber[n],
            info: extras?.episodes[n],
            watched: n <= done,
            onPlay: () => go(context, WatchScreen(account: account, media: m, episode: n)),
            onToggle: () => onError(account.markWatchedUpTo(m, n <= done ? n - 1 : n)),
          ),
        if (count > shown) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Showing $shown of $count, starting from your place.', style: const TextStyle(color: Palette.muted, fontSize: 12.5))),
      ],
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final int number;
  final StreamEpisode? episode;
  final EpisodeInfo? info;
  final bool watched;
  final VoidCallback onPlay;
  final VoidCallback onToggle;

  const _EpisodeRow({required this.number, required this.episode, this.info, required this.watched, required this.onPlay, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final fromStream = e?.title.replaceFirst(RegExp(r'^Episode\s+\d+\s*-\s*'), '') ?? '';
    final name = info?.title.isNotEmpty == true ? info!.title : fromStream;
    final picture = info?.thumbnail.isNotEmpty == true ? info!.thumbnail : (e?.thumbnail ?? '');
    return Semantics(
      button: true,
      label: 'Play episode $number',
      child: Pressable(
        scale: 0.985,
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (picture.isNotEmpty) Artwork(picture, width: 112, height: 63, radius: 0) else ColoredBox(color: Palette.card, child: Center(child: Text('$number', style: const TextStyle(fontFamily: 'Bebas', fontSize: 30, color: Palette.lavender)))),
                      if (picture.isNotEmpty) const Center(child: Icon(Icons.play_circle_fill_rounded, size: 26)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Episode $number', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    if (name.isNotEmpty && name != 'Episode $number') Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: watched ? 'Mark as not watched' : 'Mark as watched',
                onPressed: onToggle,
                icon: Icon(watched ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: watched ? Palette.bright : Palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
