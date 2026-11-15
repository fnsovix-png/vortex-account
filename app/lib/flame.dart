import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FlameTier {
  final int from;
  final String name;
  final Color core;
  final Color mid;
  final Color outer;

  const FlameTier(this.from, this.name, this.core, this.mid, this.outer);
}

const flameTiers = [
  FlameTier(1, 'Orange', Color(0xFFFFF0B8), Color(0xFFFF9A1F), Color(0xFFE5390B)),
  FlameTier(3, 'Gold', Color(0xFFFFFBE0), Color(0xFFFFD21F), Color(0xFFF08A00)),
  FlameTier(7, 'Pink', Color(0xFFFFE6F2), Color(0xFFFF4FA3), Color(0xFFC4125F)),
  FlameTier(14, 'Blue', Color(0xFFE2F6FF), Color(0xFF38B6FF), Color(0xFF0B4FE0)),
  FlameTier(30, 'Purple', Color(0xFFF2E4FF), Color(0xFFA855F7), Color(0xFF5B16C9)),
  FlameTier(60, 'Green', Color(0xFFE8FFE9), Color(0xFF34E37E), Color(0xFF078A5B)),
  FlameTier(100, 'White', Color(0xFFFFFFFF), Color(0xFFD8E8FF), Color(0xFF7A8CFF)),
];

FlameTier flameTierFor(int days) => flameTiers.lastWhere((t) => days >= t.from, orElse: () => flameTiers.first);

FlameTier? nextFlameTier(int days) {
  for (final tier in flameTiers) {
    if (tier.from > days) return tier;
  }
  return null;
}

class StreakFlame extends StatefulWidget {
  final int days;
  final double size;
  final bool animate;

  const StreakFlame({super.key, required this.days, required this.size, this.animate = true});

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;

  final ValueNotifier<double> _time = ValueNotifier(1.7);
  late final Ticker _ticker = createTicker((elapsed) => _time.value = 1.7 + elapsed.inMicroseconds / 1e6);
  ui.FragmentShader? _shader;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.animate) _ticker.start();
  }

  Future<void> _load() async {
    try {
      _program ??= ui.FragmentProgram.fromAsset('shaders/flame.frag');
      final shader = (await _program!).fragmentShader();
      if (mounted) setState(() => _shader = shader);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = flameTierFor(widget.days);
    final shader = _shader;
    if (shader == null) {
      return _failed ? Icon(Icons.local_fire_department_rounded, size: widget.size, color: tier.mid) : SizedBox.square(dimension: widget.size);
    }
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: _FlamePainter(shader, _time, tier)),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final FlameTier tier;

  _FlamePainter(this.shader, this.time, this.tier) : super(repaint: time);

  int _color(int at, Color color) {
    shader.setFloat(at, color.r);
    shader.setFloat(at + 1, color.g);
    shader.setFloat(at + 2, color.b);
    return at + 3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time.value);
    var at = _color(3, tier.core);
    at = _color(at, tier.mid);
    _color(at, tier.outer);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.tier != tier || old.shader != shader;
}

class StreakBadge extends StatelessWidget {
  final int days;
  final double size;

  const StreakBadge({super.key, required this.days, this.size = 18});

  @override
  Widget build(BuildContext context) {
    if (days <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreakFlame(days: days, size: size, animate: false),
        const SizedBox(width: 2),
        Text('$days', style: TextStyle(color: flameTierFor(days).mid, fontWeight: FontWeight.w800, fontSize: size * 0.72)),
      ],
    );
  }
}
