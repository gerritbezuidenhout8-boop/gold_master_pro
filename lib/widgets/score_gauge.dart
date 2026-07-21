import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Circular 0–100 gauge with the score in the centre — the signature
/// element of the Gold Master Score card.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({super.key, required this.score, this.size = 116});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(score / 100),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1,
                ),
              ),
              const Text('/100',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    const stroke = 9.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2; // top

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawArc(rect, start, 2 * math.pi, false, track);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [AppTheme.goldDeep, AppTheme.gold, AppTheme.goldBright],
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(
        rect, start, 2 * math.pi * fraction.clamp(0, 1), false, progress);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}
