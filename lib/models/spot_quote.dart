/// A single last-price quote with provenance. Sources that publish a
/// two-sided market (e.g. Swissquote) also carry bid/ask.
class SpotQuote {
  const SpotQuote({
    required this.price,
    required this.time,
    required this.source,
    this.bid,
    this.ask,
  });

  final double price;
  final DateTime time;
  final String source;
  final double? bid;
  final double? ask;

  double? get spread =>
      (bid != null && ask != null) ? ask! - bid! : null;
}
