import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The opening: spiral arms pull in, two blades slash into a V, the play mark drops in, and the page opens.
class Intro extends StatefulWidget {
  final VoidCallback onDone;

  const Intro({super.key, required this.onDone});

  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _span(double from, double to, [Curve curve = Curves.linear]) => curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final leaving = _span(0.82, 1, Curves.easeIn);
          return Opacity(
            opacity: 1 - leaving,
            child: ColoredBox(
              color: Palette.background,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.scale(scale: 1 + leaving * 0.5, child: CustomPaint(painter: _IntroPainter(_c.value))),
                  Align(
                    alignment: const Alignment(0, 0.42),
                    child: Opacity(
                      opacity: _span(0.46, 0.62),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _span(0.46, 0.62, Curves.easeOutCubic)) * 14),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('VORTEX ANIME', style: TextStyle(fontFamily: 'Bebas', fontSize: 44, letterSpacing: 4, color: Colors.white, decoration: TextDecoration.none, fontWeight: FontWeight.w400)),
                            Text('YOUR NEXT OBSESSION.', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, letterSpacing: 2, color: Palette.lavender, decoration: TextDecoration.none, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  final double t;

  _IntroPainter(this.t);

  double _span(double from, double to, [Curve curve = Curves.linear]) => curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final unit = math.min(size.width, size.height) / 100 * 0.52;
    Offset at(double x, double y) => center + Offset((x - 50) * unit, (y - 52) * unit);
    Path shape(List<(double, double)> points) => Path()..addPolygon([for (final p in points) at(p.$1, p.$2)], true);

    // Spiral arms winding inward and slowing as the mark lands.
    final turn = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0)) * math.pi * 2.4;
    final armsIn = _span(0, 0.3, Curves.easeOut);
    final maxRadius = size.longestSide * 0.72;
    for (var arm = 0; arm < 5; arm++) {
      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final f = i / 48;
        final radius = maxRadius * (1.25 - armsIn * 0.25) * (0.16 + f * 0.84);
        final angle = arm * math.pi * 2 / 5 + turn + math.log(0.16 + f * 0.84) * 1.9;
        final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.shortestSide * 0.05
          ..color = Color.lerp(Palette.purple, const Color(0xFF2A1466), arm / 5)!.withValues(alpha: armsIn * 0.42),
      );
    }

    // A dark eye opens up so the mark has somewhere to land.
    final eye = _span(0.1, 0.34, Curves.easeOutCubic);
    canvas.drawCircle(center, unit * 62 * eye, Paint()..color = Palette.background);

    // The left blade slashes down from the upper left.
    final left = _span(0.2, 0.36, Curves.easeOutExpo);
    if (left > 0) {
      canvas.save();
      canvas.translate((1 - left) * -unit * 60, (1 - left) * -unit * 130);
      canvas.drawPath(shape(const [(14, 18), (35, 18), (53, 66), (46, 86), (37, 86)]), Paint()..color = Colors.white.withValues(alpha: left));
      canvas.restore();
    }

    // The violet blade cuts up from the lower left, past it.
    final right = _span(0.3, 0.46, Curves.easeOutExpo);
    if (right > 0) {
      canvas.save();
      canvas.translate((1 - right) * -unit * 60, (1 - right) * unit * 130);
      canvas.drawPath(shape(const [(66, 18), (88, 18), (54, 86), (50, 86), (43.5, 69)]), Paint()..color = Palette.bright.withValues(alpha: right));
      canvas.drawPath(shape(const [(81, 18), (88, 18), (54, 86), (50.5, 86)]), Paint()..color = const Color(0xFFEDE9FE).withValues(alpha: right));
      canvas.restore();
    }

    // A flash along the cut the instant they meet.
    final flash = _span(0.38, 0.5);
    if (flash > 0 && flash < 1) {
      final a = at(88 + 30, 18 - 60), b = at(50 - 30, 86 + 60);
      canvas.drawLine(
        Offset.lerp(a, b, (flash - 0.3).clamp(0.0, 1.0))!,
        Offset.lerp(a, b, flash)!,
        Paint()
          ..color = Colors.white.withValues(alpha: 1 - flash)
          ..strokeWidth = unit * 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // The play mark pops in last, with a ring rolling out from it.
    final play = _span(0.44, 0.6, Curves.elasticOut);
    if (play > 0) {
      final pivot = at(50, 30.5);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.scale(play);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.drawPath(shape(const [(46.5, 20), (58, 30.5), (46.5, 41)]), Paint()..color = Colors.white);
      canvas.restore();
    }
    final ring = _span(0.46, 0.84, Curves.easeOutCubic);
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        center,
        unit * 20 + ring * size.longestSide * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 1.2 * (1 - ring) + 0.5
          ..color = Palette.bright.withValues(alpha: (1 - ring) * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}
