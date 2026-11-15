import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'player_controller.dart';
import 'theme.dart';
import 'updater.dart';

const appVersion = String.fromEnvironment('VORTEX_VERSION', defaultValue: '1.2.9');

Future<void> checkForUpdates(BuildContext context, PlayerController c) async {
  final prefs = await SharedPreferences.getInstance();
  final release = await c.api.release();
  if (release == null || !context.mounted) return;
  if (canInstallUpdates && isNewerVersion(release.version, appVersion) && packageFor(release) != null) {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => _UpdateDialog(c: c, release: release));
    return;
  }
  final seen = prefs.getString('seenVersion');
  await prefs.setString('seenVersion', appVersion);
  final note = release.notes.where((n) => n.version == appVersion).firstOrNull;
  if (seen != null && seen != appVersion && note != null && context.mounted) {
    await showDialog(context: context, builder: (_) => _NotesDialog(title: 'What\'s new in $appVersion', notes: [note]));
  }
}

Future<void> showUpdateInfo(BuildContext context, PlayerController c) async {
  final release = await c.api.release();
  if (!context.mounted) return;
  if (release != null && canInstallUpdates && isNewerVersion(release.version, appVersion) && packageFor(release) != null) {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => _UpdateDialog(c: c, release: release));
    return;
  }
  await showDialog(
    context: context,
    builder: (_) => _NotesDialog(title: 'You\'re up to date ($appVersion)', notes: release?.notes ?? const []),
  );
}

class _NoteList extends StatelessWidget {
  final List<ReleaseNote> notes;

  const _NoteList(this.notes);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in notes) ...[
          Text('Version ${n.version}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final change in n.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: AppColors.subtle)),
                  Expanded(child: Text(change, style: const TextStyle(color: Color(0xDDFFFFFF)))),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _NotesDialog extends StatelessWidget {
  final String title;
  final List<ReleaseNote> notes;

  const _NotesDialog({required this.title, required this.notes});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: _NoteList(notes))),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final PlayerController c;
  final ReleaseInfo release;

  const _UpdateDialog({required this.c, required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _update() async {
    final package = packageFor(widget.release)!;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await installUpdate(widget.c.api.downloadUrl(package.file), package, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newer = widget.release.notes.where((n) => isNewerVersion(n.version, appVersion)).toList();
    final busy = _progress != null;
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Update to ${widget.release.version}', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You have $appVersion.', style: const TextStyle(color: AppColors.subtle)),
              const SizedBox(height: 12),
              _NoteList(newer),
              if (busy) ...[
                LinearProgressIndicator(value: _progress, color: AppColors.accent),
                const SizedBox(height: 6),
                Text('Downloading ${(_progress! * 100).round()}%', style: const TextStyle(color: AppColors.subtle, fontSize: 13)),
              ],
              if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFF9C9C))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Later')),
        FilledButton(onPressed: busy ? null : _update, child: const Text('Update now')),
      ],
    );
  }
}
