import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../indicators/rsi.dart';
import '../../models/candle.dart';

/// Marks RSI divergences on the main price pane: a green up-triangle
/// beneath a bullish-divergence low, a red down-triangle above a
/// bearish-divergence high. Detection runs in [calc]; flagged candles are
/// held in an [Expando].
class RsiDivergenceIndicator extends MainIndicator<CandleEntity, MAStyle> {
  RsiDivergenceIndicator()
      : super(
          name: 'rsiDivergence',
          shortName: 'Div',
          calcParams: const [14, 5],
          indicatorStyle: const MAStyle(),
        );

  final Expando<DivergenceType> _flags = Expando<DivergenceType>();

  @override
  void calc(List<KLineEntity> dataList) {
    final candles = [
      for (final e in dataList)
        Candle(
          time: DateTime.fromMillisecondsSinceEpoch(e.time ?? 0, isUtc: true),
          open: e.open,
          high: e.high,
          low: e.low,
          close: e.close,
          volume: e.vol,
        ),
    ];
    for (final ev in RsiDivergence.detect(candles)) {
      _flags[dataList[ev.index]] = ev.type;
    }
  }

  @override
  (double, double) getMaxMinValue(
          KLineEntity entity, double minV, double maxV) =>
      (minV, maxV);

  @override
  TextSpan? drawFigure(
          CandleEntity entity, int precision, KChartColors chartColors) =>
      null;

  @override
  void drawChart(CandleEntity lastPoint, CandleEntity curPoint, double lastX,
      double curX, GetYFunction getY, Canvas canvas, KChartColors chartColors) {
    final type = _flags[curPoint];
    if (type == null) return;
    final bull = type == DivergenceType.bullish;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = bull ? AppTheme.bull : AppTheme.bear;
    final path = Path();
    if (bull) {
      final y = getY(curPoint.low) + 6;
      path.moveTo(curX, y);
      path.lineTo(curX - 4, y + 7);
      path.lineTo(curX + 4, y + 7);
    } else {
      final y = getY(curPoint.high) - 6;
      path.moveTo(curX, y);
      path.lineTo(curX - 4, y - 7);
      path.lineTo(curX + 4, y - 7);
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}
