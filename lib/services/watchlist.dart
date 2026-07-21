import 'dart:convert';

import 'package:http/http.dart' as http;

/// A live spot quote for one watchlist instrument.
class InstrumentQuote {
  const InstrumentQuote({
    required this.symbol,
    required this.name,
    required this.category,
    required this.price,
    this.changePct,
  });

  final String symbol; // e.g. XAU
  final String name; // e.g. Gold
  final String category; // Metals / Crypto
  final double price;

  /// Percent move since the previous refresh (null on first load).
  final double? changePct;

  String get pair => '$symbol/USD';
}

typedef WatchlistFetcher = Future<List<InstrumentQuote>> Function();

/// Live watchlist from gold-api.com — keyless, free, real spot prices for
/// metals and crypto. Change is measured across refreshes (in-memory).
class Watchlist {
  Watchlist._();

  /// Swappable for tests.
  static WatchlistFetcher fetch = fetchFromGoldApi;

  static final Map<String, double> _last = {};

  static const List<(String, String, String)> instruments = [
    ('XAU', 'Gold', 'Metals'),
    ('XAG', 'Silver', 'Metals'),
    ('HG', 'Copper', 'Metals'),
    ('BTC', 'Bitcoin', 'Crypto'),
    ('ETH', 'Ethereum', 'Crypto'),
  ];

  static Future<List<InstrumentQuote>> fetchFromGoldApi() async {
    final results = await Future.wait(instruments.map((i) async {
      final (sym, name, cat) = i;
      try {
        final r = await http
            .get(Uri.parse('https://api.gold-api.com/price/$sym'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) return null;
        final body = jsonDecode(r.body);
        final price = (body is Map ? body['price'] as num? : null)?.toDouble();
        if (price == null) return null;
        final prev = _last[sym];
        _last[sym] = price;
        return InstrumentQuote(
          symbol: sym,
          name: name,
          category: cat,
          price: price,
          changePct:
              (prev == null || prev == 0) ? null : (price - prev) / prev * 100,
        );
      } on Exception {
        return null;
      }
    }));
    return results.whereType<InstrumentQuote>().toList();
  }
}
