import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'appearance.dart';
import 'auth.dart';
import 'branding.dart';
import 'fx.dart';
import 'intro.dart';
import 'media_controls.dart';
import 'now_playing.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'screens.dart';
import 'settings.dart';
import 'social.dart';
import 'theme.dart';
import 'update_dialog.dart';
import 'widgets.dart';

const hostedServer = String.fromEnvironment('VORTEX_SERVER');

String get defaultServer {
  if (kIsWeb) return Uri.base.origin;
  if (hostedServer.isNotEmpty) return hostedServer;
  if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) return '';
  return 'http://127.0.0.1:8000';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(windows: true, android: false, iOS: false, macOS: false, linux: false);
  }
  final isPhone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (isPhone) {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }
  final prefs = await SharedPreferences.getInstance();
  if (kIsWeb) {
    await prefs.setString('server', Uri.base.origin);
  }
  final controller = PlayerController(Api(defaultServer), prefs);
  await attachMediaControls(controller);
  runApp(VortexApp(controller: controller));
}

class VortexApp extends StatefulWidget {
  final PlayerController controller;

  const VortexApp({super.key, required this.controller});

  @override
  State<VortexApp> createState() => _VortexAppState();
}

class _VortexAppState extends State<VortexApp> {
  bool _splashDone = false;
  bool _appVisible = false;

  void _finishIntro() {
    if (!widget.controller.introDone.isCompleted) widget.controller.introDone.complete();
    setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.appearanceVersion,
      builder: (context, _, _) => MaterialApp(
        title: 'Vortex',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(fontFamily: appFonts.firstWhere((f) => f.id == widget.controller.fontId, orElse: () => appFonts.first).family),
        home: Stack(
          fit: StackFit.expand,
          children: [
            // The app loads behind the intro but isn't drawn until it's nearly over.
            Offstage(offstage: !_appVisible, child: Shell(c: widget.controller)),
            if (!_splashDone) IntroOverlay(onReveal: () => setState(() => _appVisible = true), onDone: _finishIntro),
          ],
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  final PlayerController c;

  const Shell({super.key, required this.c});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.c.searchRequest.addListener(_openSearch);
    HardwareKeyboard.instance.addHandler(_onKey);
    widget.c.loadProfile();
    widget.c.prepareServer().then((_) => widget.c.introDone.future).then((_) {
      if (mounted) checkForUpdates(context, widget.c);
    });
  }

  @override
  void dispose() {
    widget.c.searchRequest.removeListener(_openSearch);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorWidgetOfExactType<EditableText>() != null || focus?.widget is EditableText) return false;
    final c = widget.c;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      c.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      ctrl ? c.next() : c.seekBy(const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      ctrl ? c.previous() : c.seekBy(const Duration(seconds: -5));
    } else {
      return false;
    }
    return c.current != null;
  }

  void _openSearch() {
    if (widget.c.searchRequest.value != null) setState(() => _tab = 1);
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => NowPlayingScreen(c: widget.c),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic)),
          child: child,
        ),
      ),
    );
  }

  Widget _pages(PlayerController c) {
    return RepaintBoundary(
      child: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(c: c),
          SearchScreen(c: c),
          LibraryScreen(c: c),
          FriendsScreen(c: c),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                AppBackdrop(c: c, decorations: false),
                if (!c.signedIn)
                  AuthScreen(c: c)
                else
                  isWide(context) ? _desktop(c) : _phone(c),
                if (c.decorations) DecorLayer(style: c.style),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(PlayerController c) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _pages(c),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10 + MediaQuery.paddingOf(context).bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, alignment: Alignment.bottomCenter, child: child),
                child: c.current == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        key: const ValueKey('mini'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MiniPlayer(c: c, onOpen: _openNowPlaying),
                      ),
              ),
              Glass(
                radius: 16,
                opacity: 0.09,
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    for (final (i, icon, label) in const [
                      (0, Icons.home_rounded, 'Home'),
                      (1, Icons.search_rounded, 'Search'),
                      (2, Icons.library_music_rounded, 'Library'),
                      (3, Icons.people_rounded, 'Friends'),
                    ])
                      Expanded(
                        flex: _tab == i ? 5 : 3,
                        child: _NavPill(icon, label, _tab == i, () => setState(() => _tab = i), badge: i == 3 ? c.unreadCount : 0),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktop(PlayerController c) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: RepaintBoundary(child: _Sidebar(c: c, tab: _tab, onTab: (i) => setState(() => _tab = i))),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                    child: Glass(radius: 10, blur: 18, opacity: 0.02, child: _pages(c)),
                  ),
                ),
              ],
            ),
          ),
          if (c.current != null) RepaintBoundary(child: DesktopPlayerBar(c: c, onOpen: _openNowPlaying)),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _NavPill(this.icon, this.label, this.selected, this.onTap, {this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  backgroundColor: const Color(0xFFFF5470),
                  child: Icon(icon, size: 22, color: selected ? Colors.black : Colors.white),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(label, maxLines: 1, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final PlayerController c;
  final int tab;
  final ValueChanged<int> onTab;

  const _Sidebar({required this.c, required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 264,
      child: Glass(
        radius: 10,
        blur: 18,
        opacity: 0.03,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 26, 22, 22),
                child: VortexWordmark(height: 24),
              ),
              _NavItem(Icons.home_rounded, 'Home', tab == 0, () => onTab(0)),
              _NavItem(Icons.search_rounded, 'Search', tab == 1, () => onTab(1)),
              _NavItem(Icons.library_music_rounded, 'Your Library', tab == 2, () => onTab(2)),
              _NavItem(Icons.people_rounded, c.unreadCount > 0 ? 'Friends (${c.unreadCount})' : 'Friends', tab == 3, () => onTab(3)),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 26, 22, 10),
                child: Text('Recently played', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: c.recent.length,
                  itemBuilder: (ctx, i) {
                    final t = c.recent[i];
                    return TrackPress(
                      track: t,
                      c: c,
                      onTap: () => c.playList(c.recent, i),
                      radius: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                        child: Row(
                          children: [
                            Art(t.thumbnail, size: 42, radius: 10),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.subtle)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              _NavItem(Icons.settings_rounded, 'Settings', false, () => openSettings(context, c)),
              InkWell(
                onTap: () => openProfile(context, c),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ProfileAvatar(c: c, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (c.profile?.username ?? '').isEmpty ? 'Your profile' : c.profile!.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem(this.icon, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.subtle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0x1FFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppColors.accent : color),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
