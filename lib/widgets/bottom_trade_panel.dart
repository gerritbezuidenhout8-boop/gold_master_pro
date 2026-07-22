import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/spot_quote.dart';
import '../services/market_data.dart';

/// MT4-style quote panel under the chart: live SELL (bid) and BUY (ask)
/// prices with the spread between them. Display only — GMP analyses, it
/// does not place orders. Falls back to a single last-price readout when
/// the active feed has no two-sided quote.
class BottomTradePanel extends StatefulWidget {
  const BottomTradePanel({super.key, this.quotes});

  /// Injection seam for tests; defaults to the live quote stream.
  final Stream<SpotQuote>? quotes;

  @override
  State<BottomTradePanel> createState() => _BottomTradePanelState();
}

class _BottomTradePanelState extends State<BottomTradePanel> {
  StreamSubscription<SpotQuote>? _sub;
  SpotQuote? _quote;

  @override
  void initState() {
    super.initState();
    final quotes = widget.quotes ?? MarketData.instance.quoteStream();
    _sub = quotes.listen((q) {
      if (mounted) setState(() => _quote = q);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: q == null
          ? const SizedBox(
              height: 44,
              child: Center(
                child: Text('connecting to live feed…',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ),
            )
          : (q.bid != null && q.ask != null)
              ? _twoSided(q)
              : _singlePrice(q),
    );
  }

  Widget _twoSided(SpotQuote q) {
    return Row(
      children: [
        Expanded(
            child:
                _priceBox('SELL', q.bid!, AppTheme.bear, CrossAxisAlignment.start)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SPREAD',
                  style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary)),
              Text(
                q.spread!.toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gold),
              ),
            ],
          ),
        ),
        Expanded(
            child:
                _priceBox('BUY', q.ask!, AppTheme.bull, CrossAxisAlignment.end)),
      ],
    );
  }

  Widget _priceBox(
      String label, double price, Color color, CrossAxisAlignment align) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(
            formatPrice(price),
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _singlePrice(SpotQuote q) {
    return SizedBox(
      height: 44,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatPrice(q.price),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            Text(q.source,
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
