import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/format.dart';
import '../models/alert_rule.dart';
import '../models/spot_quote.dart';
import '../models/trade_signal.dart';
import '../services/app_settings.dart';
import '../services/market_data.dart';
import '../services/notifications.dart';
import '../state/alerts_controller.dart';
import '../state/plan_scout.dart';
import '../state/signal_controller.dart';

/// Wraps the app shell and evaluates alerts against the live quote stream.
///
/// Two things happen per tick: price-crossing rules are tested, and — on a
/// throttle — the market is re-analysed for a high-conviction setup via
/// [PlanScout]. Anything that fires surfaces both an in-app SnackBar and an
/// OS notification, so a signal is not missed just because GMP wasn't the
/// screen you were looking at.
///
/// These are local notifications, delivered by the running app. Delivery
/// after the OS has killed the process needs the Cloudflare Worker + FCM
/// path — see docs/alerts_backend.md.
class AlertWatcher extends StatefulWidget {
  const AlertWatcher({
    super.key,
    required this.child,
    this.quotes,
    this.scout,
  });

  final Widget child;

  /// Injectable for tests; defaults to the live quote stream.
  final Stream<SpotQuote>? quotes;

  /// Injectable for tests; defaults to a scout on the live feed.
  final PlanScout? scout;

  @override
  State<AlertWatcher> createState() => _AlertWatcherState();
}

class _AlertWatcherState extends State<AlertWatcher> {
  StreamSubscription<SpotQuote>? _sub;
  late final PlanScout _scout = widget.scout ?? PlanScout();

  @override
  void initState() {
    super.initState();
    AlertsController.instance.load();
    SignalController.instance.load();
    _ensureNotificationPermission();
    final quotes = widget.quotes ?? MarketData.instance.quoteStream();
    _sub = quotes.listen((q) {
      // A running signal is tracked regardless of the alert toggle: closing
      // it at its take-profit or stop is state, not a notification.
      final closed = SignalController.instance.onPrice(q.price);
      if (closed != null) _announceClose(closed);

      // Look for the next setup. Throttled inside the scout, and skipped
      // entirely when the user has Signal Alerts off.
      if (AppSettings.instance.scoreAlerts.value) unawaited(_hunt());

      // Master switch: when price alerts are off, don't evaluate crossings
      // at all (the controller re-seeds cleanly when turned back on).
      if (!AppSettings.instance.priceAlerts.value) return;
      final fired = AlertsController.instance.onPrice(q.price);
      for (final rule in fired) {
        _announceAlert(rule, q.price);
      }
    });
  }

  /// Ask for notification permission on the way in.
  ///
  /// Android 13+ drops every notification until `POST_NOTIFICATIONS` is
  /// granted **at runtime** — the manifest entry alone does nothing. The
  /// Settings toggles only prompt on an off→on transition, and both alert
  /// switches default to *on*, so a fresh install never flipped one and
  /// therefore never asked: alerts silently went nowhere while the in-app
  /// SnackBar still appeared, which made it look like they worked.
  ///
  /// Fire-and-forget: a refusal is the user's call, and the app must keep
  /// working (SnackBars, signal tracking) without the OS channel.
  void _ensureNotificationPermission() {
    final settings = AppSettings.instance;
    if (settings.priceAlerts.value || settings.scoreAlerts.value) {
      unawaited(Notifications.instance.requestPermission());
    }
  }

  /// Runs one throttled analysis and announces a plan if one opened.
  Future<void> _hunt() async {
    final opened = await _scout.scan();
    if (opened == null) return;
    _announceSignal(opened);
  }

  void _announceSignal(TradeSignal signal) {
    final plan = signal.plan;
    final body = 'Score ${plan.score}/100 · '
        'entry ${formatPrice(plan.entry)} · '
        'stop ${formatPrice(plan.stop)} · '
        'target ${formatPrice(plan.tp1)}';
    unawaited(Notifications.instance.show(GmpNotification(
      id: GmpNotificationIds.signal,
      // Analysis, not an instruction — the positioning rule applies to
      // notifications as much as to the screens.
      title: 'Gold signal: ${plan.action} setup detected',
      body: '$body · analysis only',
    )));
    _snack(
      icon: Icons.auto_graph,
      color: const Color(0xFFD4AF37),
      text: 'New signal: ${plan.action} setup · $body',
    );
  }

  void _announceClose(TradeSignal signal) {
    final win = signal.outcome?.isWin ?? false;
    final r = signal.rMultiple;
    final text = 'Signal closed: ${signal.plan.action} '
        '${signal.outcome?.label.toLowerCase()} at '
        '${formatPrice(signal.exitPrice ?? 0)}'
        '${r == null ? '' : ' (${r >= 0 ? '+' : ''}'
            '${r.toStringAsFixed(1)}R)'}';
    unawaited(Notifications.instance.show(GmpNotification(
      id: GmpNotificationIds.signalClosed,
      title: 'Gold Master Pro — signal closed',
      body: text,
    )));
    _snack(
      icon: win ? Icons.check_circle : Icons.cancel,
      color: win ? const Color(0xFF25C685) : const Color(0xFFE5484D),
      text: text,
    );
  }

  void _announceAlert(AlertRule rule, double price) {
    final text = 'Alert: gold ${rule.kind.label} '
        '${formatPrice(rule.threshold)} (now ${formatPrice(price)})';
    unawaited(Notifications.instance.show(GmpNotification(
      id: GmpNotificationIds.priceAlert,
      title: 'Gold Master Pro — price alert',
      body: text,
    )));
    _snack(
      icon: Icons.notifications_active,
      color: const Color(0xFFD4AF37),
      text: text,
    );
  }

  /// In-app banner, shown alongside the OS notification for whoever is
  /// already looking at the app. Silently skipped when there is no
  /// messenger (e.g. the widget is off-screen).
  void _snack({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: const Color(0xFF1C1914),
      content: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
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
