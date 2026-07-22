import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:http/http.dart' as http;

import '../models/candle.dart';
import '../models/spot_quote.dart';
import 'market_data.dart';

/// Market data aligned to real gold (what CFD brokers track):
///  - candles: COMEX gold futures (GC=F) via Yahoo's chart API — within a
///    few dollars of spot; unofficial, so Binance PAXG is the automatic
///    fallback (and the only path on web, where Yahoo blocks CORS)
///  - live quotes: XAU/USD bank spot polled from Swissquote, falling back
///    to gold-api.com, then to the PAXG stream
class SpotGoldMarketData implements MarketData {
  SpotGoldMarketData({BinanceMarketData? fallback})
      : _binance = fallback ?? BinanceMarketData();

  final BinanceMarketData _binance;

  /// UI-facing label of the source that actually supplied the candles.
  static final ValueNotifier<String> candleSource =
      ValueNotifier('XAU gold futures');

  static const Map<String, (String interval, String range)> _yahoo = {
    'M5': ('5m', '5d'),
    'M15': ('15m', '1mo'),
    'M30': ('30m', '1mo'),
    'H1': ('60m', '3mo'),
    'H4': ('60m', '6mo'), // aggregated 4x below
    'D1': ('1d', '2y'),
    'W1': ('1wk', '10y'),
  };

