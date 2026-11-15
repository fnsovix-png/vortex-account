import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum DecorKind { none, comet, bear, spider, sakura, galaxy, flame, neon }

class VortexStyle {
  final String id;
  final String name;
  final String blurb;
  final DecorKind kind;
  final Color accent;
  final Color buttonColor;
  final Color buttonIcon;
  final IconData volumeIcon;
  final List<Color> palette;

  const VortexStyle({
    required this.id,
    required this.name,
    required this.blurb,
    required this.kind,
    required this.accent,
    required this.buttonColor,
    required this.buttonIcon,
    required this.volumeIcon,
    required this.palette,
  });
}

const originalAccent = Color(0xFF5CF08F);

const vortexStyles = [
  VortexStyle(
    id: 'original',
    name: 'Original',
    blurb: 'The classic Vortex look',
    kind: DecorKind.none,
    accent: originalAccent,
    buttonColor: Colors.white,
    buttonIcon: Colors.black,
    volumeIcon: Icons.volume_up_rounded,
    palette: [],
  ),
  VortexStyle(
    id: 'comet',
    name: 'Shooting Stars',
    blurb: 'Quiet night sky with falling stars',
    kind: DecorKind.comet,
    accent: Color(0xFF9CC4FF),
    buttonColor: Colors.white,
    buttonIcon: Color(0xFF0B1426),
    volumeIcon: Icons.auto_awesome_rounded,
    palette: [Color(0xFF16284F), Color(0xFF2A1F5C), Color(0xFF0E2A45), Color(0xFF1E1A40)],
  ),
  VortexStyle(
    id: 'bear',
    name: 'Honey Bear',
    blurb: 'Pink and white with a cuddly bear',
    kind: DecorKind.bear,
    accent: Color(0xFFFFA6C9),
    buttonColor: Color(0xFFFFF4F8),
    buttonIcon: Color(0xFFD9578A),
    volumeIcon: Icons.pets_rounded,
    palette: [Color(0xFFE8739F), Color(0xFFF2A6C2), Color(0xFFC95C8E), Color(0xFFE0A0C8)],
  ),
  VortexStyle(
    id: 'spider',
    name: 'Spider',
    blurb: 'Webs in the corners and a spider play button',
    kind: DecorKind.spider,
    accent: Color(0xFFFF4B4B),
    buttonColor: Color(0xFF111114),
    buttonIcon: Color(0xFFFF4B4B),
    volumeIcon: Icons.pest_control_rounded,
    palette: [Color(0xFF8A1420), Color(0xFF3A3A44), Color(0xFF5E0E18), Color(0xFF26262E)],
  ),
  VortexStyle(
    id: 'sakura',
    name: 'Sakura',
    blurb: 'Falling cherry blossom petals',
    kind: DecorKind.sakura,
    accent: Color(0xFFFFC2D6),
    buttonColor: Colors.white,
    buttonIcon: Color(0xFFD65F8C),
    volumeIcon: Icons.local_florist_rounded,
    palette: [Color(0xFFC96A92), Color(0xFF8E6AB8), Color(0xFFE39AB0), Color(0xFF6E5AA0)],
  ),
  VortexStyle(
    id: 'galaxy',
    name: 'Galaxy',
    blurb: 'Twinkling stars and a ringed planet',
    kind: DecorKind.galaxy,
    accent: Color(0xFFA9B8FF),
    buttonColor: Color(0xFFE9ECFF),
    buttonIcon: Color(0xFF2C2A7A),
    volumeIcon: Icons.auto_awesome_rounded,
    palette: [Color(0xFF2C2A8A), Color(0xFF6A2FB0), Color(0xFF14408A), Color(0xFF8A2F90)],
  ),
  VortexStyle(
    id: 'flame',
    name: 'Inferno',
    blurb: 'Rising embers and a blazing button',
    kind: DecorKind.flame,
    accent: Color(0xFFFFA63D),
    buttonColor: Color(0xFFFFE9C9),
    buttonIcon: Color(0xFFC2360E),
    volumeIcon: Icons.local_fire_department_rounded,
    palette: [Color(0xFFB8340E), Color(0xFFD9770F), Color(0xFF7E1A0A), Color(0xFFA8280A)],
  ),
  VortexStyle(
    id: 'neon',
    name: 'Neon Arcade',
    blurb: 'Glowing edges and a retro grid',
    kind: DecorKind.neon,
    accent: Color(0xFF3DF2E0),
    buttonColor: Color(0xFF0B0B14),
    buttonIcon: Color(0xFF3DF2E0),
    volumeIcon: Icons.bolt_rounded,
    palette: [Color(0xFF7A1FA8), Color(0xFF0E7E8A), Color(0xFFB01F7E), Color(0xFF1F3FA8)],
  ),
];

