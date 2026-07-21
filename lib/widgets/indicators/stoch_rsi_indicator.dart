import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../indicators/rsi.dart';

const Color _kColor = AppTheme.gold;
const Color _dColor = Color(0xFF35CDAC);

class _KD {
  const _KD(this.k, this.d);
  final double? k;
  final double? d;
}

/// Stochastic RSI as a k_chart secondary pane (%K gold, %D teal, 0–100).
/// Computed values are held in an [Expando] keyed by candle entity, since
/// the chart's entity has no built-in StochRSI field.
class StochRsiIndicator extends SecondaryIndicator<MACDEntity, RSIStyle> {
  StochRsiIndicator()
      : super(
          name: 'stochRsi',
          shortName: 'StochRSI',
          calcParams: const [14, 14, 3, 3],
          indicatorStyle: const RSIStyle(),
        );

  final Expando<_KD> _store = Expando<_KD>();
  final Paint _paint = Paint()
    ..isAntiAlias = true
    ..strokeWidth = 1.0;

  @override
  void calc(List<KLineEntity> dataList) {
    final s = StochRsi.compute([for (final e in dataList) e.close]);
    for (var i = 0; i < dataList.length; i++) {
      _store[dataList[i]] = _KD(s.k[i], s.d[i]);
    }
  }

  @override
  (double, double) getMaxMinValue(
          KLineEntity entity, double minV, double maxV) =>
      (math.min(minV, 0.0), math.max(maxV, 100.0));

  @override
  TextSpan? drawFigure(
      MACDEntity entity, int precision, KChartColors chartColors) {
    final kd = _store[entity];
    if (kd == null || kd.k == null) return null;
    return TextSpan(children: [
      TextSpan(
          text: 'StochRSI  %K:${formatNumber(kd.k!, precision)}  ',
          style: getTextStyle(_kColor)),
      if (kd.d != null)
        TextSpan(
            text: '%D:${formatNumber(kd.d!, precision)}',
            style: getTextStyle(_dColor)),
    ]);
  }

  @override
  void drawChart(MACDEntity lastPoint, MACDEntity curPoint, double lastX,
      double curX, GetYFunction getY, Canvas canvas, KChartColors chartColors) {
    final a = _store[lastPoint];
    final b = _store[curPoint];
    if (a == null || b == null) return;
    if (a.k != null && b.k != null) {
      canvas.drawLine(Offset(lastX, getY(a.k!)), Offset(curX, getY(b.k!)),
          _paint..color = _kColor);
    }
    if (a.d != null && b.d != null) {
      canvas.drawLine(Offset(lastX, getY(a.d!)), Offset(curX, getY(b.d!)),
          _paint..color = _dColor);
    }
  }

  @override
  void drawVerticalText({
    required Canvas canvas,
    required TextStyle style,
    required double maxValue,
    required double minValue,
    required int fixedLength,
    required Rect chartRect,
  }) {
    void label(String t, double y) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartRect.width - tp.width, y));
    }

    label(maxValue.toStringAsFixed(0), chartRect.top);
    label(minValue.toStringAsFixed(0), chartRect.bottom - 12);
  }
}
