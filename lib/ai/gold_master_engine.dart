import '../core/utils/format.dart';
import '../indicators/candlestick_ai.dart';
import '../indicators/fibonacci.dart';
import '../indicators/key_levels.dart';
import '../indicators/smma.dart';
import '../models/candle.dart';

enum MarketBias { bullish, neutral, bearish }

extension MarketBiasLabel on MarketBias {
  String get label => switch (this) {
        MarketBias.bullish => 'Bullish',
        MarketBias.neutral => 'Neutral',
        MarketBias.bearish => 'Bearish',
      };
}

/// One weighted signal in the rubric.
class ScoreComponent {
  const ScoreComponent({
    required this.name,
    required this.signal,
    required this.weight,
    required this.reason,
  });

  final String name;

  /// -1 (bearish) .. +1 (bullish).
  final double signal;
  final double weight;
  final String reason;

  double get contribution => signal * weight;
}

class GoldMasterAnalysis {
  const GoldMasterAnalysis({
    required this.score,
    required this.bias,
    required this.confidence,
    required this.clarity,
    required this.strategyMatch,
    required this.components,
    required this.story,
    required this.topReasons,
    required this.lastPrice,
    required this.computedAt,
  });

  /// 0..100; 50 is neutral.
  final int score;
  final MarketBias bias;

  /// Weighted share of components agreeing with the overall direction.
  final int confidence;

  /// Strength of the aggregate signal (0 = pure chop, 100 = everything
  /// pulling one way).
  final int clarity;
  final String strategyMatch;
  final List<ScoreComponent> components;
  final String story;
  final List<String> topReasons;
  final double lastPrice;
  final DateTime computedAt;
}

/// The deterministic Gold Master Score (spec: Home Screen).
///
/// A weighted rubric over the step-3 indicator engines — fully
/// explainable, no ML, no network. The narrative is assembled from the
/// computed component reasons; an LLM layer may later rephrase it via
/// the backend but never invents the numbers.
class GoldMasterEngine {
  GoldMasterEngine._();