class AppFont {
  final String id;
  final String label;
  final String? family;

  const AppFont(this.id, this.label, this.family);
}

const appFonts = [
  AppFont('system', 'System', null),
  AppFont('poppins', 'Poppins', 'Poppins'),
  AppFont('lato', 'Lato', 'Lato'),
  AppFont('righteous', 'Righteous', 'Righteous'),
  AppFont('chewy', 'Chewy', 'Chewy'),
  AppFont('bebas', 'Bebas Neue', 'BebasNeue'),
  AppFont('abril', 'Abril Fatface', 'AbrilFatface'),
];

class VortexStyles {
  static VortexStyle current = vortexStyles.first;

  static VortexStyle byId(String? id) => vortexStyles.firstWhere((s) => s.id == id, orElse: () => vortexStyles.first);
}

void paintBearFace(Canvas canvas, Offset c, double r, {double alpha = 1}) {
  final fur = Paint()..color = const Color(0xFFFFD3E2).withValues(alpha: alpha);
  final ear = Paint()..color = const Color(0xFFFF9DBF).withValues(alpha: alpha);
  final dark = Paint()..color = const Color(0xFF6B2A45).withValues(alpha: alpha);
  final snout = Paint()..color = Colors.white.withValues(alpha: alpha);
  for (final side in const [-1.0, 1.0]) {
    canvas.drawCircle(c + Offset(side * r * 0.72, -r * 0.72), r * 0.42, fur);
    canvas.drawCircle(c + Offset(side * r * 0.72, -r * 0.72), r * 0.24, ear);
    canvas.drawCircle(c + Offset(side * r * 0.36, -r * 0.12), r * 0.11, dark);
  }
  canvas.drawCircle(c, r, fur);
  for (final side in const [-1.0, 1.0]) {
    canvas.drawCircle(c + Offset(side * r * 0.36, -r * 0.12), r * 0.11, dark);
  }
  canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.3), width: r * 0.8, height: r * 0.56), snout);
  canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.18), width: r * 0.24, height: r * 0.16), dark);
}

void paintPaw(Canvas canvas, Offset c, double r, Color color) {
  final p = Paint()..color = color;
  canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.25), width: r * 1.2, height: r), p);
  for (final o in const [Offset(-0.62, -0.25), Offset(-0.22, -0.65), Offset(0.22, -0.65), Offset(0.62, -0.25)]) {
    canvas.drawCircle(c + o * r, r * 0.27, p);
  }
}

void paintSpider(Canvas canvas, Offset c, double r, Color color) {
  final body = Paint()..color = color;
  final leg = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = max(r * 0.14, 0.8);
  for (var i = 0; i < 4; i++) {
    final spread = -0.8 + i * 0.5;
    for (final side in const [-1.0, 1.0]) {
      final knee = c + Offset(side * r * 1.0, r * (spread - 0.35));
      final foot = c + Offset(side * r * 1.6, r * (spread + 0.35));
      canvas.drawPath(Path()..moveTo(c.dx, c.dy)..lineTo(knee.dx, knee.dy)..lineTo(foot.dx, foot.dy), leg);
    }
  }
  canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.2), width: r * 1.1, height: r * 1.35), body);
  canvas.drawCircle(c + Offset(0, -r * 0.55), r * 0.42, body);
}

