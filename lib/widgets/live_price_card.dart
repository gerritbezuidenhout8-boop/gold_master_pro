import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/format.dart';
import '../models/spot_quote.dart';
import '../services/market_data.dart';

/// Home-screen price card fed by the live quote stream, with the true
/// XAU spot shown as a reference line when reachable.
class LivePriceCard extends StatefulWidget {
  const LivePriceCard({super.key, this.quotes, this.fetchSpot});

  /// Injection seams for tests; both default to [BinanceMarketData].
  final Stream<SpotQuote>? quotes;
  final Future<SpotQuote?> Function()? fetchSpot;

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
    final theme = Theme.of(context);
    final live = _live;
    final xau = _xau;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: live == null
                      ? theme.colorScheme.outline
                      : const Color(0xFF14AD8F),
                ),
                const SizedBox(width: 8),
                Text('XAUUSD', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              live == null ? '— · ——' : formatPrice(live.price),
              style: theme.textTheme.displaySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              live == null
                  ? 'Connecting to live feed…'
                  : '${live.source} · ${two(live.time.hour)}:${two(live.time.minute)}:${two(live.time.second)} UTC',
              style: theme.textTheme.bodySmall,
            ),
            if (xau != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${xau.source}: ${formatPrice(xau.price)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
