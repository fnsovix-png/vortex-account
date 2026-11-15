import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account.dart';
import 'anilist.dart';
import 'details.dart';
import 'models.dart';
import 'theme.dart';
import 'watch.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2), margin: const EdgeInsets.fromLTRB(16, 0, 16, 92)));
}

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'That link couldn\'t be opened.');
}

Future<T?> go<T>(BuildContext context, Widget page) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curve), child: child),
        );
      },
    ),
  );
}

void openAnime(BuildContext context, Account a, int id, {Media? preview, String? heroTag}) => go(context, DetailsScreen(account: a, id: id, preview: preview, heroTag: heroTag));

/// Jumps straight to the watch page, even from places that only know a show's id.
Future<void> playAnime(BuildContext context, Account a, int id) async {
  try {
    final media = await AniList.detail(id);
    if (context.mounted) go(context, WatchScreen(account: a, media: media));
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// Gives anything tappable the same soft squeeze.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.96});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _down ? widget.scale : 1, duration: const Duration(milliseconds: 120), curve: Curves.easeOut, child: widget.child),
    );
  }
}

/// A slow light behind the page, in the colour of whatever show you're looking at.
class Ambient extends StatefulWidget {
  final Color color;
  final Widget child;

  const Ambient({super.key, required this.color, required this.child});

  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  final _phase = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // Ten updates a second is plenty for something this slow, and keeps the phone cool.
    _drift.addListener(() {
      final stepped = (_drift.value * 300).floorToDouble() / 300;
      if (stepped != _phase.value) _phase.value = stepped;
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: widget.color),
            duration: const Duration(milliseconds: 900),
            builder: (_, color, _) => CustomPaint(painter: _AmbientPainter(color ?? widget.color, _phase)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final Color color;
  final ValueNotifier<double> phase;

  _AmbientPainter(this.color, this.phase) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.background);
    final t = phase.value * math.pi * 2;
    void blob(double x, double y, double radius, double alpha) {
      final center = Offset(size.width * x, size.height * y);
      final r = size.width * radius;
      canvas.drawCircle(center, r, Paint()..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: r)));
    }

    blob(0.85 + math.sin(t) * 0.14, 0.42 + math.cos(t) * 0.04, 1.05, 0.26);
    blob(0.1 + math.cos(t * 2) * 0.12, 0.72 + math.sin(t) * 0.06, 0.95, 0.15);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.color != color;
}

class Wordmark extends StatelessWidget {
  final double size;

  const Wordmark({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'VORTEX', style: TextStyle(fontFamily: 'Bebas', fontSize: size, letterSpacing: 1.5, color: Colors.white)),
        TextSpan(text: ' ANIME', style: TextStyle(fontFamily: 'Bebas', fontSize: size, letterSpacing: 1.5, color: Palette.bright)),
      ]),
    );
  }
}

class Artwork extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final double radius;
  final Alignment alignment;

  const Artwork(this.url, {super.key, this.width, this.height, this.radius = 10, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    final blank = Container(width: width, height: height, color: Palette.card, alignment: Alignment.center, child: const Icon(Icons.image_not_supported_outlined, color: Palette.line));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? blank
          : Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              alignment: alignment,
              cacheWidth: width == null ? null : (width! * MediaQuery.devicePixelRatioOf(context)).ceil(),
              errorBuilder: (_, _, _) => blank,
              frameBuilder: (_, child, frame, sync) => AnimatedOpacity(opacity: sync || frame != null ? 1 : 0, duration: const Duration(milliseconds: 260), child: ColoredBox(color: Palette.card, child: child)),
            ),
    );
  }
}