void paintWeb(Canvas canvas, Offset corner, double size, Offset dirA, Offset dirB, double alpha) {
  final p = Paint()
    ..color = Colors.white.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  const spokes = 5;
  const rings = 5;
  final angles = [for (var i = 0; i <= spokes; i++) i / spokes];
  Offset point(double t, double reach) => corner + (dirA * (1 - t) + dirB * t) * reach;
  for (final t in angles) {
    canvas.drawLine(corner, point(t, size), p);
  }
  for (var ring = 1; ring <= rings; ring++) {
    final reach = size * ring / rings;
    final path = Path()..moveTo(point(0, reach).dx, point(0, reach).dy);
    for (var i = 1; i < angles.length; i++) {
      final from = point(angles[i - 1], reach);
      final to = point(angles[i], reach);
      final mid = (from + to) / 2;
      final sag = mid + (corner - mid) * 0.12;
      path.quadraticBezierTo(sag.dx, sag.dy, to.dx, to.dy);
    }
    canvas.drawPath(path, p);
  }
}

void paintHeart(Canvas canvas, Offset c, double r, Color color) {
  final path = Path()
    ..moveTo(c.dx, c.dy + r)
    ..cubicTo(c.dx - r * 1.5, c.dy - r * 0.2, c.dx - r * 0.7, c.dy - r * 1.2, c.dx, c.dy - r * 0.35)
    ..cubicTo(c.dx + r * 0.7, c.dy - r * 1.2, c.dx + r * 1.5, c.dy - r * 0.2, c.dx, c.dy + r)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

void paintStar(Canvas canvas, Offset c, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final angle = i * pi / 4 - pi / 2;
    final reach = i.isEven ? r : r * 0.28;
    final p = c + Offset(cos(angle), sin(angle)) * reach;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path..close(), Paint()..color = color);
}

void paintPetal(Canvas canvas, Offset c, double r, double angle, Color color) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(angle);
  final path = Path()
    ..moveTo(0, -r)
    ..quadraticBezierTo(r * 0.9, -r * 0.2, 0, r)
    ..quadraticBezierTo(-r * 0.9, -r * 0.2, 0, -r);
  canvas.drawPath(path, Paint()..color = color);
  canvas.restore();
}

void paintFlame(Canvas canvas, Offset c, double r, Color color) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..cubicTo(c.dx + r * 0.2, c.dy - r * 0.4, c.dx + r * 0.8, c.dy - r * 0.1, c.dx + r * 0.6, c.dy + r * 0.5)
    ..quadraticBezierTo(c.dx, c.dy + r * 1.1, c.dx - r * 0.6, c.dy + r * 0.5)
    ..cubicTo(c.dx - r * 0.8, c.dy, c.dx - r * 0.2, c.dy - r * 0.4, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

class StyledButtonDecor extends StatelessWidget {
  final VortexStyle style;
  final double radius;

  const StyledButtonDecor({super.key, required this.style, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (style.kind == DecorKind.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(size: Size.square(radius * 2), painter: _ButtonDecorPainter(style, radius)),
    );
  }
}

class _ButtonDecorPainter extends CustomPainter {
  final VortexStyle style;
  final double radius;

  const _ButtonDecorPainter(this.style, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = radius;
    switch (style.kind) {
      case DecorKind.comet:
        break;
      case DecorKind.bear:
        final fur = Paint()..color = const Color(0xFFFFD3E2);
        final inner = Paint()..color = const Color(0xFFFF9DBF);
        for (final side in const [-1.0, 1.0]) {
          final ear = c + Offset(side * r * 0.74, -r * 0.8);
          canvas.drawCircle(ear, r * 0.36, fur);
          canvas.drawCircle(ear, r * 0.2, inner);
        }
      case DecorKind.spider:
        final leg = Paint()
          ..color = const Color(0xFF111114)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(r * 0.07, 1.4);
        for (var i = 0; i < 4; i++) {
          final y = -0.62 + i * 0.42;
          for (final side in const [-1.0, 1.0]) {
            final knee = c + Offset(side * r * 1.28, r * (y - 0.28));
            final foot = c + Offset(side * r * 1.6, r * (y + 0.34));
            canvas.drawPath(Path()..moveTo(c.dx + side * r * 0.8, c.dy + r * y)..lineTo(knee.dx, knee.dy)..lineTo(foot.dx, foot.dy), leg);
          }
        }
      case DecorKind.sakura:
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4;
          paintPetal(canvas, c + Offset(cos(a), sin(a)) * r * 1.1, r * 0.24, a + pi / 2, const Color(0xFFFFB7CE));
        }
      case DecorKind.galaxy:
        final ring = Paint()
          ..color = style.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(r * 0.07, 1.4);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.4);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2.9, height: r * 0.8), ring);
        canvas.restore();
        paintStar(canvas, c + Offset(r * 1.05, -r * 0.95), r * 0.2, Colors.white);
        paintStar(canvas, c + Offset(-r * 1.1, r * 0.85), r * 0.14, Colors.white);
      case DecorKind.flame:
        for (var i = -2; i <= 2; i++) {
          final a = -pi / 2 + i * 0.5;
          paintFlame(canvas, c + Offset(cos(a), sin(a)) * r * 1.08, r * (i == 0 ? 0.42 : 0.3), i.isEven ? const Color(0xFFFF7A1A) : const Color(0xFFFFC23D));
        }
      case DecorKind.neon:
        canvas.drawCircle(
          c,
          r * 1.06,
          Paint()
            ..color = style.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(r * 0.07, 1.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 5),
        );
      case DecorKind.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_ButtonDecorPainter old) => old.style.id != style.id || old.radius != radius;
}

