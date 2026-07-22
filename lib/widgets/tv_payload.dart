import '../indicators/rsi.dart';
import '../indicators/smma.dart';
import '../models/candle.dart';

/// Serializes candles + indicator overlays into the JSON shape consumed
/// by assets/tv/chart.html (TradingView Lightweight Charts v5).
Map<String, dynamic> tvChartPayload(
  List<Candle> candles, {
  bool stochRsi = true,
  bool divergence = true,
}) {
  int t(Candle c) => c.time.millisecondsSinceEpoch ~/ 1000;
  final closes = [for (final c in candles) c.close];

  final payload = <String, dynamic>{
    'candles': [
      for (final c in candles)
        {
          'time': t(c),
          'open': c.open,
          'high': c.high,
          'low': c.low,
          'close': c.close,
        },
    ],
    'volume': [
      for (final c in candles)
        {
          'time': t(c),
          'value': c.volume,
          'color': c.close >= c.open
              ? 'rgba(37,198,133,0.35)'
              : 'rgba(229,72,77,0.35)',
        },
    ],
    'smma': [
      for (final period in const [21, 50, 200])
        () {
          final s = Smma.compute(closes, period);
          return [
            for (var i = 0; i < candles.length; i++)
              if (s[i] != null) {'time': t(candles[i]), 'value': s[i]},
          ];
        }(),
    ],
  };

  if (stochRsi) {
    final sr = StochRsi.compute(closes);
    payload['stochK'] = [
      for (var i = 0; i < candles.length; i++)
        if (sr.k[i] != null) {'time': t(candles[i]), 'value': sr.k[i]},
    ];
    payload['stochD'] = [
      for (var i = 0; i < candles.length; i++)
        if (sr.d[i] != null) {'time': t(candles[i]), 'value': sr.d[i]},
    ];
  }

  if (divergence) {
    payload['markers'] = [
      for (final e in RsiDivergence.detect(candles))
        {
          'time': t(candles[e.index]),
          'position':
              e.type == DivergenceType.bullish ? 'belowBar' : 'aboveBar',
          'color': e.type == DivergenceType.bullish ? '#25C685' : '#E5484D',
          'shape':
              e.type == DivergenceType.bullish ? 'arrowUp' : 'arrowDown',
          'text': e.type == DivergenceType.bullish ? 'Bull div' : 'Bear div',
        },
    ];
  }

  return payload;
}
