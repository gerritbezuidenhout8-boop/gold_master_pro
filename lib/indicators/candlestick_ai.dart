import '../models/candle.dart';

/// Rule-based candlestick pattern recognition (spec: Candlestick AI).
///
/// Every pattern is deterministic OHLC math — no ML involved — which
/// keeps detection free, instant, offline-capable and unit-testable.
/// Patterns are purely geometric; trend context (e.g. a hammer only
/// matters after a decline) is applied by the scoring engine in Phase 4.
enum CandlePattern {
  bullishEngulfing,
  bearishEngulfing,
  hammer,
  shootingStar,
  morningStar,
  eveningStar,
  doji,
  marubozu,
  tweezerTop,
  tweezerBottom,
  threeWhiteSoldiers,
  threeBlackCrows,
  insideBar,
  outsideBar,
}

extension CandlePatternLabel on CandlePattern {
  String get label => switch (this) {
        CandlePattern.bullishEngulfing => 'Bullish Engulfing',
        CandlePattern.bearishEngulfing => 'Bearish Engulfing',
        CandlePattern.hammer => 'Hammer',
        CandlePattern.shootingStar => 'Shooting Star',
        CandlePattern.morningStar => 'Morning Star',
        CandlePattern.eveningStar => 'Evening Star',
        CandlePattern.doji => 'Doji',
        CandlePattern.marubozu => 'Marubozu',
        CandlePattern.tweezerTop => 'Tweezer Top',
        CandlePattern.tweezerBottom => 'Tweezer Bottom',
        CandlePattern.threeWhiteSoldiers => 'Three White Soldiers',
        CandlePattern.threeBlackCrows => 'Three Black Crows',
        CandlePattern.insideBar => 'Inside Bar',
        CandlePattern.outsideBar => 'Outside Bar',
      };

  bool get isBullishSignal => switch (this) {
        CandlePattern.bullishEngulfing ||
        CandlePattern.hammer ||
        CandlePattern.morningStar ||
        CandlePattern.tweezerBottom ||
        CandlePattern.threeWhiteSoldiers =>
          true,
        _ => false,
      };

  bool get isBearishSignal => switch (this) {
        CandlePattern.bearishEngulfing ||
        CandlePattern.shootingStar ||
        CandlePattern.eveningStar ||
        CandlePattern.tweezerTop ||
        CandlePattern.threeBlackCrows =>
          true,
        _ => false,
      };
}

class CandlestickDetector {
  CandlestickDetector._();

  // Rule thresholds, expressed as fractions. Tuned for readability over
  // textbook pedantry; adjust with real-data review in Phase 4.
  static const double _dojiBodyMax = 0.1; // body ≤ 10% of range
  static const double _marubozuBodyMin = 0.9; // body ≥ 90% of range
  static const double _wickDominance = 2.0; // wick ≥ 2× body
  static const double _smallWickMax = 0.15; // of range
  static const double _minBody = 0.05; // of range — a "real" body
  static const double _starBodyMax = 0.3; // star body vs first candle body
  static const double _strongBodyMin = 0.5; // of range — a "strong" candle
  static const double _tweezerTol = 0.1; // of average range

  /// Patterns completed by the FINAL candle of [candles].
  static List<CandlePattern> detect(List<Candle> candles) {
    if (candles.isEmpty) return const [];
    final out = <CandlePattern>[];
    final c0 = candles.last;
    final c1 = candles.length > 1 ? candles[candles.length - 2] : null;
    final c2 = candles.length > 2 ? candles[candles.length - 3] : null;

    final r0 = c0.range;
    final bull0 = c0.close > c0.open;
    final bear0 = c0.close < c0.open;

    if (r0 > 0) {
      if (c0.body <= _dojiBodyMax * r0) out.add(CandlePattern.doji);
      if (c0.body >= _marubozuBodyMin * r0) out.add(CandlePattern.marubozu);
      final realBody = c0.body >= _minBody * r0;
      if (realBody &&
          _lowerWick(c0) >= _wickDominance * c0.body &&
          _upperWick(c0) <= _smallWickMax * r0) {
        out.add(CandlePattern.hammer);
      }
      if (realBody &&
          _upperWick(c0) >= _wickDominance * c0.body &&
          _lowerWick(c0) <= _smallWickMax * r0) {
        out.add(CandlePattern.shootingStar);
      }
    }

    if (c1 != null) {
      final bull1 = c1.close > c1.open;
      final bear1 = c1.close < c1.open;

      if (bear1 &&
          bull0 &&
          c0.open <= c1.close &&
          c0.close >= c1.open &&
          c0.body > c1.body) {
        out.add(CandlePattern.bullishEngulfing);
      }
      if (bull1 &&
          bear0 &&
          c0.open >= c1.close &&
          c0.close <= c1.open &&
          c0.body > c1.body) {
        out.add(CandlePattern.bearishEngulfing);
      }

      final tol = _tweezerTol * ((c0.range + c1.range) / 2);
      if (bull1 && bear0 && (c0.high - c1.high).abs() <= tol) {
        out.add(CandlePattern.tweezerTop);
      }
      if (bear1 && bull0 && (c0.low - c1.low).abs() <= tol) {
        out.add(CandlePattern.tweezerBottom);
      }

      if (c0.high <= c1.high &&
          c0.low >= c1.low &&
          (c0.high < c1.high || c0.low > c1.low)) {
        out.add(CandlePattern.insideBar);
      }
      if (c0.high >= c1.high &&
          c0.low <= c1.low &&
          (c0.high > c1.high || c0.low < c1.low)) {
        out.add(CandlePattern.outsideBar);
      }
    }

    if (c1 != null && c2 != null) {
      final bull1 = c1.close > c1.open;
      final bear1 = c1.close < c1.open;
      final bull2 = c2.close > c2.open;
      final bear2 = c2.close < c2.open;
      final mid2 = (c2.open + c2.close) / 2;
      bool strong(Candle c) => c.range > 0 && c.body >= _strongBodyMin * c.range;

      if (bear2 &&
          strong(c2) &&
          c1.body <= _starBodyMax * c2.body &&
          bull0 &&
          c0.close >= mid2) {
        out.add(CandlePattern.morningStar);
      }
      if (bull2 &&
          strong(c2) &&
          c1.body <= _starBodyMax * c2.body &&
          bear0 &&
          c0.close <= mid2) {
        out.add(CandlePattern.eveningStar);
      }

      if (bull2 &&
          bull1 &&
          bull0 &&
          strong(c2) &&
          strong(c1) &&
          strong(c0) &&
          c1.close > c2.close &&
          c0.close > c1.close &&
          c1.open >= c2.open &&
          c1.open <= c2.close &&
          c0.open >= c1.open &&
          c0.open <= c1.close) {
        out.add(CandlePattern.threeWhiteSoldiers);
      }
      if (bear2 &&
          bear1 &&
          bear0 &&
          strong(c2) &&
          strong(c1) &&
          strong(c0) &&
          c1.close < c2.close &&
          c0.close < c1.close &&
          c1.open <= c2.open &&
          c1.open >= c2.close &&
          c0.open <= c1.open &&
          c0.open >= c1.close) {
        out.add(CandlePattern.threeBlackCrows);
      }
    }
    return out;
  }

  static double _upperWick(Candle c) =>
      c.high - (c.open > c.close ? c.open : c.close);
  static double _lowerWick(Candle c) =>
      (c.open < c.close ? c.open : c.close) - c.low;
}