class StyleThumbShape extends SliderComponentShape {
  final VortexStyle style;

  const StyleThumbShape(this.style);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    switch (style.kind) {
      case DecorKind.comet:
        paintStar(canvas, center, 9, style.accent);
      case DecorKind.bear:
        paintPaw(canvas, center, 8, style.accent);
      case DecorKind.spider:
        paintSpider(canvas, center, 5, style.accent);
      case DecorKind.sakura:
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * pi / 5;
          paintPetal(canvas, center + Offset(cos(a), sin(a)) * 4.5, 4, a + pi / 2, style.accent);
        }
      case DecorKind.galaxy:
        paintStar(canvas, center, 9, style.accent);
      case DecorKind.flame:
        paintFlame(canvas, center, 8, style.accent);
      case DecorKind.neon:
        canvas.drawCircle(center, 6, Paint()..color = style.accent..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4));
      case DecorKind.none:
        canvas.drawCircle(center, 5, Paint()..color = Colors.white);
    }
  }
}

class DecorLayer extends StatefulWidget {
  final VortexStyle style;

  const DecorLayer({super.key, required this.style});

  @override
  State<DecorLayer> createState() => _DecorLayerState();
}

class _DecorLayerState extends State<DecorLayer> with WidgetsBindingObserver {
  final ValueNotifier<double> _time = ValueNotifier(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync(true);
  }

  void _sync(bool visible) {
    _timer?.cancel();
    final animate = visible && widget.style.kind != DecorKind.none;
    _timer = animate ? Timer.periodic(const Duration(milliseconds: 50), (_) => _time.value += 0.05) : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sync(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
  }

  @override
  void didUpdateWidget(DecorLayer old) {
    super.didUpdateWidget(old);
    if (old.style.kind != widget.style.kind) _sync(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style.kind == DecorKind.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(size: Size.infinite, painter: _DecorPainter(_time, widget.style)),
      ),
    );
  }
}

