import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../services/app_settings.dart';
import '../../services/watchlist.dart';
import '../../widgets/gmp_card.dart';

/// Live markets watchlist (spec: Markets tab) — real spot prices for
/// metals and crypto from gold-api.com (keyless). Change is measured
/// across refreshes; pull down to update.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  List<InstrumentQuote>? _quotes;
  String? _error;
  bool _loading = false;
  Timer? _timer;

  ValueNotifier<int> get _interval => AppSettings.instance.autoRefreshSeconds;

  @override
  void initState() {
    super.initState();
    _load();
    _interval.addListener(_restartTimer);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _interval.removeListener(_restartTimer);
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(seconds: _interval.value), (_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return; // skip overlapping refreshes
    _loading = true;
    try {
      final quotes = await Watchlist.fetch();
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _error = quotes.isEmpty && _quotes == null
            ? 'No market data available'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load markets: $e');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Markets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.gold),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.gold,
        backgroundColor: AppTheme.surface,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final quotes = _quotes;
    if (_error != null && quotes == null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(
            child: Text(_error!,
                style: const TextStyle(color: AppTheme.textSecondary))),
      ]);
    }
    if (quotes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final cats = <String>[];
    for (final q in quotes) {
      if (!cats.contains(q.category)) cats.add(q.category);
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: SectionLabel(cat),
          ),
          for (final q in quotes.where((q) => q.category == cat))
            _row(q),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: ValueListenableBuilder<int>(
            valueListenable: _interval,
            builder: (context, seconds, _) => Text(
              'Live spot · gold-api.com · auto-refresh every ${seconds}s',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(InstrumentQuote q) {
    final isGold = q.symbol == 'XAU';
    final change = q.changePct;
    final changeColor = change == null
        ? AppTheme.textSecondary
        : change >= 0
            ? AppTheme.bull
            : AppTheme.bear;
    return GmpCard(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isGold ? AppTheme.goldGradient : null,
              color: isGold ? null : AppTheme.surfaceAlt,
              border: isGold ? null : Border.all(color: AppTheme.hairline),
            ),
            child: Text(
              q.symbol.substring(0, 1),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isGold ? const Color(0xFF1A1300) : AppTheme.gold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(q.pair,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                if (isGold) ...[
                  const SizedBox(width: 8),
                  const GmpPill(text: 'Focus', color: AppTheme.gold),
                ],
              ]),
              Text(q.name,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatPrice(q.price),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              Text(
                change == null ? '—' : signedPct(change),
                style: TextStyle(fontSize: 11, color: changeColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
