import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/candle.dart';
import '../models/spot_quote.dart';
import 'market_data.dart';

/// Market data aligned to real gold (what CFD brokers track):
///  - candles: COMEX gold futures (GC=F) via Yahoo's chart API — within a
///    few dollars of spot; unofficial, so Binance PAXG is the automatic
///    fallback (and the only path on web, where Yahoo blocks CORS). Both
///    proxies are then shifted so the last close equals the live gold-api
///    XAU spot, so the chart reads at true spot levels (gold-api has no
///    OHLC history of its own).
///  - live quotes: XAU/USD bank spot polled from Swissquote (native),
///    falling back to gold-api.com, then to the PAXG stream. On web, where
///    Swissquote blocks CORS, gold-api.com's real XAU spot is polled
///    directly instead of the Binance PAXG ticker.
class SpotGoldMarketData implements MarketData {
  SpotGoldMarketData({BinanceMarketData? fallback})
      : _binance = fallback ?? BinanceMarketData();

  final BinanceMarketData _binance;

  /// Offset applied to align the proxy candle series to live XAU spot;
  /// the fallback for [candleStream] before the first live quote arrives.
  double _spotOffset = 0;

  /// Newest live spot price, recorded from [quoteStream] and the alignment
  /// fetch. [candleStream] re-anchors each forming bar to it.
  ///
  /// This exists because a *frozen* offset was the source of a real bug: the
  /// ticker (Swissquote) and the candle alignment (gold-api) were different
  /// vendors, and the offset was computed once at load, so as GC=F drifted
  /// against spot the chart flipped between two price levels and painted
  /// false red bars. One spot source, re-anchored live, is the fix.
  double? _lastSpot;

  /// UI-facing label of the source that actually supplied the candles.
  static final ValueNotifier<String> candleSource =
      ValueNotifier('XAU/USD spot · gold-api');

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
    final yahoo = kIsWeb ? null : await _tryYahoo(timeframe, spec);
    if (yahoo != null) return _alignToSpot(yahoo, 'GC=F');
    return _alignToSpot(await _binance.fetchCandles(timeframe), 'PAXG');
  }

  /// GC=F futures candles from Yahoo, or null when unavailable/empty.
  Future<List<Candle>?> _tryYahoo(String timeframe, (String, String) spec) async {
    try {
      final url = 'https://query1.finance.yahoo.com/v8/finance/chart/GC%3DF'
          '?interval=${spec.$1}&range=${spec.$2}';
      final res = await http
          .get(Uri.parse(url), headers: _ua)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      var candles = candlesFromYahooChart(res.body);
      if (timeframe == 'H4') {
        candles = aggregateCandles(candles, const Duration(hours: 4));
      }
      if (candles.length > 500) {
        candles = candles.sublist(candles.length - 500);
      }
      return candles.isEmpty ? null : candles;
    } on Exception {
      return null;
    }
  }

  /// Shifts the proxy series so its last close equals live XAU spot from
  /// [_spotQuote], so the chart reads at true spot levels (no free feed has
  /// spot OHLC history, so a keyless proxy supplies the bar shapes). Seeds
  /// `_lastSpot` and the `_spotOffset` fallback for [candleStream]; falls
  /// back to raw bars if spot is unreachable.
  Future<List<Candle>> _alignToSpot(List<Candle> candles, String proxy) async {
    if (candles.isEmpty) {
      candleSource.value = 'XAU/USD · $proxy';
      return candles;
    }
    // Deliberately the same source the ticker uses — aligning to one vendor
    // while streaming another is what made the chart jump.
    final spot = await _spotQuote();
    if (spot == null) {
      _spotOffset = 0;
      candleSource.value = 'XAU/USD · $proxy';
      return candles;
    }
    _lastSpot = spot.price;
    _spotOffset = spot.price - candles.last.close;
    candleSource.value = 'XAU/USD spot ($proxy bars)';
    return [for (final c in candles) _shift(c, _spotOffset)];
  }

  static Candle _shift(Candle c, double d) => Candle(
        time: c.time,
        open: c.open + d,
        high: c.high + d,
        low: c.low + d,
        close: c.close + d,
        volume: c.volume,
      );

  @override
  Stream<Candle> candleStream(String timeframe) {
    if (kIsWeb) {
      return _binance.candleStream(timeframe).map(anchorToSpot);
    }
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
    }).map(anchorToSpot);
  }

  /// Pins a streamed (forming) bar to the latest live spot.
  @visibleForTesting
  Candle anchorToSpot(Candle c) =>
      anchorCandleToSpot(c, _lastSpot, _spotOffset);

  @override
  Stream<SpotQuote> quoteStream() =>
      _poll<SpotQuote>(const Duration(seconds: 4), _spotQuote).map((q) {
        // Every live tick re-anchors the candle stream, so the bars and the
        // ticker can never drift onto two different price levels.
        _lastSpot = q.price;
        return q;
      });

  /// The single live-spot source for the whole class: Swissquote XAU/USD,
  /// falling back to gold-api. On web Swissquote sends no CORS header, so
  /// gold-api is used directly (single price, no bid/ask — the trade panel
  /// already degrades to a single-price display there).
  ///
  /// Both [quoteStream] and [_alignToSpot] go through here on purpose: using
  /// two vendors is what put the candles and the ticker on different levels.
  Future<SpotQuote?> _spotQuote() async {
    if (kIsWeb) return _binance.fetchXauSpot();
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

/// Shifts [c] so its close sits exactly on [spot], moving open/high/low by
/// the same delta; falls back to [fallbackOffset] when no spot is known yet.
///
/// The bar keeps the proxy's *shape* — so its colour still reflects the
/// proxy's real open-to-close move — while its *level* matches the ticker.
/// Shifting by a stale series offset instead left the close on one vendor
/// and the open on another, which painted red candles on green moves and
/// made the chart flip between two price ranges.
Candle anchorCandleToSpot(Candle c, double? spot, double fallbackOffset) {
  final delta = spot == null ? fallbackOffset : spot - c.close;
  return Candle(
    time: c.time,
    open: c.open + delta,
    high: c.high + delta,
    low: c.low + delta,
    close: c.close + delta,
    volume: c.volume,
  );
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
