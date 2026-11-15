import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'player_controller.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------- emojis

const _emojiSets = <(IconData, String, String)>[
  (Icons.emoji_emotions_outlined, 'Faces', '😀😃😄😁😆😅🤣😂🙂😉😊😇🥰😍🤩😘😋😛😜🤪😝🤗🤭🤫🤔🫡🤐🤨😐😑😶🙄😏😬😌😔😪😴😷🥵🥶🥴😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺🥹😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈💀👻👽🤖'),
  (Icons.favorite_border_rounded, 'Hearts', '❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝💟❤️‍🔥🩷🩵🩶'),
  (Icons.back_hand_outlined, 'Hands', '👍👎👊✊🤛🤜👏🙌🫶👐🤲🤝🙏✌️🤞🫰🤟🤘👌🤌🤏👈👉👆👇☝️✋🤚🖐️🖖👋🤙💪'),
  (Icons.music_note_rounded, 'Music', '🎵🎶🎧🎤🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻📻🔊🎙️💿📀🪩'),
  (Icons.celebration_outlined, 'Party', '🎉🎊🎁🎈🎂🍰🥂🍾✨🌟⭐💫🔥⚡🌈🎆🎇🏆🥇👑💎'),
  (Icons.pets_outlined, 'Animals', '🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🦄🐝🦋🐢🐍🐙🐬🐳🦈'),
  (Icons.fastfood_outlined, 'Food', '🍎🍓🍒🍑🥭🍍🍌🍉🍇🍕🍔🍟🌭🌮🍣🍜🍩🍪🍫🍿🧋☕🍵🥤'),
];

List<String> _split(String s) => s.characters.toList();

final _onlyEmoji = RegExp(r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|‍|️|⃣|\s)+$', unicode: true);

/// 1 to 3 emoji and nothing else: shown large, without a bubble.
bool isBigEmoji(String text) {
  final t = text.trim();
  if (t.isEmpty || !_onlyEmoji.hasMatch(t)) return false;
  return t.replaceAll(RegExp(r'\s'), '').characters.length <= 3;
}

