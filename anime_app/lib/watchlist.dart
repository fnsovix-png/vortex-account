import 'package:flutter/material.dart';

import 'account.dart';
import 'models.dart';
import 'theme.dart';
import 'ui.dart';

class WatchlistScreen extends StatefulWidget {
  final Account account;

  const WatchlistScreen({super.key, required this.account});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  String _tab = 'watching';
  String _sort = 'recent';
  String _query = '';

  List<ListEntry> _shown() {
    final q = _query.trim().toLowerCase();
    final items = widget.account.list.values.where((e) => (_tab == 'favorites' ? e.favorite : e.status == _tab) && (q.isEmpty || e.title.toLowerCase().contains(q))).toList();
    if (_sort == 'title') {
      items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else {
      items.sort((a, b) => b.updated - a.updated);
    }
    return items;
  }

  void _guard(Future<void> action) {
    action.catchError((Object _) {
      if (mounted) toast(context, 'Check your internet connection and try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final side = pageSide(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: a,
        builder: (context, _) {
          final items = _shown();
          final tabs = {...listStatuses, 'favorites': 'Favorites'};
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 16, side, 120),
            children: [
              const Text('My list', style: TextStyle(fontFamily: 'Bebas', fontSize: 40, letterSpacing: 0.6, height: 1)),
              const SizedBox(height: 12),
              TextField(onChanged: (v) => setState(() => _query = v), decoration: const InputDecoration(hintText: 'Search your list', prefixIcon: Icon(Icons.search_rounded, color: Palette.muted))),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in tabs.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${t.value} ${a.list.values.where((e) => t.key == 'favorites' ? e.favorite : e.status == t.key).length}'),
                          selected: _tab == t.key,
                          selectedColor: Palette.purple,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onSelected: (_) => setState(() => _tab = t.key),
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _sort = _sort == 'recent' ? 'title' : 'recent'),
                  style: TextButton.styleFrom(foregroundColor: Palette.muted),
                  icon: const Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text(_sort == 'recent' ? 'Recently updated' : 'A to Z'),
                ),
              ),
              if (items.isEmpty)
                EmptyBox(icon: Icons.bookmark_border_rounded, title: _query.isEmpty ? 'Nothing here yet' : 'No matches', body: _query.isEmpty ? 'Open any anime and add it to your list.' : 'Try another title.')
              else
                for (final e in items) _Row(account: a, entry: e, guard: _guard),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Account account;
  final ListEntry entry;
  final void Function(Future<void>) guard;

  const _Row({required this.account, required this.entry, required this.guard});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openAnime(context, account, e.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Artwork(e.cover, width: 58, height: 84, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text([if (e.format.isNotEmpty) e.format, e.episodes == null ? '${e.progress} watched' : '${e.progress} of ${e.episodes} watched', listStatuses[e.status] ?? ''].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Change',
              color: Palette.surface,
              icon: const Icon(Icons.more_horiz_rounded, color: Palette.muted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Palette.line)),
              onSelected: (v) {
                if (v == 'remove') {
                  guard(account.removeEntry(e.id));
                } else {
                  guard(account.changeEntry(e, status: v));
                }
              },
              itemBuilder: (_) => [
                for (final s in listStatuses.entries) PopupMenuItem(value: s.key, child: Text(s.value)),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Palette.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
