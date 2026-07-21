import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart';

import '../core/theme/app_theme.dart';
import '../indicators/smma.dart';
import '../models/candle.dart';

/// GMP's SMMA 21/50/200 rendered by the chart engine.
///
/// Reuses [MAIndicator]'s line renderer but replaces its simple-MA math
/// with the tested [Smma] implementation — the app owns the overlay
/// layer, which was the deciding requirement of the chart-engine choice.
class SmmaIndicator extends MAIndicator {
  SmmaIndicator()
      : super(
          calcParams: const [21, 50, 200],
          indicatorStyle: const MAStyle(
            maColors: [
              Color(0xFFF2CC5A),
              Color(0xFF35CDAC),
              Color(0xFFB48EE3),
            ],
          ),
        );

  @override
  void calc(List<KLineEntity> dataList) {
    final closes = [for (final e in dataList) e.close];
    final series = [for (final p in calcParams) Smma.compute(closes, p)];
    for (var i = 0; i < dataList.length; i++) {
      dataList[i].maValueList = [for (final s in series) s[i] ?? 0];
    }
  }

  @override
  TextSpan? drawFigure(
      CandleEntity entity, int precision, KChartColors chartColors) {
    final values = entity.maValueList;
    if (values == null || values.isEmpty) return null;
    return TextSpan(children: [
      for (var i = 0; i < values.length; i++)
        if (values[i] != 0)
          TextSpan(
            text:
                'SMMA${calcParams[i]}:${formatNumber(values[i], precision)}  ',
            style: TextStyle(
              fontSize: 11,
              color: indicatorStyle.getMAColor(i),
            ),
          ),
    ]);
  }
}

/// Candlestick chart themed for GMP, fed with app-model candles.
class GmpChart extends StatelessWidget {
  const GmpChart({super.key, required this.datas, required this.intraday});

  final List<KLineEntity> datas;
  final bool intraday;

  static final List<MainIndicator> mainIndicators = [SmmaIndicator()];

  /// Converts app candles to chart entities and pre-computes overlays.
  static List<KLineEntity> prepare(List<Candle> candles) {
    final datas = [
      for (final c in candles)
        KLineEntity.fromCustom(
          time: c.time.millisecondsSinceEpoch,
          open: c.open,
          high: c.high,
          low: c.low,
          close: c.close,
          vol: c.volume,
        ),
    ];
    DataUtil.calculateAll(datas, mainIndicators, const []);
    return datas;
  }

  static const KChartColors _colors = KChartColors(
    bgColor: AppTheme.background,
    selectFillColor: AppTheme.surfaceAlt,
    selectBorderColor: Color(0xFF4A4436),
    gridColor: Color(0xFF262119),
    defaultTextColor: Color(0xFF8F8A7E),
    crossColor: Color(0xFFD4AF37),
    crossTextColor: Color(0xFFEDE8DC),
    maxColor: Color(0xFF8F8A7E),
    minColor: Color(0xFF8F8A7E),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const volHeight = 70.0;
      final base =
          (constraints.maxHeight - volHeight - 70).clamp(220, 1400).toDouble();
      return KChartWidget(
        datas,
        const KChartStyle(),
        _colors,
        isTrendLine: false,
        mainIndicators: mainIndicators,
        volHidden: false,
        fixedLength: 2,
        mBaseHeight: base,
        mSecondaryHeight: volHeight,
        timeFormat: intraday
            ? TimeFormat.YEAR_MONTH_DAY_WITH_HOUR
            : TimeFormat.YEAR_MONTH_DAY,
        detailBuilder: _buildDetail,
      );
    });
  }

  static Widget _buildDetail(KLineEntity e) {
    final dt = DateTime.fromMillisecondsSinceEpoch(e.time ?? 0, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)} UTC';
    final change = e.open == 0 ? 0.0 : (e.close - e.open) / e.open * 100;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A4436), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stamp,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8F8A7E))),
          const SizedBox(height: 6),
          _row('Open', e.open.toStringAsFixed(2)),
          _row('High', e.high.toStringAsFixed(2)),
          _row('Low', e.low.toStringAsFixed(2)),
          _row('Close', e.close.toStringAsFixed(2)),
          _row('Change', '${change.toStringAsFixed(2)}%'),
          _row('Volume', e.vol.toStringAsFixed(2)),
        ],
      ),
    );
  }

  static Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8F8A7E))),
          Text(value,
              style: const TextStyle(fontSize: 11, color: Color(0xFFEDE8DC))),
        ],
      ),
    );
  }
}
