import 'package:flutter/material.dart';

import 'account.dart';
import 'models.dart';
import 'theme.dart';
import 'updater.dart';

const appVersion = String.fromEnvironment('VORTEX_VERSION', defaultValue: '1.0.0');

bool _isNewer(String candidate, String current) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

Future<void> checkForUpdates(BuildContext context, Account account) async {
  final release = await account.release();
  if (release == null || !context.mounted || !canInstallUpdates) return;
  final file = fileFor(release);
  if (file == null || !_isNewer(release.version, appVersion)) return;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _UpdateDialog(release: release, file: file));
}

class _UpdateDialog extends StatefulWidget {
  final Release release;
  final ReleaseFile file;

  const _UpdateDialog({required this.release, required this.file});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await installUpdate('$serverUrl/download/${widget.file.file}', widget.file, (p) {
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
    final busy = _progress != null;
    final notes = widget.release.notes.where((n) => _isNewer(n.version, appVersion));
    return AlertDialog(
      title: Text('Update to ${widget.release.version}', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You have $appVersion.', style: TextStyle(color: Palette.muted)),
              const SizedBox(height: 12),
              for (final n in notes)
                for (final c in n.changes) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $c')),
              if (busy) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress, color: Palette.purple),
                const SizedBox(height: 6),
                Text('Downloading ${(_progress! * 100).round()}%', style: const TextStyle(color: Palette.muted, fontSize: 13)),
              ],
              if (_error != null) Text(_error!, style: const TextStyle(color: Palette.danger)),
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
