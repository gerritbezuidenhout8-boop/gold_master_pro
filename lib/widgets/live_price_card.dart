import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/spot_quote.dart';
import '../services/market_data.dart';
import 'gmp_card.dart';
import 'sparkline.dart';

/// Dashboard price header: live XAUUSD price, session-open change, a
/// sparkline of recent closes and the current market session.
class LivePriceCard extends StatefulWidget {
  const LivePriceCard({
    super.key,
    this.quotes,
    this.fetchSpot,
    this.referenceOpen,
    this.spark = const [],
  });

  /// Injection seams for tests; both default to [MarketData.instance].
  final Stream<SpotQuote>? quotes;
  final Future<SpotQuote?> Function()? fetchSpot;

  /// Session/day open used to compute the change; recent closes for the
  /// sparkline. Supplied by the Home screen once candles load.
  final double? referenceOpen;
  final List<double> spark;

  @override
  State<LivePriceCard> createState() => _LivePriceCardState();
}

class _LivePriceCardState extends State<LivePriceCard> {
  StreamSubscription<SpotQuote>? _sub;
  Timer? _spotTimer;
  SpotQuote? _live;
  SpotQuote? _xau;

  @override
  void initState() {
    super.initState();
    final quotes = widget.quotes ?? MarketData.instance.quoteStream();
    _sub = quotes.listen((q) {
      if (mounted) setState(() => _live = q);
    });

    final fetchSpot = widget.fetchSpot ?? MarketData.instance.fetchXauSpot;
    Future<void> refreshSpot() async {
      final q = await fetchSpot();
      if (mounted && q != null) setState(() => _xau = q);
    }

    refreshSpot();
    _spotTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => refreshSpot());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final price = live?.price ?? _xau?.price;
    final open = widget.referenceOpen;
    final change = (price != null && open != null) ? price - open : null;
    final pct = (change != null && open != null && open != 0)
        ? change / open * 100
        : null;
    final up = (change ?? 0) >= 0;
    final changeColor = up ? AppTheme.bull : AppTheme.bear;
    final session = marketSession(DateTime.now());

    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.goldGradient,
                ),
                child: const Icon(Icons.paid,
                    color: Color(0xFF1A1300), size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('XAUUSD',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text('Gold / US Dollar',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
              const Spacer(),
              _sessionPill(session),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price == null ? '— · ——' : formatPrice(price),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      change == null
                          ? (live == null
                              ? 'Connecting to live feed…'
                              : 'Live')
                          : '${signed(change)}  (${signedPct(pct ?? 0)})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: change == null
                            ? AppTheme.textSecondary
                            : changeColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.spark.length >= 2)
                Sparkline(values: widget.spark),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            live == null && _xau != null
                ? 'XAU spot · gold-api.com'
                : live == null
                    ? 'PAXG/USD · Binance'
                    : 'PAXG/USD · Binance · live · '
                        '${two(live.time.hour)}:${two(live.time.minute)}:${two(live.time.second)} UTC',
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sessionPill(({String name, bool open}) session) {
    final color = session.open ? AppTheme.bull : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 6),
          Text(
            '${session.name} · ${session.open ? 'Open' : 'Closed'}',
            style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}
