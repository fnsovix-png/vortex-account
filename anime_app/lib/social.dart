import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'account.dart';
import 'library.dart';
import 'models.dart';
import 'sources.dart';
import 'theme.dart';
import 'ui.dart';

class FriendsScreen extends StatefulWidget {
  final Account account;

  const FriendsScreen({super.key, required this.account});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Person> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _typed(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await widget.account.searchPeople(q.trim());
        if (mounted && _search.text.trim() == q.trim()) setState(() => _results = found);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final side = pageSide(context);
    final searching = _search.text.trim().isNotEmpty;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: a,
        builder: (context, _) => RefreshIndicator(
          onRefresh: a.refreshFriends,
          color: Palette.purple,
          child: ListView(
            padding: EdgeInsets.fromLTRB(side, 16, side, 120),
            children: [
              const Text('Friends', style: TextStyle(fontFamily: 'Bebas', fontSize: 40, letterSpacing: 0.6, height: 1)),
              const Text('The same friends and chats as Vortex Music.', style: TextStyle(color: Palette.muted)),
              const SizedBox(height: 12),
              TextField(controller: _search, onChanged: _typed, decoration: const InputDecoration(hintText: 'Find people by username', prefixIcon: Icon(Icons.person_search_rounded, color: Palette.muted))),
              if (searching) ...[
                const _Heading('Results'),
                if (_results.isEmpty) const Text('No one with that username yet.', style: TextStyle(color: Palette.muted)),
                for (final p in _results) _PersonRow(account: a, person: p),
              ] else ...[
                if (a.incoming.isNotEmpty) ...[const _Heading('Requests'), for (final p in a.incoming) _PersonRow(account: a, person: p)],
                _Heading('Your friends (${a.friends.length})'),
                if (a.friends.isEmpty) const EmptyBox(icon: Icons.group_outlined, title: 'No friends yet', body: 'Search a username above to add your first friend.'),
                for (final p in a.friends) _PersonRow(account: a, person: p),
                if (a.outgoing.isNotEmpty) ...[const _Heading('Waiting for them to accept'), for (final p in a.outgoing) _PersonRow(account: a, person: p)],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 6), child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));
}

class _PersonRow extends StatelessWidget {
  final Account account;
  final Person person;

  const _PersonRow({required this.account, required this.person});

  @override
  Widget build(BuildContext context) {
    final p = person;
    final shows = p.online || p.status == 'dnd' || p.status == 'sleep';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => go(context, PersonScreen(account: account, id: p.id, name: p.username)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            PersonAvatar(account: account, id: p.id, name: p.username, images: p.images, size: 46, status: shows ? p.status : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(p.statusText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (p.unread > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Palette.purple, borderRadius: BorderRadius.circular(10)),
                child: Text('${p.unread}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            if (p.friendship == 'none') FilledButton(onPressed: () => account.addFriend(p.id), child: const Text('Add')),
            if (p.friendship == 'incoming') FilledButton(onPressed: () => account.addFriend(p.id), child: const Text('Accept')),
            if (p.friendship == 'friends')
              IconButton(tooltip: 'Message', icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20), onPressed: () => go(context, ChatScreen(account: account, person: p))),
          ],
        ),
      ),
    );
  }
}

class PersonScreen extends StatefulWidget {
  final Account account;
  final int id;
  final String name;

