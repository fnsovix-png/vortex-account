import 'dart:async';

import 'package:flutter/material.dart';

import 'account.dart';
import 'anilist.dart';
import 'models.dart';
import 'theme.dart';
import 'ui.dart';

class DiscoverController extends ChangeNotifier {
  bool playsHere = false;
  String? genre;

  void show({bool playsHere = false, String? genre}) {
    this.playsHere = playsHere;
    this.genre = genre;
    notifyListeners();
  }
}

class DiscoverScreen extends StatefulWidget {
  final Account account;
  final DiscoverController controller;

  const DiscoverScreen({super.key, required this.account, required this.controller});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String? _genre;
  int? _year;
  String? _format;
  String? _status;
  String _sort = 'POPULARITY_DESC';
  bool _plays = false;
  int? _site;
  List<Media> _items = [];
  bool _hasMore = false;
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _request = 0;

  static const _sorts = {'POPULARITY_DESC': 'Most popular', 'SCORE_DESC': 'Highest rated', 'TRENDING_DESC': 'Trending', 'START_DATE_DESC': 'Newest', 'TITLE_ROMAJI': 'A to Z'};
  static const _formats = {'TV': 'TV', 'MOVIE': 'Movie', 'OVA': 'OVA', 'ONA': 'ONA', 'SPECIAL': 'Special'};
  static const _statuses = {'RELEASING': 'Airing', 'FINISHED': 'Finished', 'NOT_YET_RELEASED': 'Upcoming'};

  @override
  void initState() {
    super.initState();
    _plays = widget.controller.playsHere;
    widget.controller.addListener(_external);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && _hasMore && !_loading) _fetch(more: true);
    });
    _fetch();
  }

  void _external() {
    final c = widget.controller;
    if (c.playsHere != _plays || c.genre != _genre) {
      setState(() {
        _plays = c.playsHere;
        _genre = c.genre;
      });
      _fetch();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_external);
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool more = false}) async {
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _items = [];
    });
    try {
      final result = await AniList.discover(search: _search.text.trim(), genre: _genre, year: _year, format: _format, status: _status, sort: _sort, sourceIds: _site == null ? null : [_site!], onlyIds: _plays ? widget.account.verified.keys.take(100).toList() : null, page: page);
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _items = more ? [..._items, ...result.items] : result.items;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _fetch);
  }

  void _clear() {
    setState(() {
      _genre = null;
      _year = null;
      _format = null;
      _status = null;
      _sort = 'POPULARITY_DESC';
      _plays = false;
      _site = null;
    });
    widget.controller
      ..playsHere = false
      ..genre = null;
    _fetch();
  }

  Widget _menu<T>(String label, T? value, Map<T, String> options, ValueChanged<T?> onPick) {
    final active = value != null;
    return PopupMenuButton<Object>(
      tooltip: '',
      color: Palette.surface,
      constraints: const BoxConstraints(maxHeight: 400),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Palette.line)),
      onSelected: (v) => onPick(v == '__any' ? null : v as T),
      itemBuilder: (_) => [
        const PopupMenuItem<Object>(value: '__any', child: Text('Any')),
        for (final e in options.entries) PopupMenuItem<Object>(value: e.key as Object, child: Text(e.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? Palette.purple.withValues(alpha: 0.18) : Palette.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? Palette.purple : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(active ? options[value]! : label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 18, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    final thisYear = DateTime.now().year + 1;
    return SafeArea(
      bottom: false,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(side, 16, side, 120),
        children: [
          const Text('Discover', style: TextStyle(fontFamily: 'Bebas', fontSize: 40, letterSpacing: 0.6, height: 1)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: _typed,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search anime',
              prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _fetch();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.account.verified.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() => _plays = !_plays);
                    widget.controller.playsHere = _plays;
                    _fetch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: _plays ? Palette.purple : Palette.card, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Plays here', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              _menu<int>('Source', _site, const {13: 'YouTube', 5: 'Crunchyroll', 20: 'HIDIVE', 10: 'Netflix'}, (v) {
                setState(() => _site = v);
                _fetch();
              }),
              _menu<String>('Genre', _genre, {for (final g in genreChoices) g: g}, (v) {
                setState(() => _genre = v);
                widget.controller.genre = v;
                _fetch();
              }),
              _menu<int>('Year', _year, {for (var y = thisYear; y >= 1990; y--) y: '$y'}, (v) {
                setState(() => _year = v);
                _fetch();
              }),
              _menu<String>('Format', _format, _formats, (v) {
                setState(() => _format = v);
                _fetch();
              }),
              _menu<String>('Status', _status, _statuses, (v) {
                setState(() => _status = v);
                _fetch();
              }),
              _menu<String>('Sort', _sort == 'POPULARITY_DESC' ? null : _sort, _sorts, (v) {
                setState(() => _sort = v ?? 'POPULARITY_DESC');
                _fetch();
              }),
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null && _items.isEmpty)
            ErrorBox(message: _error!, onRetry: _fetch)
          else if (_items.isEmpty && _loading)
            Wrap(spacing: 12, runSpacing: 18, children: [for (var i = 0; i < 12; i++) const Skeleton(width: 138, height: 200)])
          else if (_items.isEmpty)
            Column(
              children: [
                const EmptyBox(icon: Icons.search_off_rounded, title: 'Nothing matches that', body: 'Try another title or fewer filters.'),
                OutlinedButton(onPressed: _clear, child: const Text('Clear filters')),
              ],
            )
          else ...[
            AnimeGrid(account: widget.account, items: _items),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 18), child: ErrorBox(message: _error!, onRetry: () => _fetch(more: true))),
            if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Palette.purple))),
          ],
        ],
      ),
    );
  }
}