class PlaysTag extends StatelessWidget {
  const PlaysTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
      decoration: BoxDecoration(color: Palette.purple, borderRadius: BorderRadius.circular(5)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 13),
          Text('VORTEX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class ScoreTag extends StatelessWidget {
  final int score;

  const ScoreTag(this.score, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xCC09090F), borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFC857)),
          const SizedBox(width: 2),
          Text('$score', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class AnimeCard extends StatelessWidget {
  final Account account;
  final Media media;
  final double width;
  final String scope;

  const AnimeCard({super.key, required this.account, required this.media, this.width = 136, this.scope = ''});

  @override
  Widget build(BuildContext context) {
    final m = media;
    final tag = 'cover-$scope-${m.id}';
    final facts = [if (m.year != null) '${m.year}', if (m.formatLabel.isNotEmpty) m.formatLabel].join(' · ');
    return Semantics(
      button: true,
      label: m.title,
      child: Pressable(
        onTap: () => openAnime(context, account, m.id, preview: m, heroTag: tag),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: showColor(m.color).withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))]),
                child: Stack(
                  children: [
                    Hero(tag: tag, child: Artwork(m.cover, width: width, height: width * 1.46)),
                    if (account.playsInVortex(m.id)) const Positioned(left: 6, top: 6, child: PlaysTag()),
                    if (m.score != null) Positioned(right: 6, bottom: 6, child: ScoreTag(m.score!)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.25)),
              const SizedBox(height: 2),
              Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A poster standing on a huge outlined rank number.
class RankCard extends StatelessWidget {
  final Account account;
  final Media media;
  final int rank;

  const RankCard({super.key, required this.account, required this.media, required this.rank});

  @override
  Widget build(BuildContext context) {
    final m = media;
    final tag = 'cover-rank-${m.id}';
    final wide = rank >= 10;
    return Semantics(
      button: true,
      label: 'Number $rank, ${m.title}',
      child: Pressable(
        onTap: () => openAnime(context, account, m.id, preview: m, heroTag: tag),
        child: SizedBox(
          width: wide ? 214 : 180,
          height: 176,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: -18,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontFamily: 'Bebas',
                    fontSize: 172,
                    height: 1,
                    letterSpacing: -6,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 2.5
                      ..color = Palette.bright,
                  ),
                ),
              ),
              Positioned(right: 0, top: 0, child: Hero(tag: tag, child: Artwork(m.cover, width: 120, height: 176))),
              if (account.playsInVortex(m.id)) const Positioned(right: 54, top: 6, child: PlaysTag()),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onMore;

  const SectionTitle(this.title, {super.key, this.subtitle, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pageSide(context), 30, pageSide(context), 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Bebas', fontSize: 30, letterSpacing: 0.6, height: 1)),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, style: const TextStyle(color: Palette.muted, fontSize: 12.5))),
              ],
            ),
          ),
          if (onMore != null)
            Semantics(
              button: true,
              label: 'View all $title',
              child: Pressable(onTap: onMore, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.arrow_forward_rounded, color: Palette.bright))),
            ),
        ],
      ),
    );
  }
}

double pageSide(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 1280 ? (width - 1180) / 2 : (width >= wideLayout ? 32 : 18);
}

class AnimeRow extends StatelessWidget {
  final Account account;
  final List<Media> items;
  final String scope;

  const AnimeRow({super.key, required this.account, required this.items, required this.scope});

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    return SizedBox(
      height: 268,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: side),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => AnimeCard(account: account, media: items[i], scope: scope),
      ),
    );
  }
}

class AnimeGrid extends StatelessWidget {
  final Account account;
  final List<Media> items;
  final String scope;

  const AnimeGrid({super.key, required this.account, required this.items, this.scope = 'grid'});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 150).floor().clamp(2, 8);
        const gap = 12.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [for (final m in items) AnimeCard(account: account, media: m, width: width, scope: scope)],
        );
      },
    );
  }
}

class Skeleton extends StatefulWidget {
  final double? width;
  final double height;

  const Skeleton({super.key, this.width, required this.height});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: Container(width: widget.width, height: widget.height, decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(10))),
    );
  }
}

class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
        children: [for (var i = 0; i < 8; i++) const Padding(padding: EdgeInsets.only(right: 12), child: Skeleton(width: 136, height: 200))],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorBox({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: Palette.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class EmptyBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const EmptyBox({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Palette.bright),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted)),
        ],
      ),
    );
  }
}

Color statusColor(String status) => switch (status) {
      'dnd' => const Color(0xFFE5484D),
      'sleep' => const Color(0xFFF0B232),
      'invisible' => const Color(0xFF8A8A94),
      _ => const Color(0xFF2DBE6C),
    };

class PersonAvatar extends StatelessWidget {
  final Account account;
  final int id;
  final String name;
  final Map<String, int> images;
  final double size;
  final bool mine;
  final String? status;

  const PersonAvatar({super.key, required this.account, required this.id, required this.name, required this.images, required this.size, this.mine = false, this.status});

  @override
  Widget build(BuildContext context) {
    final version = images['avatar'];
    final url = version == null ? null : (mine ? account.imageUrl('avatar', version) : account.personImageUrl(id, 'avatar', version));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.card),
          child: url != null
              ? Image.network(url, width: size, height: size, fit: BoxFit.cover, cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(), errorBuilder: (_, _, _) => const SizedBox.shrink())
              : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800)),
        ),
        if (status != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(color: statusColor(status!), shape: BoxShape.circle, border: Border.all(color: Palette.background, width: 2)),
            ),
          ),
      ],
    );
  }
}
