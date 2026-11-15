import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chat_extras.dart';
import 'flame.dart';
import 'fx.dart';
import 'models.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

String formatListening(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String statusLabel(String status, bool online) {
  return switch (status) {
    'dnd' => 'Do not disturb',
    'sleep' => 'Sleeping',
    'invisible' => 'Invisible',
    _ => online ? 'Online' : 'Offline',
  };
}

String joinedLabel(int seconds) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return 'Joined ${months[date.month - 1]} ${date.year}';
}

Color statusColor(String status) => switch (status) {
      'dnd' => const Color(0xFFE5484D),
      'sleep' => const Color(0xFFF0B232),
      'invisible' => const Color(0xFF8A8A94),
      _ => const Color(0xFF2DBE6C),
    };

IconData statusIcon(String status) => switch (status) {
      'dnd' => Icons.music_off_rounded,
      'sleep' => Icons.bedtime_rounded,
      'invisible' => Icons.visibility_off_rounded,
      _ => Icons.graphic_eq_rounded,
    };

class StatusDot extends StatelessWidget {
  final String status;
  final double size;

  const StatusDot({super.key, required this.status, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _StatusPainter(status));
  }
}

class _StatusPainter extends CustomPainter {
  final String status;

  const _StatusPainter(this.status);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    final radius = outer - (outer * 0.2).clamp(1.5, 3.0);
    canvas.drawCircle(center, outer, Paint()..color = AppColors.background);
    canvas.drawCircle(center, radius, Paint()..color = statusColor(status));
    const ink = Color(0xFF0C0C10);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.26;
    switch (status) {
      case 'dnd':
        // A slash, like a muted speaker.
        canvas.drawLine(center + Offset(-radius * 0.42, -radius * 0.42), center + Offset(radius * 0.42, radius * 0.42), line);
      case 'sleep':
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.6)),
          Path()..addOval(Rect.fromCircle(center: center + Offset(radius * 0.3, -radius * 0.24), radius: radius * 0.5)),
        );
        canvas.drawPath(moon, Paint()..color = ink);
      case 'invisible':
        canvas.drawCircle(center, radius * 0.42, line);
      default:
        // Three sound bars.
        for (final (x, h) in const [(-0.46, 0.34), (0.0, 0.62), (0.46, 0.34)]) {
          canvas.drawLine(center + Offset(radius * x, -radius * h), center + Offset(radius * x, radius * h), line);
        }
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) => old.status != status;
}

class StatusMenu extends StatelessWidget {
  final PlayerController c;
  final ValueChanged<String>? onChanged;

  const StatusMenu({super.key, required this.c, this.onChanged});

  static const _options = ['online', 'sleep', 'dnd', 'invisible'];

  static String _meaning(String status) => switch (status) {
        'sleep' => 'Friends know you\'ll reply later',
        'dnd' => 'Mutes your message badge',
        'invisible' => 'Hides you and what you\'re playing',
        _ => 'Friends see what you\'re playing',
      };

