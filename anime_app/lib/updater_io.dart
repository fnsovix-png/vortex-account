import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

bool get canInstallUpdates => Platform.isAndroid || Platform.isWindows;

ReleaseFile? fileFor(Release release) => Platform.isAndroid ? release.android : (Platform.isWindows ? release.windows : null);

Future<File> _download(String url, ReleaseFile package, void Function(double) onProgress) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}${package.file}');
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) throw 'Download failed. Try again.';
    final total = response.contentLength ?? package.size;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
    }
    await sink.close();
  } finally {
    client.close();
  }
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != package.sha256) {
    await file.delete();
    throw 'That download looks damaged. Try again.';
  }
  return file;
}

Future<void> _installWindows(File zip) async {
  final exe = Platform.resolvedExecutable;
  final appDir = File(exe).parent.path;
  final name = exe.split('\\').last;
  final script = File('${zip.parent.path}\\vortex_anime_update.cmd');
  final staging = '${zip.parent.path}\\vortex_anime_update';
  await script.writeAsString('''
@echo off
ping -n 3 127.0.0.1 >nul
taskkill /f /im "$name" >nul 2>&1
rmdir /s /q "$staging" >nul 2>&1
mkdir "$staging"
tar -xf "${zip.path}" -C "$staging"
robocopy "$staging\\VortexAnime" "$appDir" /E /NFL /NDL /NJH /NJS >nul
start "" "$exe"
''');
  await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
  exit(0);
}

Future<void> installUpdate(String url, ReleaseFile package, void Function(double) onProgress) async {
  final file = await _download(url, package, onProgress);
  if (Platform.isWindows) {
    await _installWindows(file);
    return;
  }
  final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
  if (result.type != ResultType.done) throw 'Couldn\'t open the installer. Try again.';
}
