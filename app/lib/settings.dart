import 'package:flutter/material.dart';

import 'appearance.dart';
import 'fx.dart';
import 'player_controller.dart';
import 'profile.dart';
import 'theme.dart';
import 'update_dialog.dart';

void openSettings(BuildContext context, PlayerController c) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(c: c)));
}

class SettingsScreen extends StatelessWidget {
  final PlayerController c;

  const SettingsScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppBackdrop(c: c),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                    children: [
                      Row(
                        children: [
                          Glass(
                            radius: 22,
                            blur: 12,
                            child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                          ),
                          const SizedBox(width: 12),
                          const Text('Settings', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        ],
                      ),
                      const _Heading('Vortex style'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [for (final s in vortexStyles) _StyleCard(style: s, selected: c.style.id == s.id, onTap: () => c.setStyle(s.id))],
                      ),
                      const _Heading('Backgrounds'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Swatch(label: 'Match cover', colors: const [Color(0xFFFF5470), Color(0xFF5CF08F), Color(0xFF4F7CFF)], selected: (c.profile?.theme ?? 'auto') == 'auto', onTap: () => c.saveProfile(theme: 'auto')),
                          for (final p in themePresets) _Swatch(label: p.label, colors: p.colors, selected: c.profile?.theme == p.id, onTap: () => c.saveProfile(theme: p.id)),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _Panel(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.wallpaper_rounded),
                              title: const Text('Your own wallpaper', style: TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(c.wallpaperUrl == null ? 'Add one on your profile. The whole app matches its colors.' : 'On. The whole app matches its colors.'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => openProfileEditor(context, c),
                            ),
                          ],
                        ),
                      ),
                      const _Heading('Font'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in appFonts)
                            ChoiceChip(
                              label: Text(f.label, style: TextStyle(fontFamily: f.family, color: c.fontId == f.id ? Colors.black : Colors.white)),
                              selected: c.fontId == f.id,
                              selectedColor: AppColors.accent,
                              backgroundColor: const Color(0x1FFFFFFF),
                              showCheckmark: false,
                              onSelected: (_) => c.setFont(f.id),
                            ),
                        ],
                      ),
                      const _Heading('Look'),
                      _Panel(
                        children: [
                          _Toggle('Decorations', 'Animated bears, webs, petals and more', c.decorations, (v) => c.setOption('decorations', v)),
                          _Toggle('Moving background', 'Turn off to save battery', c.animatedBackground, (v) => c.setOption('animatedBackground', v)),
                          _Toggle('Vortex ring', 'Spinning rings around the cover', c.showRing, (v) => c.setOption('showRing', v)),
                          _Toggle('Waveform seek bar', 'Off shows a simple line', c.showWave, (v) => c.setOption('showWave', v)),
                          ListTile(
                            title: const Text('Card size', style: TextStyle(fontWeight: FontWeight.w700)),
                            trailing: SegmentedButton<double>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 130, label: Text('S')),
                                ButtonSegment(value: 160, label: Text('M')),
                                ButtonSegment(value: 190, label: Text('L')),
                              ],
                              selected: {c.cardSize},
                              onSelectionChanged: (s) => c.setCardSize(s.first),
                            ),
                          ),
                        ],
                      ),
                      const _Heading('Playback'),
                      _Panel(
                        children: [
                          _Toggle('Autoplay similar songs', 'Keep the music going when the queue ends', c.autoplay, (v) => c.setOption('autoplay', v)),
                        ],
                      ),
                      const _Heading('Keyboard shortcuts'),
                      const _Panel(
                        children: [
                          _Shortcut('Space', 'Play or pause'),
                          _Shortcut('Ctrl + Right / Left', 'Next or previous song'),
                          _Shortcut('Right / Left', 'Skip forward or back 5 seconds'),
                        ],
                      ),
                      const _Heading('About Vortex'),
                      _Panel(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.new_releases_rounded),
                            title: Text('Version $appVersion', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('See what\'s new or check for an update'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => showUpdateInfo(context, c),
                          ),
                        ],
                      ),
                      const _Heading('Account and privacy'),
                      _Panel(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.person_rounded),
                            title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(c.profile?.email ?? ''),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => openProfile(context, c),
                          ),
                          ListTile(
                            leading: const Icon(Icons.lock_rounded),
                            title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w700)),
                            onTap: () => _changePassword(context),
                          ),
                          ListTile(
                            leading: const Icon(Icons.logout_rounded),
                            title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w700)),
                            onTap: () {
                              c.signOut();
                              Navigator.of(context).popUntil((r) => r.isFirst);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFFF7B7B)),
                            title: const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFFF7B7B))),
                            subtitle: const Text('Permanently removes your account, chats and history'),
                            onTap: () => _deleteAccount(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on SettingsScreen {
  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.api.changePassword(current.text, next.text);
      messenger.showSnackBar(const SnackBar(content: Text('Password changed'), width: 260));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), width: 320));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete your account?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('This can\'t be undone. Your profile, history, likes, friends and chats will be gone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5470)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.deleteAccount();
      navigator.popUntil((r) => r.isFirst);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), width: 320));
    }
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;

  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) {
    return Glass(radius: 18, child: Material(color: Colors.transparent, child: Column(children: children)));
  }
}

class _Toggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle(this.title, this.subtitle, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      value: value,
      activeTrackColor: AppColors.accent,
      onChanged: onChanged,
    );
  }
}

class _Shortcut extends StatelessWidget {
  final String keys;
  final String action;

  const _Shortcut(this.keys, this.action);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: Text(keys, style: const TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w600)),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final VortexStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _StyleCard({required this.style, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: style.name,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 170,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0x14FFFFFF),
              border: Border.all(color: selected ? style.accent : const Color(0x24FFFFFF), width: selected ? 2.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 64,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        StyledButtonDecor(style: style, radius: 20),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: style.buttonColor, shape: BoxShape.circle),
                          child: Icon(Icons.play_arrow_rounded, color: style.buttonIcon, size: 28),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(style.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Icon(style.volumeIcon, size: 16, color: style.accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(style.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.subtle, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({required this.label, required this.colors, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 76,
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [...colors, colors.first]),
                    border: Border.all(color: selected ? Colors.white : const Color(0x33FFFFFF), width: selected ? 3 : 1),
                  ),
                  child: selected ? const Icon(Icons.check_rounded) : null,
                ),
                const SizedBox(height: 6),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
