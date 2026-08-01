import '../ai/gold_master_engine.dart';
import '../ai/trade_plan_engine.dart';
import '../indicators/key_levels.dart';
import '../models/candle.dart';
import '../models/trade_signal.dart';
import '../services/market_data.dart';
import 'signal_controller.dart';

/// Hunts for a high-conviction setup in the background.
///
/// Before this existed, a plan was only ever generated inside the Trade Plan
/// screen's refresh — so a score reaching 80 while you were on Home, or with
/// the app merely backgrounded, was silently missed. The scout runs the same
/// analysis off the live quote stream, which is what makes a signal
/// notification possible at all.
///
/// Deliberately network-tolerant: a failed fetch returns null rather than
/// throwing, because this runs inside a stream listener that must not die.
class PlanScout {
  PlanScout({
    this.data,
    this.signals,
    this.minInterval = const Duration(minutes: 1),
    this.dailyCacheTtl = const Duration(minutes: 15),
    this.bullishThreshold = 80,
    this.bearishThreshold = 20,
  });

  /// Injected seams. Null means "use the app-wide singleton", resolved lazily
  /// below rather than here so a later `MarketData.instance` swap still wins.
  final MarketData? data;
  final SignalController? signals;

  /// Shortest gap between two analyses. The score only moves meaningfully on
  /// new candles, so recomputing on every tick would burn battery for nothing.
  final Duration minInterval;

  /// How long a daily-candle fetch is reused. Daily bars barely move
  /// intraday, so refetching them each scan is wasted bandwidth.
  final Duration dailyCacheTtl;

  final int bullishThreshold;
  final int bearishThreshold;

  MarketData get _market => data ?? MarketData.instance;
  SignalController get _controller => signals ?? SignalController.instance;

  DateTime? _lastScan;
  List<Candle>? _cachedDaily;
  DateTime? _cachedDailyAt;
  bool _busy = false;

  /// When the last completed scan ran; null before the first.
  DateTime? get lastScan => _lastScan;

  /// Whether a scan would run right now rather than being throttled away.
  bool due(DateTime now) =>
      _lastScan == null || now.difference(_lastScan!) >= minInterval;

  /// Runs an analysis if one is due and nothing is already running.
  ///
  /// Returns the signal that was just opened, or null when throttled, busy,
  /// a trade is already running, the score is undecided, or data is
  /// unavailable. Null is the overwhelmingly common answer.
  Future<TradeSignal?> scan({DateTime? now}) async {
    final at = (now ?? DateTime.now().toUtc()).toUtc();
    if (_busy || !due(at)) return null;

    // One at a time: the desk already has a position, so no plan can open.
    final controller = _controller;
    if (!controller.loaded) await controller.load();
    if (!controller.canIssue) {
      _lastScan = at; // still counts as a look, so we don't spin
      return null;
    }

    _busy = true;
    try {
      final h1 = await _market.fetchCandles('H1');
      if (h1.isEmpty) return null;
      final d1 = await _daily(at);
      if (d1.isEmpty) return null;

      final analysis = GoldMasterEngine.analyze(h1: h1, d1: d1);
      final plan = TradePlanEngine.generate(
        analysis: analysis,
        candles: h1,
        levels: KeyLevels.compute(d1),
        bullishThreshold: bullishThreshold,
        bearishThreshold: bearishThreshold,
        now: at,
      );
      if (plan == null) return null;
      // issue() re-checks the one-at-a-time gate and returns null if the
      // watcher opened something while we were awaiting the network.
      return await controller.issue(plan, now: at);
    } on Exception {
      return null;
    } finally {
      _lastScan = at;
      _busy = false;
    }
  }

  Future<List<Candle>> _daily(DateTime at) async {
    final cached = _cachedDaily;
    final cachedAt = _cachedDailyAt;
    if (cached != null &&
        cachedAt != null &&
        at.difference(cachedAt) < dailyCacheTtl) {
      return cached;
    }
    final fresh = await _market.fetchCandles('D1');
    if (fresh.isNotEmpty) {
      _cachedDaily = fresh;
      _cachedDailyAt = at;
    }
    return fresh;
  }
}