  Future<void> _set(BuildContext context, String status) async {
    if (status == c.profile?.status) return;
    try {
      await c.saveProfile(status: status);
      onChanged?.call(status);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check your internet connection and try again.')));
      }
    }
  }

  void _open(BuildContext context) {
    final current = c.profile?.status ?? 'online';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17171C),
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your status', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.32,
                children: [
                  for (final id in _options)
                    _StatusTile(
                      status: id,
                      hint: _meaning(id),
                      selected: id == current,
                      onTap: () {
                        Navigator.pop(sheet);
                        _set(context, id);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = c.profile?.status ?? 'online';
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 18, child: Icon(statusIcon(current), size: 18, color: statusColor(current))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(statusLabel(current, true), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(_meaning(current), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 12)),
                ],
              ),
            ),
            const Text('Change', style: TextStyle(color: AppColors.subtle, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String status;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _StatusTile({required this.status, required this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Material(
      color: selected ? color.withValues(alpha: 0.14) : const Color(0x0DFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? color : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon(status), size: 26, color: color),
              const Spacer(),
              Text(statusLabel(status, true), maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 12, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

class SelfPanel extends StatelessWidget {
  final PlayerController c;
  final VoidCallback onEdit;
  final ValueChanged<String>? onStatus;

  const SelfPanel({super.key, required this.c, required this.onEdit, this.onStatus});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0x12FFFFFF), borderRadius: BorderRadius.circular(8)),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              InkWell(
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      SizedBox(width: 18, child: Icon(Icons.edit_rounded, size: 17, color: AppColors.subtle)),
                      SizedBox(width: 12),
                      Expanded(child: Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: AppColors.hairline),
              StatusMenu(c: c, onChanged: onStatus),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonAvatar extends StatelessWidget {
  final PlayerController c;
  final Person person;
  final double size;

  const PersonAvatar({super.key, required this.c, required this.person, required this.size});

  @override
  Widget build(BuildContext context) {
    final version = person.images['avatar'];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.card),
          child: version != null
              ? Image.network(c.api.personImageUrl(person.id, 'avatar', version), width: size, height: size, fit: BoxFit.cover, cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil())
              : Text(person.username.characters.first.toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900)),
        ),
        if (person.online || person.status == 'dnd' || person.status == 'sleep')
          Positioned(
            right: 0,
            bottom: 0,
            child: StatusDot(status: person.status, size: size * 0.32),
          ),
      ],
    );
  }
}

class FriendsScreen extends StatefulWidget {
  final PlayerController c;

  const FriendsScreen({super.key, required this.c});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Person> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.c.refreshFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await widget.c.api.searchPeople(q.trim());
        if (mounted && _search.text.trim() == q.trim()) setState(() => _results = found);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    });
  }

  Future<void> _addFriend(Person p) async {
    await widget.c.api.addFriend(p.id);
    await widget.c.refreshFriends();
    if (_search.text.trim().isNotEmpty) _onSearch(_search.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final side = isWide(context) ? 28.0 : 18.0;
    final searching = _search.text.trim().isNotEmpty;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: c.refreshFriends,
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 18, side, isWide(context) ? 24 : 176),
          children: [
            const Text('Friends', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
            const SizedBox(height: 12),
            Glass(
              radius: 18,
              opacity: 0.1,
              child: Material(
                color: Colors.transparent,
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  cursorColor: AppColors.accent,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Find people by username',
                    hintStyle: TextStyle(color: AppColors.subtle),
                    prefixIcon: Icon(Icons.person_search_rounded, color: Colors.white),
                    contentPadding: EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF7B7B)))),
            if (searching) ...[
              const _Heading('Results'),
              if (_results.isEmpty) const Text('No one with that username yet.', style: TextStyle(color: AppColors.subtle)),
              for (final p in _results) _PersonRow(c: c, person: p, onAdd: () => _addFriend(p)),
            ] else ...[
              if (c.incomingRequests.isNotEmpty) ...[
                const _Heading('Requests'),
                for (final p in c.incomingRequests) _PersonRow(c: c, person: p, onAdd: () => _addFriend(p)),
              ],
              _Heading('Your friends (${c.friends.length})'),
              if (c.friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Search a username above to add your first friend.', style: TextStyle(color: AppColors.subtle)),
                ),
              for (final p in c.friends) _PersonRow(c: c, person: p),
              if (c.outgoingRequests.isNotEmpty) ...[
                const _Heading('Waiting for them to accept'),
                for (final p in c.outgoingRequests) _PersonRow(c: c, person: p),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final PlayerController c;
  final Person person;
  final VoidCallback? onAdd;

  const _PersonRow({required this.c, required this.person, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final track = person.nowPlaying;
    final String status;
    if (person.friendship == 'incoming') {
      status = 'Wants to be friends';
    } else if (person.friendship == 'outgoing') {
      status = 'Request sent';
    } else if (person.friendship != 'friends') {
      status = 'Not friends yet';
    } else if (track != null && person.isPlaying) {
      status = '${track.title} • ${track.artist}';
    } else {
      status = statusLabel(person.status, person.online);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonScreen(c: c, id: person.id, name: person.username))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            PersonAvatar(c: c, person: person, size: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(person.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      if (person.streak > 0) ...[
                        const SizedBox(width: 6),
                        StreakBadge(days: person.streak, size: 16),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (track != null && person.isPlaying) ...[
                        EqualizerBars(size: 12, color: AppColors.accent),
                        const SizedBox(width: 6),
                      ],
                      Expanded(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 13))),
                    ],
                  ),
                ],
              ),
            ),
            if (person.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: Text('${person.unread}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            if (onAdd != null && person.friendship == 'none') FilledButton(onPressed: onAdd, child: const Text('Add')),
            if (onAdd != null && person.friendship == 'incoming') FilledButton(onPressed: onAdd, child: const Text('Accept')),
            if (person.friendship == 'friends')
              IconButton(
                tooltip: 'Message',
                icon: const Icon(Icons.chat_bubble_rounded, size: 20),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(c: c, person: person))),
              ),
          ],
        ),
      ),
    );
  }
}

