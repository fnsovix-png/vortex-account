import 'dart:io';

import 'package:http/http.dart' as http;

const _healthUrl = 'http://127.0.0.1:8000/health';
const _startupAttempts = 60;

Future<void>? _ready;

Future<void> ensureServer() => _ready ??= _start();

Future<bool> _healthy() async {
  try {
    final res = await http.get(Uri.parse(_healthUrl)).timeout(const Duration(seconds: 1));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<void> _start() async {
  if (!Platform.isWindows || await _healthy()) return;
  final server = File('${File(Platform.resolvedExecutable).parent.path}\\server\\VortexServer.exe');
  if (!server.existsSync()) return;
  await Process.start(server.path, const [], workingDirectory: server.parent.path, mode: ProcessStartMode.detached);
  for (var i = 0; i < _startupAttempts; i++) {
    if (await _healthy()) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
