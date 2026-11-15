import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';


const double wordmarkAspect = 6.2;
const double _skew = 0.14;
const double _gap = 0.13;

Path _poly(List<List<double>> points) {
  return Path()..addPolygon([for (final p in points) Offset(p[0], p[1])], true);
}

Path _letterV() => _poly([[0, 0], [0.26, 0], [0.47, 0.66], [0.68, 0], [0.94, 0], [0.6, 1], [0.34, 1]]);

Path _letterO() {
  return Path()
    ..addOval(const Rect.fromLTWH(0, 0, 1, 1))
    ..addOval(Rect.fromCircle(center: const Offset(0.54, 0.46), radius: 0.235));
}

Path _letterR() {
  return Path()
    ..addRRect(RRect.fromLTRBAndCorners(0, 0, 0.82, 0.66, topRight: Radius.circular(0.33), bottomRight: Radius.circular(0.33)))
    ..addRRect(RRect.fromLTRBAndCorners(0.25, 0.2, 0.56, 0.46, topRight: Radius.circular(0.13), bottomRight: Radius.circular(0.13)))
    ..addRect(const Rect.fromLTWH(0, 0.66, 0.25, 0.34))
    ..addPolygon(const [Offset(0.34, 0.66), Offset(0.6, 0.66), Offset(0.9, 1), Offset(0.62, 1)], true);
}

Path _letterT() {
  return Path()
    ..addRect(const Rect.fromLTWH(0, 0, 0.84, 0.21))
    ..addRect(const Rect.fromLTWH(0.295, 0.21, 0.25, 0.79));
}

Path _letterE() {
  return Path()
    ..addRect(const Rect.fromLTWH(0, 0, 0.25, 1))
    ..addRect(const Rect.fromLTWH(0.25, 0, 0.51, 0.21))
    ..addRect(const Rect.fromLTWH(0.25, 0.395, 0.43, 0.2))
    ..addRect(const Rect.fromLTWH(0.25, 0.79, 0.51, 0.21));
}

Path _letterX() {
  return Path()
    ..addPolygon(const [Offset(0, 0), Offset(0.28, 0), Offset(0.94, 1), Offset(0.66, 1)], true)
    ..addPolygon(const [Offset(0.66, 0), Offset(0.94, 0), Offset(0.28, 1), Offset(0, 1)], true);
}

const _widths = [0.94, 1.0, 0.9, 0.84, 0.76, 0.94];

void paintWordmark(Canvas canvas, Rect box, Paint paint) {
  final natural = _widths.reduce((a, b) => a + b) + _gap * (_widths.length - 1) + _skew;
  final scale = min(box.width / natural, box.height);
  final left = box.left + (box.width - natural * scale) / 2;
  final top = box.top + (box.height - scale) / 2;
  final matrix = Float64List.fromList([
    scale, 0, 0, 0,
    -_skew * scale, scale, 0, 0,
    0, 0, 1, 0,
    left + _skew * scale, top, 0, 1,
  ]);
  final letters = [_letterV(), _letterO(), _letterR(), _letterT(), _letterE(), _letterX()];
  var x = 0.0;
  for (var i = 0; i < letters.length; i++) {
    final path = letters[i].shift(Offset(x, 0)).transform(matrix);
    if (i == 1 || i == 2) path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
    x += _widths[i] + _gap;
  }
}

/// Draws the headphones-on-a-V app icon. iOS and maskable web icons need
/// [fullBleed], because those systems round the corners themselves.
void paintAppIcon(Canvas canvas, double size, {bool fullBleed = false}) {
  const ink = Color(0xFF071307);
  const design = 512.0;
  canvas.save();
  canvas.scale(size / design);

  const square = Rect.fromLTWH(0, 0, design, design);
  final tile = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB6FF3C), Color(0xFF2FD64A)],
    ).createShader(square);
  if (fullBleed) {
    canvas.drawRect(square, tile);
  } else {
    canvas.drawRRect(RRect.fromRectAndRadius(square, const Radius.circular(114)), tile);
  }

  final band = Path()
    ..moveTo(84, 262)
    ..lineTo(84, 224)
    ..arcToPoint(const Offset(428, 224), radius: const Radius.circular(172))
    ..lineTo(428, 262);
  canvas.drawPath(
    band,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 36
      ..color = ink,
  );

  final solid = Paint()..color = ink;
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(62, 228, 54, 116), const Radius.circular(27)), solid);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(396, 228, 54, 116), const Radius.circular(27)), solid);

  final v = Path()
    ..moveTo(170, 188)
    ..relativeLineTo(70, 0)
    ..relativeLineTo(20, 106)
    ..relativeLineTo(70, -106)
    ..relativeLineTo(46, 0)
    ..lineTo(282, 386)
    ..relativeCubicTo(-8, 14, -20, 22, -34, 22)
    ..relativeLineTo(-30, 0)
    ..relativeCubicTo(-10, 0, -18, -6, -20, -16)
    ..close();
  canvas.drawPath(v, solid);
  canvas.restore();
}

class VortexWordmark extends StatelessWidget {
  final double height;
  final Color? color;

  const VortexWordmark({super.key, required this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vortex',
      child: CustomPaint(size: Size(height * wordmarkAspect, height), painter: _WordmarkPainter(color)),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  final Color? color;

  const _WordmarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    if (color != null) {
      paint.color = color!;
    } else {
      paint.color = Colors.white;
    }
    paintWordmark(canvas, rect, paint);
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.color != color;
}
