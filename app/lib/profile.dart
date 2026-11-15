import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'appearance.dart';
import 'fx.dart';
import 'models.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'social.dart';
import 'theme.dart';
import 'widgets.dart';

const _bannerHeight = 220.0;
const _avatarSize = 112.0;

void openProfile(BuildContext context, PlayerController c) {
  final me = c.profile;
  if (me == null) {
    openProfileEditor(context, c);
    return;
  }
  _pushProfilePage(context, PersonScreen(c: c, id: me.id, name: me.username));
}

Future<void> openProfileEditor(BuildContext context, PlayerController c) => _pushProfilePage(context, ProfileScreen(c: c));

Future<void> _pushProfilePage(BuildContext context, Widget page) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

class AppBackdrop extends StatelessWidget {
  final PlayerController c;
  final bool decorations;

  const AppBackdrop({super.key, required this.c, this.decorations = true});

  @override
  Widget build(BuildContext context) {
    final wallpaper = c.wallpaperUrl;
    final screen = MediaQuery.sizeOf(context);
    final longSide = (screen.longestSide * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Stack(
      fit: StackFit.expand,
      children: [
        // A wallpaper covers the moving colors almost completely, and holding them
        // still means the panels on top don't have to re-blur it on every frame.
        MeshBackground(palette: c.palette, animate: c.animatedBackground && wallpaper == null),
        if (wallpaper != null) ...[
          Image.network(wallpaper, key: ValueKey(wallpaper), fit: BoxFit.cover, cacheWidth: longSide, opacity: const AlwaysStoppedAnimation(0.62), errorBuilder: (_, _, _) => const SizedBox.shrink()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x99000000), Color(0xCC000000)],
              ),
            ),
          ),
        ],
        if (decorations && c.decorations) DecorLayer(style: c.style),
      ],
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final PlayerController c;
  final double size;
  final bool showStatus;

  const ProfileAvatar({super.key, required this.c, required this.size, this.showStatus = true});

  @override
  Widget build(BuildContext context) {
    final url = c.imageUrl('avatar');
    final name = c.profile?.username ?? '';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ValueListenableBuilder<Color>(
          valueListenable: c.tint,
          builder: (context, tint, _) => Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, HSLColor.fromColor(tint).withLightness(0.2).toColor()]),
            ),
            child: url != null
                ? Image.network(url, key: ValueKey(url), width: size, height: size, fit: BoxFit.cover, cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil())
                : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900)),
          ),
        ),
        if (c.profile?.crown == true)
          Positioned(
            top: -size * 0.22,
            right: -size * 0.06,
            child: const CrownBadge(),
          ),
        if (showStatus && c.profile != null)
          Positioned(right: -1, bottom: -1, child: StatusDot(status: c.profile!.status, size: size * 0.34)),
      ],
    );
  }
}

class ImageDropZone extends StatefulWidget {
  final ValueChanged<Uint8List> onImage;
  final Widget Function(bool active) builder;

  const ImageDropZone({super.key, required this.onImage, required this.builder});

  @override
  State<ImageDropZone> createState() => _ImageDropZoneState();
}

class _ImageDropZoneState extends State<ImageDropZone> {
  bool _dragging = false;
  bool _hover = false;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes != null) widget.onImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final touchOnly = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (touchOnly) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: _pick, child: widget.builder(false));
    }
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) widget.onImage(await details.files.first.readAsBytes());
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pick,
          child: widget.builder(_dragging || _hover),
        ),
      ),
    );
  }
}

class _DropHint extends StatelessWidget {
  final bool visible;
  final String label;

  const _DropHint({required this.visible, required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          color: const Color(0x99000000),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_photo_alternate_rounded, size: 26),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final PlayerController c;

  const ProfileScreen({super.key, required this.c});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.c.profile?.username ?? '');
  late final TextEditingController _pronouns = TextEditingController(text: widget.c.profile?.pronouns ?? '')..addListener(_refreshAbout);
  late final TextEditingController _quote = TextEditingController(text: widget.c.profile?.quote ?? '')..addListener(_refreshAbout);
  late final TextEditingController _bio = TextEditingController(text: widget.c.profile?.bio ?? '')..addListener(_refreshAbout);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pronouns.dispose();
    _quote.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _refreshAbout() => setState(() {});

  bool get _aboutChanged {
    final p = widget.c.profile;
    return _pronouns.text.trim() != (p?.pronouns ?? '') || _quote.text.trim() != (p?.quote ?? '') || _bio.text.trim() != (p?.bio ?? '');
  }