  /// [h1] drives short-term signals, [d1] the higher-timeframe trend and
  /// key levels; the last H1 close is "current price".
  static GoldMasterAnalysis analyze({
    required List<Candle> h1,
    required List<Candle> d1,
    DateTime? now,
  }) {
    if (h1.isEmpty || d1.isEmpty) {
      throw ArgumentError('h1 and d1 candles must not be empty');
    }
    final price = h1.last.close;
    final components = <ScoreComponent>[
      _smmaTrend('Hourly trend', 'hourly', h1, price, weight: 30),
      _smmaTrend('Daily trend', 'daily', d1, price, weight: 20),
      _keyLevelPosition(d1, price),
      _fibPosition(h1, price),
      _recentPatterns(h1),
    ];

    final totalWeight = components.fold(0.0, (s, c) => s + c.weight);
    final aggregate =
        components.fold(0.0, (s, c) => s + c.contribution) / totalWeight;
    final score = (50 + 50 * aggregate).round().clamp(0, 100).toInt();
    final bias = score >= 60
        ? MarketBias.bullish
        : score <= 40
            ? MarketBias.bearish
            : MarketBias.neutral;

    final aggSign = aggregate.sign;
    var agree = 0.0;
    var aligned = 0;
    for (final c in components) {
      if (c.signal == 0) {
        agree += 0.5 * c.weight;
      } else if (aggSign != 0 && c.signal.sign == aggSign) {
        agree += c.weight;
        aligned++;
      }
    }
    final confidence = (agree / totalWeight * 100).round();
    final clarity = (aggregate.abs() * 100).round().clamp(0, 100).toInt();
    final strategyMatch = '$aligned of ${components.length} signals aligned';

    final ranked = [...components]..sort(
        (a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
    final topReasons = [for (final c in ranked.take(3)) c.reason];
    final story = 'Gold trades at ${formatPrice(price)}. '
        '${ranked[0].reason}. ${ranked[1].reason}. '
        'Overall bias is ${bias.label.toLowerCase()} '
        'with a Gold Master Score of $score/100.';

    return GoldMasterAnalysis(
      score: score,
      bias: bias,
      confidence: confidence,
      clarity: clarity,
      strategyMatch: strategyMatch,
      components: components,
      story: story,
      topReasons: topReasons,
      lastPrice: price,
      computedAt: now ?? DateTime.now().toUtc(),
    );
  }

  static ScoreComponent _smmaTrend(
    String name,
    String word,
    List<Candle> candles,
    double price, {
    required double weight,
  }) {
    final closes = [for (final c in candles) c.close];
    final values = <double>[];
    for (final p in const [21, 50, 200]) {
      if (closes.length >= p) {
        final v = Smma.compute(closes, p).last;
        if (v != null) values.add(v);
      }
    }
    if (values.isEmpty) {
      return ScoreComponent(
        name: name,
        signal: 0,
        weight: weight,
        reason: 'Not enough $word history for an SMMA read',
      );
    }
    var s = 0.0;
    var above = 0;
    for (final v in values) {
      if (price > v) {
        s += 1;
        above++;
      } else if (price < v) {
        s -= 1;
      }
    }
    s /= values.length;
    final reason = above == values.length
        ? 'Price is above all ${values.length} $word SMMAs (21/50/200)'
        : above == 0
            ? 'Price is below all ${values.length} $word SMMAs (21/50/200)'
            : 'Price is above $above of ${values.length} $word SMMAs — '
                'mixed $word trend';
    return ScoreComponent(
        name: name, signal: s, weight: weight, reason: reason);
  }

  static ScoreComponent _keyLevelPosition(List<Candle> d1, double price) {
    final kl = KeyLevels.compute(d1);
    var s = 0.0;
    final notes = <String>[];
    if (price > kl.dailyOpen) {
      s += 0.4;
      notes.add('above the daily open');
    } else if (price < kl.dailyOpen) {
      s -= 0.4;
      notes.add('below the daily open');
    }
    final pdh = kl.prevDayHigh;
    final pdl = kl.prevDayLow;
    if (pdh != null && price > pdh) {
      s += 0.6;
      notes.add("broke above yesterday's high");
    } else if (pdl != null && price < pdl) {
      s -= 0.6;
      notes.add("trading below yesterday's low");
    } else if (pdh != null && pdl != null) {
      notes.add("inside yesterday's range");
    }
    final reason = notes.isEmpty
        ? 'Price is sitting on the daily open'
        : 'Price is ${notes.join(' and ')}';
    return ScoreComponent(
      name: 'Key levels',
      signal: s.clamp(-1.0, 1.0).toDouble(),
      weight: 20,
      reason: reason,
    );
  }

  static ScoreComponent _fibPosition(List<Candle> h1, double price) {
    final fib = Fibonacci.auto(h1);
    final range = fib.swingHigh - fib.swingLow;
    if (range <= 0) {
      return const ScoreComponent(
        name: 'Fibonacci',
        signal: 0,
        weight: 10,
        reason: 'No usable swing for a retracement read',
      );
    }
    final t = (price - fib.swingLow) / range;
    final pct = (t * 100).clamp(0, 199).round();
    return ScoreComponent(
      name: 'Fibonacci',
      signal: ((t - 0.5) * 2).clamp(-1.0, 1.0).toDouble(),
      weight: 10,
      reason: 'Price sits at $pct% of the ${fib.isUpLeg ? 'up' : 'down'}-swing '
          '${formatPrice(fib.swingLow)} → ${formatPrice(fib.swingHigh)}',
    );
  }

  static ScoreComponent _recentPatterns(List<Candle> h1) {
    var s = 0.0;
    String? note;
    final n = h1.length;
    for (var age = 0; age < 5 && n - age >= 2; age++) {
      for (final p in CandlestickDetector.detect(h1.sublist(0, n - age))) {
        final recency = 1.0 - 0.15 * age;
        final where = age == 0
            ? 'on the latest hourly candle'
            : '$age candle${age == 1 ? '' : 's'} back';
        if (p.isBullishSignal) {
          s += recency;
          note ??= '${p.label} $where';
        } else if (p.isBearishSignal) {
          s -= recency;
          note ??= '${p.label} $where';
        }
      }
    }
    return ScoreComponent(
      name: 'Candle patterns',
      signal: s.clamp(-1.0, 1.0).toDouble(),
      weight: 20,
      reason:
          note ?? 'No directional candle patterns in the last 5 hourly candles',
    );
  }
}