  static const Map<String, String> _ua = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
  };

  @override
  Future<List<Candle>> fetchCandles(String timeframe) async {
    final spec = _yahoo[timeframe];
    if (spec == null) {
      throw ArgumentError.value(timeframe, 'timeframe', 'unknown timeframe');
    }
    if (!kIsWeb) {
      try {
        final url = 'https://query1.finance.yahoo.com/v8/finance/chart/GC%3DF'
            '?interval=${spec.$1}&range=${spec.$2}';
        final res = await http
            .get(Uri.parse(url), headers: _ua)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          var candles = candlesFromYahooChart(res.body);
          if (timeframe == 'H4') {
            candles = aggregateCandles(candles, const Duration(hours: 4));
          }
          if (candles.length > 500) {
            candles = candles.sublist(candles.length - 500);
          }
          if (candles.isNotEmpty) {
            candleSource.value = 'XAU gold futures · Yahoo';
            return candles;
          }
        }
      } on Exception {
        // fall through to PAXG
      }
    }
    final fallback = await _binance.fetchCandles(timeframe);
    candleSource.value = 'PAXG/USD · Binance';
    return fallback;
  }

  @override
  Stream<Candle> candleStream(String timeframe) {
    if (kIsWeb) return _binance.candleStream(timeframe);
    final spec = _yahoo[timeframe];
    if (spec == null) {
      throw ArgumentError.value(timeframe, 'timeframe', 'unknown timeframe');
    }
    return _poll<Candle>(const Duration(seconds: 10), () async {
      final url = 'https://query1.finance.yahoo.com/v8/finance/chart/GC%3DF'
          '?interval=${spec.$1}&range=5d';
      final res = await http
          .get(Uri.parse(url), headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      var candles = candlesFromYahooChart(res.body);
      if (timeframe == 'H4') {
        candles = aggregateCandles(candles, const Duration(hours: 4));
      }
      return candles.isEmpty ? null : candles.last;
    });
  }

  @override
  Stream<SpotQuote> quoteStream() {
    if (kIsWeb) return _binance.quoteStream();
    return _poll<SpotQuote>(const Duration(seconds: 4), () async {
      try {
        final res = await http
            .get(
              Uri.parse('https://forex-data-feed.swissquote.com'
                  '/public-quotes/bboquotes/instrument/XAU/USD'),
            )
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final q = quoteFromSwissquote(res.body);
          if (q != null) return q;
        }
      } on Exception {
        // try gold-api below
      }
      return _binance.fetchXauSpot();
    });
  }

  @override
  Future<SpotQuote?> fetchXauSpot() => _binance.fetchXauSpot();

  /// Emits the result of [fetch] every [every] (skipping nulls/errors and
  /// duplicate timestamps), starting immediately.
  Stream<T> _poll<T>(Duration every, Future<T?> Function() fetch) {
    late final StreamController<T> controller;
    Timer? timer;
    var cancelled = false;

    Future<void> tick() async {
      try {
        final value = await fetch();
        if (!cancelled && value != null) controller.add(value);
      } on Exception {
        // transient failure — next tick retries
      }
    }

    controller = StreamController<T>(
      onListen: () {
        tick();
        timer = Timer.periodic(every, (_) => tick());
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Parses Yahoo's v8 chart payload into candles (null buckets skipped).
List<Candle> candlesFromYahooChart(String body) {
  final decoded = jsonDecode(body);
  final result = decoded?['chart']?['result'];
  if (result is! List || result.isEmpty) return const [];
  final r = result.first as Map<String, dynamic>;
  final times = (r['timestamp'] as List?)?.cast<num?>();
  final quote = (r['indicators']?['quote'] as List?)?.first;
  if (times == null || quote is! Map) return const [];
  final opens = (quote['open'] as List?)?.cast<num?>();
  final highs = (quote['high'] as List?)?.cast<num?>();
  final lows = (quote['low'] as List?)?.cast<num?>();
  final closes = (quote['close'] as List?)?.cast<num?>();
  final vols = (quote['volume'] as List?)?.cast<num?>();
  if (opens == null || highs == null || lows == null || closes == null) {
    return const [];
  }
  final out = <Candle>[];
  for (var i = 0; i < times.length; i++) {
    final t = times[i];
    final o = i < opens.length ? opens[i] : null;
    final h = i < highs.length ? highs[i] : null;
    final l = i < lows.length ? lows[i] : null;
    final c = i < closes.length ? closes[i] : null;
    if (t == null || o == null || h == null || l == null || c == null) {
      continue;
    }
    out.add(Candle(
      time: DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000, isUtc: true),
      open: o.toDouble(),
      high: h.toDouble(),
      low: l.toDouble(),
      close: c.toDouble(),
      volume:
          (vols != null && i < vols.length ? vols[i] : null)?.toDouble() ?? 0,
    ));
  }
  return out;
}

/// Combines candles into fixed UTC buckets of [bucket] (e.g. H1 → H4).
List<Candle> aggregateCandles(List<Candle> candles, Duration bucket) {
  if (candles.isEmpty) return candles;
  final ms = bucket.inMilliseconds;
  final out = <Candle>[];
  Candle? current;
  int? currentBucket;
  for (final c in candles) {
    final b = c.time.millisecondsSinceEpoch ~/ ms;
    if (currentBucket == b && current != null) {
      current = Candle(
        time: current.time,
        open: current.open,
        high: c.high > current.high ? c.high : current.high,
        low: c.low < current.low ? c.low : current.low,
        close: c.close,
        volume: current.volume + c.volume,
      );
    } else {
      if (current != null) out.add(current);
      currentBucket = b;
      current = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(b * ms, isUtc: true),
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
        volume: c.volume,
      );
    }
  }
  if (current != null) out.add(current);
  return out;
}

/// Parses Swissquote's public XAU/USD quote (mid of the best profile).
SpotQuote? quoteFromSwissquote(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List || decoded.isEmpty) return null;
  final first = decoded.first;
  final profiles = first?['spreadProfilePrices'];
  if (profiles is! List || profiles.isEmpty) return null;
  final p = profiles.first;
  final bid = (p?['bid'] as num?)?.toDouble();
  final ask = (p?['ask'] as num?)?.toDouble();
  if (bid == null || ask == null) return null;
  final ts = (first?['ts'] as num?)?.toInt();
  return SpotQuote(
    price: (bid + ask) / 2,
    bid: bid,
    ask: ask,
    time: ts == null
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
    source: 'XAU/USD spot · Swissquote',
  );
}