class PersonScreen extends StatefulWidget {
  final PlayerController c;
  final int id;
  final String name;

  const PersonScreen({super.key, required this.c, required this.id, required this.name});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Person? _person;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await widget.c.api.person(widget.id);
      if (mounted) setState(() => _person = p);
    } catch (_) {}
  }

  Future<void> _addOrAccept() async {
    await widget.c.api.addFriend(widget.id);
    await widget.c.refreshFriends();
    await _load();
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Remove ${widget.name}?'),
        content: const Text('You won\'t see each other\'s activity or be able to chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.c.api.removeFriend(widget.id);
    await widget.c.refreshFriends();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = _person;
    final top = MediaQuery.paddingOf(context).top;
    final bannerVersion = p?.images['banner'];
    final width = MediaQuery.sizeOf(context).width;
    final side = width >= 900 ? (width - 780) / 2 : 18.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            AppBackdrop(c: c),
            if (p == null)
              Center(child: EqualizerBars(size: 34, color: AppColors.accent))
            else
              ListView(
                padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
                children: [
                  SizedBox(
                    height: 210 + top + 54,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 210 + top,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              bannerVersion != null
                                  ? Image.network(c.api.personImageUrl(p.id, 'banner', bannerVersion), fit: BoxFit.cover, cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).ceil())
                                  : ValueListenableBuilder<List<Color>>(
                                      valueListenable: c.palette,
                                      builder: (context, colors, _) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: colors.take(3).toList()))),
                                    ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: [0.45, 1],
                                    colors: [Color(0x00000000), Color(0x8C000000)],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: side,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
                            child: PersonAvatar(c: c, person: p, size: 104),
                          ),
                        ),
                        if (p.quote.isNotEmpty)
                          Positioned(
                            left: side + 104,
                            right: side,
                            bottom: 46,
                            child: Align(alignment: Alignment.bottomLeft, child: _QuoteBubble(p.quote)),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(side, 14, side, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 2,
                          children: [
                            Text(p.username, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15)),
                            if (p.pronouns.isNotEmpty) Text(p.pronouns, style: const TextStyle(fontSize: 14, color: AppColors.subtle, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _identityLine(p),
                        if (p.bio.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(p.bio, style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xE6FFFFFF))),
                          ),
                        const SizedBox(height: 16),
                        _actions(context, p),
                        if (p.friendship == 'friends' || p.friendship == 'self') ...[
                          const SizedBox(height: 24),
                          _ProfileStats(person: p),
                          if (p.nowPlaying != null && p.isPlaying) ...[
                            const _Heading('Listening now'),
                            TrackTile(track: p.nowPlaying!, c: c, onTap: () => c.playList([p.nowPlaying!], 0)),
                          ],
                          if (p.topArtists.isNotEmpty) ...[
                            const _Heading('Top artists'),
                            SizedBox(
                              height: 134,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: p.topArtists.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 14),
                                itemBuilder: (ctx, i) => SizedBox(
                                  width: 100,
                                  child: Column(
                                    children: [
                                      Art(p.topArtists[i].thumbnail, size: 100, radius: 50),
                                      const SizedBox(height: 8),
                                      Text(p.topArtists[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ] else
                          const Padding(
                            padding: EdgeInsets.only(top: 18),
                            child: Text('Become friends to see what they\'re listening to.', style: TextStyle(color: AppColors.subtle)),
                          ),
                      ],
                    ),
                  ),
                ],
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

  Widget _identityLine(Person p) {
    final known = p.friendship == 'friends' || p.friendship == 'self';
    final away = p.status == 'dnd' || p.status == 'sleep';
    final shown = p.friendship == 'self' || !known ? null : statusLabel(p.status, p.online);
    return Row(
      children: [
        if (shown != null) ...[
          if (p.online || away) ...[
            StatusDot(status: p.status, size: 14),
            const SizedBox(width: 6),
          ],
          Text(shown, style: TextStyle(color: p.online || away ? statusColor(p.status) : AppColors.subtle, fontSize: 14, fontWeight: FontWeight.w700)),
          const Text('   ·   ', style: TextStyle(color: AppColors.subtle)),
        ],
        if (p.joined > 0) Text(joinedLabel(p.joined), style: const TextStyle(color: AppColors.subtle, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _actions(BuildContext context, Person p) {
    switch (p.friendship) {
      case 'self':
        return SelfPanel(
          c: widget.c,
          onStatus: (_) => _load(),
          onEdit: () async {
            await openProfileEditor(context, widget.c);
            await _load();
          },
        );
      case 'friends':
        return Row(
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(c: widget.c, person: p))),
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('Message'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _remove, child: const Text('Remove friend')),
          ],
        );
      case 'incoming':
        return FilledButton(onPressed: _addOrAccept, child: const Text('Accept request'));
      case 'outgoing':
        return OutlinedButton(onPressed: _remove, child: const Text('Cancel request'));
      case 'none':
        return FilledButton.icon(onPressed: _addOrAccept, icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Add friend'));
      default:
        return const SizedBox.shrink();
    }
  }
}

class _QuoteBubble extends StatelessWidget {
  final String quote;

  const _QuoteBubble(this.quote);

  @override
  Widget build(BuildContext context) {
    const shape = BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(16),
      bottomLeft: Radius.circular(3),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: const Color(0x38FFFFFF)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x47FFFFFF), Color(0x14FFFFFF)],
              ),
            ),
            child: Text(quote, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  final Person person;

  const _ProfileStats({required this.person});

  @override
  Widget build(BuildContext context) {
    final p = person;
    final next = nextFlameTier(p.streak);
    final String streakNote;
    if (p.streak == 0) {
      streakNote = p.friendship == 'self' ? 'Play a song today to light it' : 'No streak right now';
    } else if (p.friendship == 'self' && next != null) {
      final left = next.from - p.streak;
      streakNote = '$left more ${left == 1 ? 'day' : 'days'} to ${next.name.toLowerCase()} fire';
    } else {
      streakNote = 'Best ${p.bestStreak} ${p.bestStreak == 1 ? 'day' : 'days'}';
    }
    final streak = Row(
      children: [
        p.streak > 0
            ? StreakFlame(days: p.streak, size: 78)
            : const SizedBox.square(dimension: 78, child: Icon(Icons.local_fire_department_outlined, size: 42, color: Color(0x59FFFFFF))),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p.streak} day streak',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.streak > 0 ? flameTierFor(p.streak).mid : Colors.white),
              ),
              Text(streakNote, style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    final numbers = Row(
      children: [
        Expanded(child: _Figure(formatListening(p.listeningSeconds), 'listening')),
        Expanded(child: _Figure('${p.plays}', p.plays == 1 ? 'play' : 'plays')),
        if (p.bestStreak > 0) Expanded(child: _Figure('${p.bestStreak}', 'best streak')),
      ],
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 620
              ? Row(children: [Expanded(flex: 5, child: streak), const SizedBox(width: 16), Expanded(flex: 4, child: numbers)])
              : Column(children: [streak, const SizedBox(height: 12), numbers]),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;

  const _Figure(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 12.5)),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final PlayerController c;
  final Person person;

  const ChatScreen({super.key, required this.c, required this.person});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  final _focus = FocusNode();
  Timer? _timer;
  String? _error;
  bool _sending = false;
  bool _live = true;
  bool _emoji = false;

  @override
  void initState() {
    super.initState();
    _poll().then((_) => _listen());
  }

  /// Keeps one request open that the server answers the moment a message
  /// arrives. Falls back to checking every 3 seconds on older servers.
  Future<void> _listen() async {
    var failures = 0;
    while (mounted && _live) {
      try {
        final after = _messages.isEmpty ? 0 : _messages.last.id;
        _merge(await widget.c.api.waitMessages(widget.person.id, after));
        failures = 0;
      } on UnsupportedError {
        if (mounted) _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
        return;
      } catch (_) {
        failures++;
        await Future.delayed(Duration(seconds: min(1 << failures, 15)));
      }
    }
  }

  void _merge(List<ChatMessage> fresh) {
    if (!mounted || fresh.isEmpty) return;
    final known = _messages.map((m) => m.id).toSet();
    final add = fresh.where((m) => !known.contains(m.id)).toList();
    if (add.isEmpty) return;
    setState(() => _messages.addAll(add));
    _toBottom();
  }

  @override
  void dispose() {
    _live = false;
    _timer?.cancel();
    _focus.dispose();
    _input.dispose();
    _scroll.dispose();
    widget.c.refreshFriends();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _poll() async {
    try {
      final after = _messages.isEmpty ? 0 : _messages.last.id;
      _merge(await widget.c.api.messages(widget.person.id, after));
    } catch (_) {}
  }

  void _insertEmoji(String e) {
    final sel = _input.selection;
    final text = _input.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _input.value = TextEditingValue(text: text.replaceRange(start, end, e), selection: TextSelection.collapsed(offset: start + e.length));
  }

  void _toggleEmoji() {
    setState(() => _emoji = !_emoji);
    if (_emoji) {
      _focus.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _gift() async {
    final picked = await pickGift(context, widget.c, widget.person.username);
    if (picked == null || !mounted) return;
    await _send(track: picked.$1, gift: true, note: picked.$2);
  }

  Future<void> _send({Track? track, bool gift = false, String? note}) async {
    final text = note ?? _input.text.trim();
    if ((text.isEmpty && track == null) || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await widget.c.api.sendMessage(widget.person.id, text, track: track, gift: gift);
      if (!mounted) return;
      if (note == null) _input.clear();
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) _messages.add(sent);
      });
      _toBottom();
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t send that. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final me = c.profile?.id;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            AppBackdrop(c: c),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonScreen(c: c, id: widget.person.id, name: widget.person.username))),
                          child: Row(
                            children: [
                              PersonAvatar(c: c, person: widget.person, size: 40),
                              const SizedBox(width: 10),
                              Text(widget.person.username, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _messages.isEmpty
                        ? Center(child: Text('Say hi to ${widget.person.username}', style: const TextStyle(color: AppColors.subtle)))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) => _Bubble(c: c, message: _messages[i], mine: _messages[i].senderId == me, senderName: widget.person.username),
                          ),
                  ),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFF7B7B))),
                  if (widget.person.status == 'dnd' || widget.person.status == 'sleep')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        widget.person.status == 'dnd' ? '${widget.person.username} is on Do not disturb. They\'ll see this later.' : '${widget.person.username} is sleeping. They\'ll see this later.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.subtle, fontSize: 13),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Glass(
                      radius: 24,
                      opacity: 0.1,
                      child: Material(
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: _emoji ? 'Keyboard' : 'Emoji',
                              icon: Icon(_emoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined),
                              onPressed: _toggleEmoji,
                            ),
                            if (c.current != null)
                              IconButton(tooltip: 'Share what you\'re playing', icon: const Icon(Icons.music_note_rounded), onPressed: () => _send(track: c.current)),
                            IconButton(tooltip: 'Gift a song', icon: const Icon(Icons.card_giftcard_rounded), onPressed: _sending ? null : _gift),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.zero,
                                child: TextField(
                                  controller: _input,
                                  focusNode: _focus,
                                  onTap: () {
                                    if (_emoji) setState(() => _emoji = false);
                                  },
                                  maxLength: 2000,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  cursorColor: AppColors.accent,
                                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Message', counterText: ''),
                                ),
                              ),
                            ),
                            IconButton(tooltip: 'Send', icon: Icon(Icons.send_rounded, color: AppColors.accent), onPressed: _sending ? null : () => _send()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _emoji
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: Glass(radius: 20, opacity: 0.08, child: EmojiPanel(onPick: _insertEmoji)),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final PlayerController c;
  final ChatMessage message;
  final bool mine;
  final String senderName;

  const _Bubble({required this.c, required this.message, required this.mine, required this.senderName});

  @override
  Widget build(BuildContext context) {
    final track = message.track;
    if (message.gift && track != null) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: GiftCard(c: c, message: message, mine: mine, senderName: senderName),
        ),
      );
    }
    if (track == null && isBigEmoji(message.body)) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: SelectableText(message.body.trim(), style: const TextStyle(fontSize: 44, height: 1.1)),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? AppColors.accent.withValues(alpha: 0.32) : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track != null)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => c.playList([track], 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Art(track.thumbnail, size: 46, radius: 8),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.play_circle_rounded),
                    ],
                  ),
                ),
              if (track != null && message.body.isNotEmpty) const SizedBox(height: 6),
              if (message.body.isNotEmpty) SelectableText(message.body),
            ],
          ),
        ),
      ),
    );
  }
}
