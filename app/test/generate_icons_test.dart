import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vortex/branding.dart';

Future<Uint8List> _renderPng(int size, {bool fullBleed = false}) async {
  final recorder = ui.PictureRecorder();
  paintAppIcon(ui.Canvas(recorder), size.toDouble(), fullBleed: fullBleed);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Uint8List _buildIco(Map<int, Uint8List> images) {
  final header = BytesData(6 + 16 * images.length);
  header.setUint16(2, 1);
  header.setUint16(4, images.length);
  var offset = 6 + 16 * images.length;
  var entry = 6;
  images.forEach((size, png) {
    header.setUint8(entry, size >= 256 ? 0 : size);
    header.setUint8(entry + 1, size >= 256 ? 0 : size);
    header.setUint16(entry + 4, 1);
    header.setUint16(entry + 6, 32);
    header.setUint32(entry + 8, png.length);
    header.setUint32(entry + 12, offset);
    offset += png.length;
    entry += 16;
  });
  final out = BytesBuilder()..add(header.bytes);
  images.values.forEach(out.add);
  return out.toBytes();
}

class BytesData {
  final Uint8List bytes;
  late final ByteData _view = ByteData.sublistView(bytes);

  BytesData(int length) : bytes = Uint8List(length);

  void setUint8(int offset, int value) => _view.setUint8(offset, value);
  void setUint16(int offset, int value) => _view.setUint16(offset, value, Endian.little);
  void setUint32(int offset, int value) => _view.setUint32(offset, value, Endian.little);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate Vortex app icons', () async {
    const targets = {
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'web/favicon.png': 64,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
    };
    for (final entry in targets.entries) {
      File(entry.key).writeAsBytesSync(await _renderPng(entry.value));
    }
    File('web/icons/Icon-maskable-192.png').writeAsBytesSync(await _renderPng(192, fullBleed: true));
    File('web/icons/Icon-maskable-512.png').writeAsBytesSync(await _renderPng(512, fullBleed: true));
    File('web/icons/apple-touch-icon.png').writeAsBytesSync(await _renderPng(180, fullBleed: true));
    final iosIcons = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final iconName = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$');
    for (final file in iosIcons.listSync().whereType<File>()) {
      final match = iconName.firstMatch(file.path);
      if (match == null) continue;
      final pixels = (double.parse(match.group(1)!) * int.parse(match.group(2)!)).round();
      file.writeAsBytesSync(await _renderPng(pixels, fullBleed: true));
    }
    final ico = <int, Uint8List>{};
    for (final size in const [16, 32, 48, 64, 128, 256]) {
      ico[size] = await _renderPng(size);
    }
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(_buildIco(ico));
  });
}
