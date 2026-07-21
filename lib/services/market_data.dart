import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/candle.dart';
import '../models/spot_quote.dart';
import 'candle_fixtures.dart';

/// Swappable market-data facade. Widgets default to [MarketData.instance]
/// (the live Binance implementation); tests assign a fake so no real
/// network or WebSocket is ever touched under the test clock.
abstract class MarketData {
  static MarketData instance = BinanceMarketData();

  Future<List<Candle>> fetchCandles(String timeframe);
  Stream<Candle> candleStream(String timeframe);
  Stream<SpotQuote> quoteStream();
  Future<SpotQuote?> fetchXauSpot();
}

/// Live PAXG/USD market data from Binance's keyless public endpoints
/// (zero cost, no account), with the bundled snapshots as offline
/// fallback and gold-api.com as the true-spot XAU reference.
class BinanceMarketData implements MarketData {

  static const String symbol = 'PAXGUSDT';
  static const String _rest = 'https://data-api.binance.vision/api/v3';
  static const String _ws = 'wss://data-stream.binance.vision/ws';
  static const String _spotUrl = 'https://api.gold-api.com/price/XAU';

  /// App timeframe → Binance kline interval.
  static const Map<String, String> intervals = {
    'M5': '5m',
    'M15': '15m',
    'M30': '30m',
    'H1': '1h',
    'H4': '4h',
    'D1': '1d',
    'W1': '1w',
  };

  static String _interval(String timeframe) {
    final interval = intervals[timeframe];
    if (interval == null) {
      throw ArgumentError.value(timeframe, 'timeframe', 'unknown timeframe');
    }
    return interval;
  }

  /// REST backfill of the latest 500 candles; falls back to the bundled
  /// snapshot when the network is unavailable.
  @override
  Future<List<Candle>> fetchCandles(String timeframe) async {
    final interval = _interval(timeframe);
    try {
      final res = await http
          .get(Uri.parse(
              '$_rest/klines?symbol=$symbol&interval=$interval&limit=500'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}');
      }
      return candlesFromBinanceKlines(res.body);
    } on Exception {
      return CandleFixtures.load(timeframe);
    }
  }

  /// Live updates to the newest candle of [timeframe]. Reconnects every
  /// 5 seconds until the subscription is cancelled.
  @override
  Stream<Candle> candleStream(String timeframe) {
    final interval = _interval(timeframe);
    return _reconnecting(
        '$_ws/${symbol.toLowerCase()}@kline_$interval', candleFromKlineEvent);
  }

  /// Live last-trade quotes (~1/second) from the mini-ticker stream.
  @override
  Stream<SpotQuote> quoteStream() => _reconnecting(
      '$_ws/${symbol.toLowerCase()}@miniTicker', quoteFromMiniTicker);

  /// True spot XAU/USD from gold-api.com; null when unreachable.
  @override
  Future<SpotQuote?> fetchXauSpot() async {
    try {
      final res = await http
          .get(Uri.parse(_spotUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      return quoteFromGoldApi(body);
    } on Exception {
      return null;
    }
  }

  Stream<T> _reconnecting<T>(
      String url, T? Function(Map<String, dynamic>) parse) {
    late final StreamController<T> controller;
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    Timer? retry;
    var cancelled = false;

    void connect() {
      if (cancelled) return;
      void reconnectLater() {
        if (cancelled) return;
        retry?.cancel();
        retry = Timer(const Duration(seconds: 5), connect);
      }

      try {
        channel = WebSocketChannel.connect(Uri.parse(url));
        sub = channel!.stream.listen(
          (data) {
            if (data is! String || cancelled) return;
            final decoded = jsonDecode(data);
            if (decoded is! Map<String, dynamic>) return;
            final parsed = parse(decoded);
            if (parsed != null) controller.add(parsed);
          },
          onError: (Object _) => reconnectLater(),
          onDone: reconnectLater,
          cancelOnError: true,
        );
      } on Exception {
        reconnectLater();
      }
    }

    controller = StreamController<T>(
      onListen: connect,
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        await sub?.cancel();
        await channel?.sink.close();
      },
    );
    return controller.stream;
  }
}

/// Extracts the affected candle from a kline WebSocket event; null for
/// unrelated messages.
Candle? candleFromKlineEvent(Map<String, dynamic> msg) {
  final k = msg['k'];
  if (k is! Map<String, dynamic>) return null;
  return Candle(
    time: DateTime.fromMillisecondsSinceEpoch((k['t'] as num).toInt(),
        isUtc: true),
    open: double.parse(k['o'] as String),
    high: double.parse(k['h'] as String),
    low: double.parse(k['l'] as String),
    close: double.parse(k['c'] as String),
    volume: double.parse(k['v'] as String),
  );
}

/// Extracts a quote from a mini-ticker WebSocket event.
SpotQuote? quoteFromMiniTicker(Map<String, dynamic> msg) {
  final last = msg['c'];
  if (last is! String) return null;
  final eventTime = (msg['E'] as num?)?.toInt();
  return SpotQuote(
    price: double.parse(last),
    time: eventTime == null
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(eventTime, isUtc: true),
    source: 'PAXG/USD · Binance · live',
  );
}

/// Parses gold-api.com's `/price/XAU` response.
SpotQuote? quoteFromGoldApi(Map<String, dynamic> body) {
  final price = (body['price'] as num?)?.toDouble();
  if (price == null) return null;
  final updated = body['updatedAt'];
  return SpotQuote(
    price: price,
    time: updated is String
        ? (DateTime.tryParse(updated)?.toUtc() ?? DateTime.now().toUtc())
        : DateTime.now().toUtc(),
    source: 'XAU spot · gold-api.com',
  );
}

/// Replace-or-append [update] by candle open time; ignores stale updates
/// and caps the list at [maxLength].
List<Candle> mergeCandle(List<Candle> candles, Candle update,
    {int maxLength = 600}) {
  if (candles.isEmpty || update.time.isAfter(candles.last.time)) {
    final out = [...candles, update];
    return out.length > maxLength ? out.sublist(out.length - maxLength) : out;
  }
  if (candles.last.time.isAtSameMomentAs(update.time)) {
    return [...candles.sublist(0, candles.length - 1), update];
  }
  return candles;
}
