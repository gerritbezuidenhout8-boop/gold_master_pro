import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/format.dart';
import '../models/alert_rule.dart';
import '../models/spot_quote.dart';
import '../services/market_data.dart';
import '../state/alerts_controller.dart';

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
    final quotes = widget.quotes ?? MarketData.instance.quoteStream();
    _sub = quotes.listen((q) {
      final fired = AlertsController.instance.onPrice(q.price);
      if (fired.isEmpty || !mounted) return;
      for (final rule in fired) {
        _notify(rule, q.price);
      }
    });
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
