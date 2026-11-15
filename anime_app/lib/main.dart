import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'auth.dart';
import 'discover.dart';
import 'home.dart';
import 'intro.dart';
import 'social.dart';
import 'theme.dart';
import 'ui.dart';
import 'update_dialog.dart';
import 'watchlist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent));
  final account = Account(await SharedPreferences.getInstance());
  account.load();
  runApp(VortexAnimeApp(account: account));
}

class VortexAnimeApp extends StatefulWidget {
  final Account account;

  const VortexAnimeApp({super.key, required this.account});

  @override
  State<VortexAnimeApp> createState() => _VortexAnimeAppState();
}

class _VortexAnimeAppState extends State<VortexAnimeApp> {
  bool _intro = true;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return MaterialApp(
      title: 'Vortex Anime',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          ?child,
          if (_intro) Intro(onDone: () => setState(() => _intro = false)),
        ],
      ),
      home: ListenableBuilder(
        listenable: account,
        builder: (context, _) => account.signedIn ? Shell(account: account) : AuthScreen(account: account),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  final Account account;

  const Shell({super.key, required this.account});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _discover = DiscoverController();

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.explore_rounded, 'Discover'),
    (Icons.bookmark_rounded, 'My list'),
    (Icons.forum_rounded, 'Friends'),
    (Icons.person_rounded, 'You'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdates(context, widget.account);
    });
  }

  @override
  void dispose() {
    _discover.dispose();
    super.dispose();
  }

  void _showDiscover({bool playsHere = false, String? genre}) {
    _discover.show(playsHere: playsHere, genre: genre);
    setState(() => _tab = 1);
  }

  Widget _icon(int index, double size, Color color) {
    final icon = Icon(_items[index].$1, size: size, color: color);
    if (index != 3) return icon;
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final unread = widget.account.unread;
        return Badge(isLabelVisible: unread > 0, label: Text('$unread'), backgroundColor: Palette.purple, child: icon);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final pages = IndexedStack(
      index: _tab,
      children: [
        HomeScreen(account: a, onDiscover: _showDiscover),
        DiscoverScreen(account: a, controller: _discover),
        WatchlistScreen(account: a),
        FriendsScreen(account: a),
        ProfileScreen(account: a),
      ],
    );
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) setState(() => _tab = 0);
      },
      child: Scaffold(
      extendBody: true,
      body: pages,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xF2171522),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Palette.line),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      selected: _tab == i,
                      label: _items[i].$2,
                      icon: _icon(i, 23, _tab == i ? Colors.white : Palette.muted),
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _tab = i);
                      },
                    ),
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

class _NavItem extends StatelessWidget {
  final bool selected;
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  const _NavItem({required this.selected, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Pressable(
        scale: 0.9,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? Palette.purple : Colors.transparent, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              if (selected) Text(label, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}