  const PersonScreen({super.key, required this.account, required this.id, required this.name});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Person? _person;
  List<ListEntry> _list = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.account.person(widget.id);
      List<ListEntry> list = [];
      if (p.friendship == 'friends' || p.friendship == 'self') list = await widget.account.personList(widget.id);
      if (mounted) {
        setState(() {
          _person = p;
          _list = list;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Check your internet connection and try again.');
    }
  }

  Future<void> _addOrAccept() async {
    await widget.account.addFriend(widget.id);
    await _load();
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.name}?'),
        content: const Text('You won\'t see each other\'s activity or be able to chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.account.removeFriend(widget.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final p = _person;
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.background, scrolledUnderElevation: 0, title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
      body: p == null
          ? (_error != null ? ErrorBox(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(color: Palette.purple)))
          : ListView(
              padding: EdgeInsets.fromLTRB(pageSide(context), 8, pageSide(context), 28),
              children: [
                _ProfileHead(account: a, id: p.id, name: p.username, images: p.images, pronouns: p.pronouns, quote: p.quote, bio: p.bio, statusText: p.statusText, status: p.online || p.status == 'dnd' || p.status == 'sleep' ? p.status : null),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (p.friendship == 'friends') ...[
                      FilledButton.icon(onPressed: () => go(context, ChatScreen(account: a, person: p)), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('Message')),
                      OutlinedButton(onPressed: _remove, child: const Text('Remove friend')),
                    ],
                    if (p.friendship == 'none') FilledButton(onPressed: _addOrAccept, child: const Text('Add friend')),
                    if (p.friendship == 'incoming') FilledButton(onPressed: _addOrAccept, child: const Text('Accept request')),
                    if (p.friendship == 'outgoing') OutlinedButton(onPressed: _remove, child: const Text('Cancel request')),
                  ],
                ),
                if (p.friendship == 'friends') ...[
                  const SizedBox(height: 24),
                  const Text('Their anime', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (_list.isEmpty) const Text('Nothing on their list yet.', style: TextStyle(color: Palette.muted)),
                  for (final e in _list.take(40))
                    InkWell(
                      onTap: () => openAnime(context, a, e.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Artwork(e.cover, width: 46, height: 66, radius: 6),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(listStatuses[e.status] ?? '', style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _ProfileHead extends StatelessWidget {
  final Account account;
  final int id;
  final String name;
  final Map<String, int> images;
  final String pronouns;
  final String quote;
  final String bio;
  final String statusText;
  final String? status;
  final bool mine;

  const _ProfileHead({required this.account, required this.id, required this.name, required this.images, required this.pronouns, required this.quote, required this.bio, required this.statusText, this.status, this.mine = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PersonAvatar(account: account, id: id, name: name, images: images, size: 88, mine: mine, status: status),
            if (quote.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Palette.card,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14), bottomRight: Radius.circular(14), bottomLeft: Radius.circular(3)),
                  ),
                  child: Text(quote, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            if (pronouns.isNotEmpty) Text(pronouns, style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600)),
          ],
        ),
        Text(statusText, style: const TextStyle(color: Palette.lavender, fontSize: 13, fontWeight: FontWeight.w600)),
        if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(bio, style: const TextStyle(height: 1.4))),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Account account;
  final Person person;

  const ChatScreen({super.key, required this.account, required this.person});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  Timer? _timer;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    widget.account.refreshFriends();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _poll() async {
    try {
      final fresh = await widget.account.messages(widget.person.id, _messages.isEmpty ? 0 : _messages.last.id);
      if (!mounted || fresh.isEmpty) return;
      final known = _messages.map((m) => m.id).toSet();
      setState(() => _messages.addAll(fresh.where((m) => !known.contains(m.id))));
      _toEnd();
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await widget.account.sendMessage(widget.person.id, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) _messages.add(sent);
      });
      _toEnd();
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t send that. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final p = widget.person;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.background,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            PersonAvatar(account: a, id: p.id, name: p.username, images: p.images, size: 32),
            const SizedBox(width: 10),
            Expanded(child: Text(p.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(child: Text('Say hi to ${p.username}', style: const TextStyle(color: Palette.muted)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final mine = m.senderId == a.me?.id;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: mine ? Palette.purple : Palette.card, borderRadius: BorderRadius.circular(10)),
                              child: SelectableText(m.body),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Palette.danger)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(controller: _input, minLines: 1, maxLines: 4, maxLength: 2000, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message', counterText: '')),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(tooltip: 'Send', style: IconButton.styleFrom(backgroundColor: Palette.purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded, size: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final Account account;

  const ProfileScreen({super.key, required this.account});

  static const _statuses = {
    'online': ('Online', 'Friends see when you\'re here'),
    'sleep': ('Sleeping', 'Friends know you\'ll reply later'),
    'dnd': ('Do not disturb', 'Mutes your message badge in Vortex Music'),
    'invisible': ('Invisible', 'You\'ll appear offline'),
  };

  Future<void> _avatar(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    try {
      await account.uploadImage('avatar', bytes);
    } catch (e) {
      if (context.mounted) toast(context, e is String ? e : 'Use a PNG, JPEG, WebP or GIF under 10 MB.');
    }
  }

  void _pickStatus(BuildContext context) {
    final current = account.me?.status;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _statuses.entries)
              ListTile(
                leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: statusColor(s.key), shape: BoxShape.circle)),
                title: Text(s.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(s.value.$2, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                trailing: current == s.key ? const Icon(Icons.check_rounded, color: Palette.bright) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  account.saveProfile(status: s.key).catchError((Object _) {
                    if (context.mounted) toast(context, 'Check your internet connection and try again.');
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: account,
        builder: (context, _) {
          final me = account.me;
          if (me == null) return ErrorBox(message: 'Check your internet connection and try again.', onRetry: account.load);
          final list = account.list.values;
          int count(String s) => list.where((e) => e.status == s).length;
          final episodes = list.fold<int>(0, (sum, e) => sum + e.progress);
          final favorites = list.where((e) => e.favorite).toList();
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 16, side, 120),
            children: [
              InkWell(
                onTap: () => _avatar(context),
                borderRadius: BorderRadius.circular(8),
                child: _ProfileHead(
                  account: account,
                  id: me.id,
                  name: me.username,
                  images: me.images,
                  pronouns: me.pronouns,
                  quote: me.quote,
                  bio: me.bio,
                  statusText: _statuses[me.status]?.$1 ?? 'Online',
                  status: me.status,
                  mine: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Tap your profile to change your picture. It updates in Vortex Music too.', style: TextStyle(color: Palette.muted, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    ListTile(leading: const Icon(Icons.edit_rounded, size: 20), title: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w600)), onTap: () => go(context, _EditProfile(account: account))),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(leading: const Icon(Icons.video_library_rounded, size: 20), title: const Text('My Library', style: TextStyle(fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right_rounded, color: Palette.muted), onTap: () => go(context, MyLibraryScreen(prefs: account.prefs))),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(leading: const Icon(Icons.hub_rounded, size: 20), title: const Text('Sources', style: TextStyle(fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right_rounded, color: Palette.muted), onTap: () => go(context, SourcesScreen(account: account))),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(leading: Container(width: 12, height: 12, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(color: statusColor(me.status), shape: BoxShape.circle)), title: const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)), trailing: Text(_statuses[me.status]?.$1 ?? 'Online', style: const TextStyle(color: Palette.muted)), onTap: () => _pickStatus(context)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text('Your anime', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 26,
                runSpacing: 14,
                children: [_Number('$episodes', 'episodes'), _Number('${count('watching')}', 'watching'), _Number('${count('completed')}', 'completed'), _Number('${count('planning')}', 'planned')],
              ),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Favorites', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => InkWell(onTap: () => openAnime(context, account, favorites[i].id), child: Artwork(favorites[i].cover, width: 88, height: 128)),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              OutlinedButton.icon(onPressed: account.signOut, icon: const Icon(Icons.logout_rounded, size: 18), label: const Text('Sign out')),
            ],
          );
        },
      ),
    );
  }
}

class _Number extends StatelessWidget {
  final String value;
  final String label;

  const _Number(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
        ],
      );
}

class _EditProfile extends StatefulWidget {
  final Account account;

  const _EditProfile({required this.account});

  @override
  State<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<_EditProfile> {
  late final _name = TextEditingController(text: widget.account.me?.username ?? '');
  late final _pronouns = TextEditingController(text: widget.account.me?.pronouns ?? '');
  late final _quote = TextEditingController(text: widget.account.me?.quote ?? '');
  late final _bio = TextEditingController(text: widget.account.me?.bio ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pronouns.dispose();
    _quote.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.account.saveProfile(username: _name.text.trim(), pronouns: _pronouns.text.trim(), quote: _quote.text.trim(), bio: _bio.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e is String ? e : 'Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.background, scrolledUnderElevation: 0, title: const Text('Edit profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: pageSide(context), vertical: 12),
        children: [
          const Text('This is the same profile as Vortex Music.', style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 14),
          TextField(controller: _name, maxLength: 30, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 10),
          TextField(controller: _pronouns, maxLength: 30, decoration: const InputDecoration(labelText: 'Pronouns')),
          const SizedBox(height: 10),
          TextField(controller: _quote, maxLength: 120, maxLines: 2, minLines: 1, decoration: const InputDecoration(labelText: 'Quote')),
          const SizedBox(height: 10),
          TextField(controller: _bio, maxLength: 300, maxLines: 5, minLines: 2, decoration: const InputDecoration(labelText: 'Bio')),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving' : 'Save'))),
        ],
      ),
    );
  }
}
