import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Tiny area chart of recent closes; green when rising, red when falling.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.size = const Size(84, 40)});

  final List<double> values;
  final Size size;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox.fromSize(size: size);
    final rising = values.last >= values.first;
    return CustomPaint(
      size: size,
      painter: _SparkPainter(values, rising ? AppTheme.bull : AppTheme.bear),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var min = values.first, max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final dx = size.width / (values.length - 1);
    Offset at(int i) => Offset(
        i * dx, size.height - (values[i] - min) / span * size.height);

    final line = Path()..moveTo(0, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}
