import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/format.dart';
import '../models/alert_rule.dart';
import '../models/spot_quote.dart';
import '../models/trade_signal.dart';
import '../services/app_settings.dart';
import '../services/market_data.dart';
import '../state/alerts_controller.dart';
import '../state/signal_controller.dart';

/// Wraps the app shell and evaluates alerts against the live quote stream
/// for as long as the app is open, surfacing an in-app SnackBar when a
/// rule fires. Background delivery (app closed) needs the Cloudflare
/// Worker + FCM path — see docs/alerts_backend.md.
class AlertWatcher extends StatefulWidget {
  const AlertWatcher({super.key, required this.child, this.quotes});

  final Widget child;

  /// Injectable for tests; defaults to the live quote stream.
  final Stream<SpotQuote>? quotes;

  @override
  State<AlertWatcher> createState() => _AlertWatcherState();
}

class _AlertWatcherState extends State<AlertWatcher> {
  StreamSubscription<SpotQuote>? _sub;

  @override
  void initState() {
    super.initState();
    AlertsController.instance.load();
    SignalController.instance.load();
    final quotes = widget.quotes ?? MarketData.instance.quoteStream();
    _sub = quotes.listen((q) {
      // A running signal is tracked regardless of the alert toggle: closing
      // it at its take-profit or stop is state, not a notification.
      final closed = SignalController.instance.onPrice(q.price);
      if (closed != null && mounted) _notifySignal(closed);

      // Master switch: when price alerts are off, don't evaluate crossings
      // at all (the controller re-seeds cleanly when turned back on).
      if (!AppSettings.instance.priceAlerts.value) return;
      final fired = AlertsController.instance.onPrice(q.price);
      if (fired.isEmpty || !mounted) return;
      for (final rule in fired) {
        _notify(rule, q.price);
      }
    });
  }

  void _notifySignal(TradeSignal signal) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final win = signal.outcome?.isWin ?? false;
    final r = signal.rMultiple;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: const Color(0xFF1C1914),
      content: Row(
        children: [
          Icon(win ? Icons.check_circle : Icons.cancel,
              color: win ? const Color(0xFF25C685) : const Color(0xFFE5484D)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Signal closed: ${signal.plan.action} '
              '${signal.outcome?.label.toLowerCase()} at '
              '${formatPrice(signal.exitPrice ?? 0)}'
              '${r == null ? '' : ' (${r >= 0 ? '+' : ''}'
                  '${r.toStringAsFixed(1)}R)'}',
            ),
          ),
        ],
      ),
    ));
  }

  void _notify(AlertRule rule, double price) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: const Color(0xFF1C1914),
      content: Row(
        children: [
          const Icon(Icons.notifications_active, color: Color(0xFFD4AF37)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Alert: gold ${rule.kind.label} ${formatPrice(rule.threshold)} '
              '(now ${formatPrice(price)})',
            ),
          ),
        ],
      ),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
