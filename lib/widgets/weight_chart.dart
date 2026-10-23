import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../fmt.dart';
import '../models.dart';

/// Biểu đồ cân nặng: vẽ dần khi đổi dữ liệu, chạm/kéo để xem từng điểm.
class WeightChart extends StatefulWidget {
  final List<Measurement> data;
  final double? goalKg;
  final bool lb;
  final double height;
  final Color color;
  const WeightChart({
    super.key,
    required this.data,
    required this.lb,
    required this.color,
    this.goalKg,
    this.height = 220,
  });

  @override
  State<WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<WeightChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750))
    ..forward();
  int? _sel;

  @override
  void didUpdateWidget(WeightChart old) {
    super.didUpdateWidget(old);
    if (old.data.length != widget.data.length ||
        (old.data.isNotEmpty &&
            widget.data.isNotEmpty &&
            old.data.first.at != widget.data.first.at)) {
      _sel = null;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _pick(Offset p, Size size) {
    if (widget.data.isEmpty) return;
    final geo = _Geo(widget.data, widget.goalKg, size);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < widget.data.length; i++) {
      final d = (geo.x(widget.data[i].at) - p.dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != _sel) setState(() => _sel = best);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, widget.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition, size),
          onHorizontalDragStart: (d) => _pick(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, size),
          onLongPressStart: (d) => _pick(d.localPosition, size),
          onLongPressMoveUpdate: (d) => _pick(d.localPosition, size),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _ChartPainter(
                data: widget.data,
                goal: widget.goalKg,
                lb: widget.lb,
                progress: Curves.easeOutCubic.transform(_c.value),
                selected: _sel,
                line: widget.color,
                grid: cs.outlineVariant.withValues(alpha: 0.5),
                text: cs.onSurfaceVariant,
                surface: cs.surface,
                tipBg: cs.inverseSurface,
                tipFg: cs.onInverseSurface,
                goalColor: cs.tertiary,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Geo {
  static const padL = 44.0, padR = 14.0, padT = 18.0, padB = 26.0;
  final Size size;
  late final double minY, maxY;
  late final int t0, t1;

  _Geo(List<Measurement> d, double? goal, this.size) {
    var lo = d.map((m) => m.weightKg).reduce(min);
    var hi = d.map((m) => m.weightKg).reduce(max);
    if (goal != null) {
      lo = min(lo, goal);
      hi = max(hi, goal);
    }
    final pad = max(0.6, (hi - lo) * 0.15);
    minY = lo - pad;
    maxY = hi + pad;
    t0 = d.first.at.millisecondsSinceEpoch;
    t1 = d.last.at.millisecondsSinceEpoch;
  }

  double x(DateTime t) {
    final w = size.width - padL - padR;
    if (t1 == t0) return padL + w / 2;
    return padL + (t.millisecondsSinceEpoch - t0) / (t1 - t0) * w;
  }

  double y(double kg) {
    final h = size.height - padT - padB;
    return padT + (1 - (kg - minY) / (maxY - minY)) * h;
  }
}

class _ChartPainter extends CustomPainter {
  final List<Measurement> data;
  final double? goal;
  final bool lb;
  final double progress;
  final int? selected;
  final Color line, grid, text, surface, tipBg, tipFg, goalColor;

  _ChartPainter({
    required this.data,
    required this.goal,
    required this.lb,
    required this.progress,
    required this.selected,
    required this.line,
    required this.grid,
    required this.text,
    required this.surface,
    required this.tipBg,
    required this.tipFg,
    required this.goalColor,
  });

  void _label(Canvas c, String s, Offset at, Color color,
      {double size = 11, TextAlign align = TextAlign.left, FontWeight? w}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: w,
              fontFeatures: const [ui.FontFeature.tabularFigures()])),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (align == TextAlign.right) dx -= tp.width;
    if (align == TextAlign.center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final g = _Geo(data, goal, size);

    // Lưới ngang + nhãn trục Y.
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = g.minY + (g.maxY - g.minY) * i / 3;
      final yy = g.y(v);
      canvas.drawLine(Offset(_Geo.padL, yy), Offset(size.width - _Geo.padR, yy), gp);
      _label(canvas, fmtW(v, lb), Offset(_Geo.padL - 6, yy), text,
          align: TextAlign.right);
    }

    // Nhãn trục X: đầu và cuối.
    final by = size.height - _Geo.padB / 2 + 2;
    _label(canvas, fmtDay(data.first.at), Offset(_Geo.padL, by), text);
    if (data.length > 1) {
      _label(canvas, fmtDay(data.last.at),
          Offset(size.width - _Geo.padR, by), text,
          align: TextAlign.right);
    }

    // Đường mục tiêu nét đứt.
    if (goal != null) {
      final yy = g.y(goal!);
      final dp = Paint()
        ..color = goalColor
        ..strokeWidth = 1.5;
      var x = _Geo.padL;
      while (x < size.width - _Geo.padR) {
        canvas.drawLine(Offset(x, yy), Offset(min(x + 6, size.width - _Geo.padR), yy), dp);
        x += 11;
      }
      _label(canvas, 'Mục tiêu', Offset(size.width - _Geo.padR, yy - 9),
          goalColor,
          align: TextAlign.right, size: 10, w: FontWeight.w600);
    }

    final pts = [for (final m in data) Offset(g.x(m.at), g.y(m.weightKg))];
    final clipW = _Geo.padL + (size.width - _Geo.padL) * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipW, size.height));

    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      final area = Path.from(path)
        ..lineTo(pts.last.dx, size.height - _Geo.padB)
        ..lineTo(pts.first.dx, size.height - _Geo.padB)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.28), line.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, _Geo.padT, size.width, size.height)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
    if (pts.length <= 40) {
      for (final p in pts) {
        canvas.drawCircle(p, 3, Paint()..color = line);
      }
    }
    canvas.drawCircle(pts.last, 6, Paint()..color = surface);
    canvas.drawCircle(pts.last, 4.5, Paint()..color = line);
    canvas.restore();

    // Điểm được chọn + tooltip.
    final s = selected;
    if (s != null && s < data.length && progress > 0.99) {
      final p = pts[s];
      canvas.drawLine(Offset(p.dx, _Geo.padT), Offset(p.dx, size.height - _Geo.padB),
          Paint()
            ..color = text.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      canvas.drawCircle(p, 7, Paint()..color = surface);
      canvas.drawCircle(p, 5, Paint()..color = line);

      final m = data[s];
      final tp1 = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: '${fmtWU(m.weightKg, lb, digits: 2)}\n',
              style: TextStyle(
                  color: tipFg, fontSize: 13, fontWeight: FontWeight.w700)),
          TextSpan(
              text: fmtDate(m.at),
              style: TextStyle(color: tipFg.withValues(alpha: 0.8), fontSize: 11)),
        ]),
        textDirection: TextDirection.ltr,
      )..layout();
      const pad = 8.0;
      final w = tp1.width + pad * 2, h = tp1.height + pad * 2;
      var left = p.dx - w / 2;
      left = left.clamp(2.0, max(2.0, size.width - w - 2));
      var top = p.dy - h - 12;
      if (top < 0) top = p.dy + 12;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h), const Radius.circular(8));
      canvas.drawRRect(r, Paint()..color = tipBg);
      tp1.paint(canvas, Offset(left + pad, top + pad));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.progress != progress ||
      o.selected != selected ||
      o.data != data ||
      o.goal != goal ||
      o.lb != lb ||
      o.line != line ||
      o.text != text;
}
