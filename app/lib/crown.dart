// The founder crown: a hand-drawn gold crown worn tilted on the side of the profile picture.
// It drops on with a little bounce, then floats, sways, catches a light sweep and twinkles.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Puts [FounderCrown] on the top-right of a round avatar of [avatarSize], sitting on its edge like it's worn.
/// Use inside a `Stack(clipBehavior: Clip.none)` that is exactly the avatar's size.
class CrownOnAvatar extends StatelessWidget {
  final double avatarSize;
  const CrownOnAvatar({super.key, required this.avatarSize});

  @override
  Widget build(BuildContext context) {
    final s = avatarSize;
    final w = s * 0.54;
    final h = w * FounderCrown.aspect;
    // Where the crown sits: on the rim, 55° above the right side, leaning outwards with the head.
    const deg = 55.0;
    final a = deg * math.pi / 180;
    final px = s / 2 + (s / 2) * math.cos(a);
    final py = s / 2 - (s / 2) * math.sin(a);
    final tilt = (90 - deg) * math.pi / 180;
    return Positioned(
      left: px - w * 0.56,
      top: py - h * 0.6,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Transform.rotate(angle: tilt, alignment: const Alignment(0, 0.72), child: FounderCrown(width: w)),
      ),
    );
  }
}

class FounderCrown extends StatefulWidget {
  static const aspect = 0.82;
  final double width;
  const FounderCrown({super.key, required this.width});

  @override
  State<FounderCrown> createState() => _FounderCrownState();
}

