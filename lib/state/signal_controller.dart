import 'package:flutter/foundation.dart';

import '../ai/signal_engine.dart';
import '../ai/trade_plan_engine.dart';
import '../models/candle.dart';
import '../models/trade_signal.dart';
import '../services/signal_store.dart';

/// App-wide trade-signal state, deliberately a plain [ChangeNotifier]
/// singleton like [AlertsController].
///
/// The rule this type exists to enforce: **one signal at a time**. A new
/// plan can only be issued when nothing is running, and the running signal
/// closes only when price reaches its take-profit or its stop. The app-level
/// watcher feeds live prices in; the Trade Plan screen renders the result.
class SignalController extends ChangeNotifier {
  SignalController({SignalStore? store})
      : _store = store ?? SignalStore.instance;

  static SignalController instance = SignalController();

  /// How many closed signals are kept.
  static const int historyLimit = 25;

  final SignalStore _store;
  List<TradeSignal> _signals = []; // newest first
  bool _loaded = false;

  /// Newest first: the running signal (if any) followed by closed ones.
  List<TradeSignal> get signals => List.unmodifiable(_signals);

  /// The single running signal, or null when the desk is flat.
  TradeSignal? get active {
    for (final s in _signals) {
      if (s.isOpen) return s;
    }
    return null;
  }

  List<TradeSignal> get history =>
      List.unmodifiable(_signals.where((s) => !s.isOpen));

  bool get loaded => _loaded;

  /// True when a fresh plan may be issued — i.e. nothing is running.
  bool get canIssue => active == null;

  int get wins =>
      history.where((s) => s.outcome == SignalOutcome.takeProfit).length;
  int get losses =>
      history.where((s) => s.outcome == SignalOutcome.stopLoss).length;

  /// Sum of closed results in R.
  double get totalR =>
      history.fold(0.0, (sum, s) => sum + (s.rMultiple ?? 0));

  Future<void> load() async {
    _signals = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => _store.save(_signals);

  /// Opens [plan] as the running signal. Returns null (and changes nothing)
  /// when a signal is already running — this is the one-at-a-time gate.
  Future<TradeSignal?> issue(TradePlan plan, {DateTime? now}) async {
    if (!canIssue) return null;
    final signal = TradeSignal(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      plan: plan,
      openedAt: (now ?? DateTime.now().toUtc()).toUtc(),
    );
    _signals.insert(0, signal);
    _trim();
    notifyListeners();
    await _persist();
    return signal;
  }

  /// Feeds the latest price in. Returns the signal that just closed so the
  /// caller can surface a notification, or null if nothing changed.
  TradeSignal? onPrice(double price, {DateTime? now}) {
    final open = active;
    if (open == null) return null;
    final res = SignalEngine.resolve(open, price, now: now);
    if (res == null) return null;
    return _apply(open, res);
  }

  /// Replays [candles] so a signal that completed while the app was closed
  /// is settled on launch. Returns the closed signal, or null.
  TradeSignal? reconcile(List<Candle> candles) {
    final open = active;
    if (open == null) return null;
    final res = SignalEngine.resolveFromCandles(open, candles);
    if (res == null) return null;
    return _apply(open, res);
  }

  TradeSignal _apply(TradeSignal open, SignalResolution res) {
    final closed = open.close(
      outcome: res.outcome,
      exitPrice: res.exitPrice,
      at: res.at,
    );
    final i = _signals.indexWhere((s) => s.id == open.id);
    if (i >= 0) _signals[i] = closed;
    notifyListeners();
    _persist();
    return closed;
  }

  void _trim() {
    if (_signals.length <= historyLimit + 1) return;
    _signals = _signals.sublist(0, historyLimit + 1);
  }

  /// Test/debug helper: drop all signals.
  Future<void> clear() async {
    _signals = [];
    notifyListeners();
    await _persist();
  }
}
