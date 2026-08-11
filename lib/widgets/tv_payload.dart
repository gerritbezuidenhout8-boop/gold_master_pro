import '../indicators/rsi.dart';
import '../indicators/smma.dart';
import '../models/candle.dart';
import '../models/trade_signal.dart';
import '../services/market_data.dart';

/// The running signal's levels as TradingView price lines.
///
/// The stop is the **live** one: once it ratchets, the line moves with it,
/// which is the whole point of being able to see the trade on the chart.
/// Returns an empty list when nothing is running.
List<Map<String, dynamic>> signalPriceLines(TradeSignal? signal) {
  if (signal == null || !signal.isOpen) return const [];
  final plan = signal.plan;
  final trailing = signal.isTrailing;
  return [
    {
      'price': plan.entry,
      'color': '#E3B84C',
      'style': 2, // dashed
      'title': '${plan.action} ${plan.entry.toStringAsFixed(2)}',
    },
    {
      'price': signal.trailingStop,
      'color': '#E5484D',
      'style': trailing ? 0 : 2, // solid once it is actually trailing
      'title': trailing ? 'SL (trailing)' : 'SL',
    },
    {
      'price': plan.tp1,
      'color': '#25C685',
      'style': 0,
      'title': 'TP1',
    },
    {
      'price': plan.tp2,
      'color': '#25C685',
      'style': 2, // the untracked runner, drawn lighter
      'title': 'TP2',
    },
  ];
}

/// Serializes candles + indicator overlays into the JSON shape consumed
/// by assets/tv/chart.html (TradingView Lightweight Charts v5).
Map<String, dynamic> tvChartPayload(
  List<Candle> candles, {
  bool stochRsi = true,
  bool divergence = true,
  TradeSignal? signal,

  /// Drives the on-axis bar-close countdown. Omitted (null) means no
  /// countdown — the page hides the label rather than guessing an interval.
  String? timeframe,
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

  // Always present (possibly empty) so chart.html can clear stale lines when
  // a trade closes rather than leaving them painted on.
  payload['priceLines'] = signalPriceLines(signal);

  // When the forming bar closes, as epoch seconds. The page counts down from
  // this on its own clock, so the label ticks without a repush every second.
  if (timeframe != null && candles.isNotEmpty) {
    final bar = timeframeDuration(timeframe);
    final opened = floorToTimeframe(candles.last.time, timeframe);
    payload['barCloseAt'] =
        opened.add(bar).millisecondsSinceEpoch ~/ 1000;
  }

  return payload;
}