class EmojiPanel extends StatefulWidget {
  final ValueChanged<String> onPick;
  const EmojiPanel({super.key, required this.onPick});

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  static const _recentKey = 'recentEmoji';
  List<String> _recent = const [];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = saved);
      if (saved.isEmpty && mounted) setState(() => _tab = 1);
    });
  }

  Future<void> _pick(String e) async {
    widget.onPick(e);
    final next = [e, ..._recent.where((r) => r != e)].take(24).toList();
    setState(() => _recent = next);
    (await SharedPreferences.getInstance()).setStringList(_recentKey, next);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String, List<String>)>[
      (Icons.schedule_rounded, 'Recent', _recent),
      for (final s in _emojiSets) (s.$1, s.$2, _split(s.$3)),
    ];
    final current = tabs[_tab.clamp(0, tabs.length - 1)];
    return SizedBox(
      height: 280,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: tabs.length,
            itemBuilder: (_, i) => IconButton(
              tooltip: tabs[i].$2,
              isSelected: i == _tab,
              color: i == _tab ? AppColors.accent : AppColors.subtle,
              icon: Icon(tabs[i].$1, size: 22),
              onPressed: () => setState(() => _tab = i),
            ),
          ),
        ),
        Expanded(
          child: current.$3.isEmpty
              ? const Center(child: Text('Emojis you use show up here', style: TextStyle(color: AppColors.subtle)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
                  itemCount: current.$3.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pick(current.$3[i]),
                    child: Center(child: Text(current.$3[i], style: const TextStyle(fontSize: 26))),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- gifts

/// A wrapped present that bursts open into a spinning record of the song.
class GiftCard extends StatefulWidget {
  final PlayerController c;
  final ChatMessage message;
  final bool mine;
  final String senderName;
  const GiftCard({super.key, required this.c, required this.message, required this.mine, required this.senderName});

  @override
  State<GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends State<GiftCard> with TickerProviderStateMixin {
  static const _openedKey = 'openedGifts';
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (widget.mine) {
      _open = true;
    } else {
      SharedPreferences.getInstance().then((p) {
        final opened = p.getStringList(_openedKey) ?? const [];
        if (mounted && opened.contains('${widget.message.id}')) setState(() => _open = true);
      });
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _unwrap() async {
    if (_open) return;
    await _burst.forward(from: 0);
    if (!mounted) return;
    setState(() => _open = true);
    final p = await SharedPreferences.getInstance();
    final opened = {...p.getStringList(_openedKey) ?? const <String>[], '${widget.message.id}'}.toList();
    await p.setStringList(_openedKey, opened.length > 500 ? opened.sublist(opened.length - 500) : opened);
  }

  void _play() {
    final t = widget.message.track!;
    widget.c.playList([t], 0);
    if (!_spin.isAnimating) _spin.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    final note = widget.message.body;
    return SizedBox(
      width: 260,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: .85, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
        child: _open ? _revealed(accent, note) : _wrapped(accent, note),
      ),
    );
  }

  Widget _wrapped(Color accent, String note) {
    return GestureDetector(
      key: const ValueKey('wrapped'),
      onTap: _unwrap,
      child: AnimatedBuilder(
        animation: _burst,
        builder: (context, child) {
          final t = _burst.value;
          final shake = t < .55 ? sin(t * 40) * (1 - t / .55) * .08 : 0.0;
          final pop = t < .55 ? 1.0 : 1 + (t - .55) * .5;
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Transform.rotate(angle: shake, child: Transform.scale(scale: pop, child: Opacity(opacity: t < .7 ? 1 : (1 - (t - .7) / .3), child: child))),
            if (t > .5) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter((t - .5) / .5, accent)))),
          ]);
        },
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withValues(alpha: .9), Color.lerp(accent, Colors.black, .45)!]),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Stack(children: [
            Positioned.fill(child: Center(child: Container(width: 26, color: Colors.white.withValues(alpha: .85)))),
            Positioned(left: 0, right: 0, top: 46, child: Container(height: 22, color: Colors.white.withValues(alpha: .85))),
            Positioned(
              left: 0,
              right: 0,
              top: 26,
              child: Icon(Icons.card_giftcard_rounded, size: 54, color: Colors.white.withValues(alpha: .98)),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(children: [
                Text('${widget.senderName} sent you a song', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
                Text(note.isEmpty ? 'Tap to unwrap' : 'Tap to unwrap · there\'s a note', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xCC000000))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _revealed(Color accent, String note) {
    final t = widget.message.track!;
    return Container(
      key: const ValueKey('open'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0x1FFFFFFF),
        border: Border.all(color: accent.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.card_giftcard_rounded, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(widget.mine ? 'You gifted a song' : 'A gift from ${widget.senderName}', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          RotationTransition(
            turns: _spin,
            child: SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(
                painter: _VinylPainter(),
                child: Center(child: ClipOval(child: Art(t.thumbnail, size: 38, radius: 19))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 2),
              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _play,
                style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('“$note”', style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xE6FFFFFF))),
        ],
      ]),
    );
  }
}

class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0D0D10));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = const Color(0x22FFFFFF);
    for (var g = r * .55; g < r - 2; g += 3.2) {
      canvas.drawCircle(c, g, groove);
    }
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * .82), -2.4, .9, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x18FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final Color accent;
  _ConfettiPainter(this.t, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final c = size.center(Offset.zero);
    final colors = [accent, Colors.white, const Color(0xFFFFD166), const Color(0xFFFF6B9A), const Color(0xFF6BD5FF)];
    for (var i = 0; i < 36; i++) {
      final angle = rnd.nextDouble() * pi * 2;
      final speed = 60 + rnd.nextDouble() * 120;
      final d = speed * t;
      final p = c + Offset(cos(angle) * d, sin(angle) * d + 60 * t * t);
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + t * 6);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -2, 8, 4), const Radius.circular(1)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Pick a song to gift: what's playing, or search. Returns the song and a note.
Future<(Track, String)?> pickGift(BuildContext context, PlayerController c, String friend) {
  return showModalBottomSheet<(Track, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _GiftSheet(c: c, friend: friend),
  );
}

class _GiftSheet extends StatefulWidget {
  final PlayerController c;
  final String friend;
  const _GiftSheet({required this.c, required this.friend});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  final _note = TextEditingController();
  Timer? _debounce;
  List<Track> _results = const [];
  bool _loading = false;
  Track? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.c.current;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (q.trim().length < 2) return setState(() => _results = const []);
      setState(() => _loading = true);
      try {
        final r = await widget.c.api.search(q.trim(), limit: 12);
        if (mounted) setState(() => _results = r);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0x44FFFFFF), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Gift a song to ${widget.friend}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.5)),
              const SizedBox(height: 4),
              const Text('They unwrap it in the chat and can play it right away.', style: TextStyle(color: AppColors.subtle)),
              const SizedBox(height: 14),
              TextField(
                onChanged: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search a song'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  if (widget.c.current != null && _results.isEmpty) ...[
                    const Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text('PLAYING NOW', style: TextStyle(color: AppColors.subtle, fontSize: 11, fontWeight: FontWeight.w800))),
                    _row(widget.c.current!),
                  ],
                  if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                  for (final t in _results) _row(t),
                ]),
              ),
              TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(hintText: 'Add a note (optional)', counterText: '')),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: picked == null ? null : () => Navigator.pop(context, (picked, _note.text.trim())),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: Text(picked == null ? 'Pick a song' : 'Send gift', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(Track t) {
    final sel = _picked?.id == t.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Art(t.thumbnail, size: 46, radius: 8),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle)),
      trailing: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: sel ? AppColors.accent : AppColors.subtle),
      onTap: () => setState(() => _picked = t),
    );
  }
}