  Widget _aboutField(TextEditingController controller, String label, String hint, int maxLength, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        minLines: 1,
        maxLines: maxLines,
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.subtle),
          labelStyle: const TextStyle(color: AppColors.subtle),
          floatingLabelStyle: TextStyle(color: AppColors.accent),
          filled: true,
          fillColor: const Color(0x14FFFFFF),
          counterStyle: const TextStyle(color: AppColors.subtle, fontSize: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), duration: const Duration(seconds: 3)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Clear listening history?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('Your recommendations start over. Liked Songs stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (yes == true) _run(widget.c.clearHistory);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final side = isWide(context) ? 40.0 : 18.0;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AppBackdrop(c: c),
              ListView(
                padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
                children: [
                  _header(context, side),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: side),
                        child: _body(context),
                      ),
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
              if (_busy) Align(alignment: Alignment.topCenter, child: LinearProgressIndicator(minHeight: 2, color: AppColors.accent, backgroundColor: Colors.transparent)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, double side) {
    final c = widget.c;
    final banner = c.imageUrl('banner');
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: _bannerHeight + top + _avatarSize / 2,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _bannerHeight + top,
            child: ImageDropZone(
              onImage: (b) => _run(() => c.setProfileImage('banner', b)),
              builder: (active) => Stack(
                fit: StackFit.expand,
                children: [
                  if (banner != null)
                    Image.network(banner, key: ValueKey(banner), fit: BoxFit.cover)
                  else
                    ValueListenableBuilder<List<Color>>(
                      valueListenable: c.palette,
                      builder: (context, colors, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors.take(3).toList()),
                        ),
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x8C000000)],
                      ),
                    ),
                  ),
                  _DropHint(visible: active, label: isWide(context) ? 'Drop a banner here or click to choose' : 'Tap to choose a banner'),
                ],
              ),
            ),
          ),
          Positioned(
            left: side,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
              child: ClipOval(
                child: ImageDropZone(
                  onImage: (b) => _run(() => c.setProfileImage('avatar', b)),
                  builder: (active) => Stack(
                    children: [
                      ProfileAvatar(c: c, size: _avatarSize, showStatus: false),
                      Positioned.fill(child: _DropHint(visible: active, label: '')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = widget.c;
    final p = c.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          maxLength: 30,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1),
          cursorColor: AppColors.accent,
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Your name', counterText: '', isDense: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => _run(() => c.saveProfile(username: v)),
          onTapOutside: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_name.text.trim() != (p?.username ?? '') && _name.text.trim().isNotEmpty) _run(() => c.saveProfile(username: _name.text));
          },
        ),
        Text(
          '${p?.plays ?? 0} ${p?.plays == 1 ? 'play' : 'plays'}  •  ${c.liked.length} liked ${c.liked.length == 1 ? 'song' : 'songs'}',
          style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w600),
        ),
        const _SectionTitle('Status'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: const Color(0x12FFFFFF), borderRadius: BorderRadius.circular(8)),
            child: StatusMenu(c: c),
          ),
        ),
        const _SectionTitle('About you'),
        _aboutField(_pronouns, 'Pronouns', 'Add your pronouns', 30),
        _aboutField(_quote, 'Quote', 'A line that sounds like you', 120, maxLines: 2),
        _aboutField(_bio, 'Bio', 'Tell people about yourself', 300, maxLines: 5),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _aboutChanged && !_busy
                ? () => _run(() => c.saveProfile(pronouns: _pronouns.text.trim(), quote: _quote.text.trim(), bio: _bio.text.trim()))
                : null,
            child: const Text('Save'),
          ),
        ),
        if (c.topArtists.isNotEmpty) ...[
          const _SectionTitle('Your top artists'),
          TopArtistsRow(c: c, padding: EdgeInsets.zero, onTap: (a) {
            c.requestSearch(a.name);
            Navigator.pop(context);
          }),
        ],
        const _SectionTitle('Wallpaper'),
        _wallpaperCard(context),
        const _SectionTitle('Privacy'),
        Glass(
          radius: 18,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Styles, backgrounds, fonts and more'),
                  onTap: () => openSettings(context, c),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Clear listening history', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Your history is only used for your recommendations.'),
                  onTap: _confirmClear,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wallpaperCard(BuildContext context) {
    final c = widget.c;
    final wallpaper = c.wallpaperUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: ImageDropZone(
              onImage: (b) => _run(() => c.setProfileImage('wallpaper', b)),
              builder: (active) => Stack(
                fit: StackFit.expand,
                children: [
                  if (wallpaper != null)
                    Image.network(wallpaper, key: ValueKey(wallpaper), fit: BoxFit.cover)
                  else
                    Glass(radius: 18, blur: 10, child: const SizedBox.expand()),
                  _DropHint(visible: active || wallpaper == null, label: isWide(context) ? 'Drop a wallpaper here or click to choose' : 'Tap to choose a wallpaper'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          wallpaper == null ? 'App colors adapt to your wallpaper automatically.' : 'App colors now match this wallpaper.',
          style: const TextStyle(color: AppColors.subtle, fontSize: 13),
        ),
        if (wallpaper != null)
          TextButton.icon(
            onPressed: () => _run(() => c.removeProfileImage('wallpaper')),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Remove wallpaper'),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
    );
  }
}

class TopArtistsRow extends StatelessWidget {
  final PlayerController c;
  final EdgeInsets padding;
  final ValueChanged<TopArtist> onTap;

  const TopArtistsRow({super.key, required this.c, required this.padding, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 134,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: c.topArtists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final a = c.topArtists[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(a),
            child: SizedBox(
              width: 100,
              child: Column(
                children: [
                  Art(a.thumbnail, size: 100, radius: 50),
                  const SizedBox(height: 8),
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


/// Gold crown for the founder: floats, glows and swings a little, forever.
class CrownBadge extends StatefulWidget {
  final double size;
  const CrownBadge({super.key, this.size = 34});
  @override
  State<CrownBadge> createState() => _CrownBadgeState();
}

class _CrownBadgeState extends State<CrownBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -2.5 * t),
          child: Transform.rotate(
            angle: 0.10 * (t - 0.5),
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: s * 1.15, height: s * 1.15,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: const Color(0xFFFFD35C).withValues(alpha: 0.35 + 0.3 * t), blurRadius: 12 + 10 * t, spreadRadius: 1),
                ]),
              ),
              ShaderMask(
                shaderCallback: (r) => LinearGradient(colors: [
                  Color.lerp(const Color(0xFFFFE082), const Color(0xFFFFF8D6), t)!,
                  Color.lerp(const Color(0xFFFFB300), const Color(0xFFFFD54F), t)!,
                ], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r),
                child: Text('👑', style: TextStyle(fontSize: s, height: 1)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