class _DecorPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final VortexStyle style;

  _DecorPainter(this.time, this.style) : super(repaint: time);

  double _noise(int i, int salt) => (sin(i * 12.9898 + salt * 78.233) * 43758.5453) % 1;

  double _unit(int i, int salt) {
    final n = _noise(i, salt);
    return n < 0 ? n + 1 : n;
  }

  void _paintComets(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    for (var i = 0; i < 40; i++) {
      final twinkle = 0.12 + 0.2 * (0.5 + 0.5 * sin(t * (0.3 + _unit(i, 1) * 0.5) + i));
      canvas.drawCircle(Offset(w * _unit(i, 2), h * _unit(i, 3)), 0.5 + _unit(i, 4) * 0.7, Paint()..color = Colors.white.withValues(alpha: twinkle));
    }
    const count = 5;
    const direction = Offset(-0.72, 0.69);
    final travel = sqrt(w * w + h * h) * 0.55;
    for (var i = 0; i < count; i++) {
      final period = 7 + _unit(i, 5) * 8;
      final phase = (t + _unit(i, 6) * period) / period;
      final cycle = phase.floor();
      final progress = (phase - cycle) / 0.34;
      if (progress > 1) continue;
      final start = Offset(w * (0.2 + _unit(i + cycle * 7, 7) * 0.9), h * (_unit(i + cycle * 7, 8) * 0.55 - 0.05));
      final head = start + direction * travel * Curves.easeOutQuad.transform(progress);
      final length = (travel * 0.42) * sin(pi * progress.clamp(0.0, 1.0));
      final tail = head - direction * length;
      final fade = sin(pi * progress.clamp(0.0, 1.0));
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.4
          ..shader = ui.Gradient.linear(
            tail,
            head,
            [
              style.accent.withValues(alpha: 0),
              style.accent.withValues(alpha: 0.45 * fade),
              Colors.white.withValues(alpha: fade),
            ],
            const [0, 0.65, 1],
          ),
      );
      canvas.drawCircle(head, 5, Paint()..color = style.accent.withValues(alpha: 0.28 * fade)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(head, 1.7, Paint()..color = Colors.white.withValues(alpha: fade));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    switch (style.kind) {
      case DecorKind.comet:
        _paintComets(canvas, size, t);
      case DecorKind.bear:
        for (var i = 0; i < 6; i++) {
          final speed = 0.012 + _unit(i, 1) * 0.02;
          final y = h * (1.1 - ((_unit(i, 2) + t * speed) % 1.2));
          final x = w * _unit(i, 3) + sin(t * 0.7 + i) * 18;
          if (i == 0) {
            paintBearFace(canvas, Offset(x, y), 13 + _unit(i, 4) * 6, alpha: 0.55);
          } else {
            paintHeart(canvas, Offset(x, y), 6 + _unit(i, 4) * 7, const Color(0xFFFFB3CE).withValues(alpha: 0.42));
          }
        }
      case DecorKind.spider:
        final span = min(w, h) * 0.3;
        paintWeb(canvas, Offset(w, 0), span, const Offset(-1, 0), const Offset(0, 1), 0.26);
        paintWeb(canvas, Offset(0, h), span * 0.8, const Offset(1, 0), const Offset(0, -1), 0.2);
        final swing = sin(t * 0.5);
        final anchor = Offset(w * 0.8, 0);
        final drop = h * (0.2 + 0.1 * sin(t * 0.3));
        final body = anchor + Offset(swing * 20, drop);
        canvas.drawLine(anchor, body, Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 1);
        paintSpider(canvas, body, 8, const Color(0xCC111114));
      case DecorKind.sakura:
        for (var i = 0; i < 12; i++) {
          final speed = 0.018 + _unit(i, 1) * 0.03;
          final y = h * (((_unit(i, 2) + t * speed) % 1.1) - 0.05);
          final x = w * _unit(i, 3) + sin(t * 0.8 + i) * 30;
          paintPetal(canvas, Offset(x, y), 5 + _unit(i, 4) * 5, t * 0.7 + i, const Color(0xFFFFC2D6).withValues(alpha: 0.55));
        }
      case DecorKind.galaxy:
        for (var i = 0; i < 28; i++) {
          final glow = 0.25 + 0.6 * (0.5 + 0.5 * sin(t * (0.6 + _unit(i, 1)) + i));
          paintStar(canvas, Offset(w * _unit(i, 2), h * _unit(i, 3)), 2 + _unit(i, 4) * 4, Colors.white.withValues(alpha: glow));
        }
      case DecorKind.flame:
        for (var i = 0; i < 14; i++) {
          final speed = 0.03 + _unit(i, 1) * 0.05;
          final p = (_unit(i, 2) + t * speed) % 1;
          final x = w * _unit(i, 3) + sin(t + i) * 16;
          canvas.drawCircle(Offset(x, h * (1 - p)), 1.5 + _unit(i, 4) * 2.5, Paint()..color = const Color(0xFFFF9A3D).withValues(alpha: (1 - p) * 0.7));
        }
      case DecorKind.neon:
        final p = Paint()
          ..color = style.accent.withValues(alpha: 0.1)
          ..strokeWidth = 1;
        const gap = 46.0;
        final offset = (t * 14) % gap;
        for (var y = h * 0.55 + offset; y < h; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
        for (var x = 0.0; x < w; x += gap) {
          canvas.drawLine(Offset(x, h * 0.55), Offset(x, h), p);
        }
      case DecorKind.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) => old.style.id != style.id;
}