class _FounderCrownState extends State<FounderCrown> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _loop.repeat();
    _enter.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Reduce motion" on the device: show it still.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _loop.stop();
      _enter.value = 1;
    } else {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w * FounderCrown.aspect;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _enter]),
        builder: (context, _) {
          final t = _loop.value;
          final e = _enter.value;
          // Entrance: falls from above, lands with a bounce and a little squash.
          final land = Curves.elasticOut.transform(e.clamp(0.0, 1.0));
          final drop = (1 - Curves.easeOutCubic.transform((e * 1.6).clamp(0.0, 1.0))) * -h * 0.9;
          final opacity = (e * 3).clamp(0.0, 1.0);
          // Idle: float and sway.
          final wave = math.sin(t * 2 * math.pi);
          final bob = _still ? 0.0 : wave * h * 0.035;
          final sway = _still ? 0.0 : math.sin(t * 2 * math.pi + 1.1) * 0.045;
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, drop + bob),
              child: Transform.rotate(
                angle: sway,
                alignment: const Alignment(0, 0.8),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * land,
                  alignment: const Alignment(0, 1),
                  child: CustomPaint(size: Size(w, h), painter: _CrownPainter(t: _still ? 0.5 : t, glow: _still ? 0.5 : (wave + 1) / 2)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  final double t; // 0..1 loop phase
  final double glow; // 0..1
  _CrownPainter({required this.t, required this.glow});

  static const _tips = [Offset(0.04, 0.30), Offset(0.27, 0.17), Offset(0.50, 0.06), Offset(0.73, 0.17), Offset(0.96, 0.30)];
  static const _valleys = [Offset(0.17, 0.54), Offset(0.385, 0.47), Offset(0.615, 0.47), Offset(0.83, 0.54)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(Offset o) => Offset(o.dx * w, o.dy * h);

    // Body: five points down into a curved base.
    final body = Path()..moveTo(0.09 * w, 0.88 * h);
    body.lineTo(p(_tips[0]).dx, p(_tips[0]).dy);
    for (var i = 0; i < 4; i++) {
      body.lineTo(p(_valleys[i]).dx, p(_valleys[i]).dy);
      body.lineTo(p(_tips[i + 1]).dx, p(_tips[i + 1]).dy);
    }
    body
      ..lineTo(0.91 * w, 0.88 * h)
      ..quadraticBezierTo(0.5 * w, 0.98 * h, 0.09 * w, 0.88 * h)
      ..close();

    final band = Path()
      ..moveTo(0.075 * w, 0.66 * h)
      ..quadraticBezierTo(0.5 * w, 0.76 * h, 0.925 * w, 0.66 * h)
      ..lineTo(0.91 * w, 0.88 * h)
      ..quadraticBezierTo(0.5 * w, 0.98 * h, 0.09 * w, 0.88 * h)
      ..close();

    // Warm glow and a soft shadow for depth.
    canvas.drawPath(
      body.shift(Offset(0, h * 0.05)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.38)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFFFFC83D).withValues(alpha: 0.28 + 0.27 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * (0.08 + 0.05 * glow)),
    );

    // Gold.
    final rect = Offset.zero & size;
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4C2), Color(0xFFFFD54A), Color(0xFFF0AE12), Color(0xFFC07A00)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ).createShader(rect),
    );
    // Facets: the left half of every point catches more light.
    final facet = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var i = 0; i < 5; i++) {
      final tip = p(_tips[i]);
      final left = i == 0 ? Offset(0.09 * w, 0.66 * h) : p(_valleys[i - 1]);
      final mid = Offset(tip.dx + (i == 0 ? 0.05 * w : 0.0), 0.68 * h);
      canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(left.dx, left.dy)..lineTo(mid.dx, mid.dy)..close(), facet);
    }

    // Band.
    canvas.drawPath(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE07A), Color(0xFFE09A00), Color(0xFFA86400)],
        ).createShader(Rect.fromLTWH(0, 0.62 * h, w, 0.36 * h)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0.09 * w, 0.685 * h)
        ..quadraticBezierTo(0.5 * w, 0.785 * h, 0.91 * w, 0.685 * h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.016
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Light sweep across the gold.
    final sweep = (t * 1.6) % 1.6; // passes in the first part of each loop, then rests
    if (sweep < 1.0) {
      final x = -0.4 * w + sweep * 1.8 * w;
      canvas.save();
      canvas.clipPath(body);
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 0.16 * w, 0)
          ..lineTo(x - 0.12 * w, h)
          ..lineTo(x - 0.28 * w, h)
          ..close(),
        Paint()
          ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0)])
              .createShader(Rect.fromLTWH(x - 0.28 * w, 0, 0.44 * w, h))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
      );
      canvas.restore();
    }

    // Outline.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w * 0.026
      ..color = const Color(0xFF7A4600).withValues(alpha: 0.85);
    canvas.drawPath(body, edge);
    canvas.drawPath(
      Path()
        ..moveTo(0.075 * w, 0.66 * h)
        ..quadraticBezierTo(0.5 * w, 0.76 * h, 0.925 * w, 0.66 * h),
      edge..strokeWidth = w * 0.018,
    );

    // Pearls on the tips.
    for (final tip in _tips) {
      final c = p(tip);
      final r = w * (tip.dx == 0.5 ? 0.058 : 0.046);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(center: const Alignment(-0.35, -0.4), colors: const [Colors.white, Color(0xFFFFF0C8), Color(0xFFD9A441)], stops: const [0.0, 0.45, 1.0])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.012..color = const Color(0xFF7A4600).withValues(alpha: 0.7));
    }

    // Gems: a ruby in the middle, sapphires either side.
    void gem(Offset at, double rw, double rh, List<Color> colors) {
      final c = p(at);
      final r = Rect.fromCenter(center: c, width: rw * w, height: rh * w);
      canvas.drawOval(r.inflate(w * 0.012), Paint()..color = const Color(0xFF6B3B00));
      canvas.drawOval(r, Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.4), colors: colors).createShader(r));
      canvas.drawOval(
        Rect.fromCenter(center: c + Offset(-rw * w * 0.18, -rh * w * 0.2), width: rw * w * 0.32, height: rh * w * 0.24),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    gem(const Offset(0.5, 0.80), 0.15, 0.12, const [Color(0xFFFF8A9A), Color(0xFFE0123A), Color(0xFF7A0018)]);
    gem(const Offset(0.255, 0.775), 0.10, 0.085, const [Color(0xFF9AD8FF), Color(0xFF1E7BFF), Color(0xFF0A2E8A)]);
    gem(const Offset(0.745, 0.775), 0.10, 0.085, const [Color(0xFF9AD8FF), Color(0xFF1E7BFF), Color(0xFF0A2E8A)]);

    // Twinkles near the tips.
    void star(Offset at, double phase, double maxR) {
      final k = math.sin((t + phase) * 2 * math.pi);
      if (k <= 0) return;
      final r = maxR * w * k;
      final c = p(at);
      final s = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(s, Paint()..color = Colors.white.withValues(alpha: 0.95 * k));
      canvas.drawCircle(c, r * 0.5, Paint()..color = const Color(0xFFFFF3B0).withValues(alpha: 0.6 * k)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6));
    }

    star(const Offset(0.60, 0.03), 0.0, 0.10);
    star(const Offset(0.17, 0.13), 0.38, 0.075);
    star(const Offset(0.88, 0.20), 0.7, 0.085);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.t != t || old.glow != glow;
}
