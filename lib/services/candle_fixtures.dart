import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/candle.dart';

/// Bundled PAXG/USD candle snapshots (Binance public data, no API key).
///
/// These fixtures make the chart work offline at zero cost. Build-order
/// step 2 replaces them with a live service behind the same interface.
class CandleFixtures {
  CandleFixtures._();

  static const Map<String, String> _files = {
    'M5': 'assets/candles/paxg_m5.json',
    'M15': 'assets/candles/paxg_m15.json',
    'M30': 'assets/candles/paxg_m30.json',
    'H1': 'assets/candles/paxg_h1.json',
    'H4': 'assets/candles/paxg_h4.json',
    'D1': 'assets/candles/paxg_d1.json',
    'W1': 'assets/candles/paxg_w1.json',
  };

  static Future<List<Candle>> load(String timeframe) async {
    final path = _files[timeframe];
    if (path == null) {
      throw ArgumentError.value(timeframe, 'timeframe', 'unknown timeframe');
    }
    return candlesFromBinanceKlines(await rootBundle.loadString(path));
  }
}

/// Parses Binance's kline format: an array of
/// `[openTimeMs, "open", "high", "low", "close", "volume", ...]` rows.
List<Candle> candlesFromBinanceKlines(String jsonStr) {
  final raw = jsonDecode(jsonStr) as List<dynamic>;
  return [
    for (final row in raw.cast<List<dynamic>>())
      Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          (row[0] as num).toInt(),
          isUtc: true,
        ),
        open: double.parse(row[1] as String),
        high: double.parse(row[2] as String),
        low: double.parse(row[3] as String),
        close: double.parse(row[4] as String),
        volume: double.parse(row[5] as String),
      ),
  ];
}
