/// A single last-price quote with provenance.
class SpotQuote {
  const SpotQuote({
    required this.price,
    required this.time,
    required this.source,
  });

  final double price;
  final DateTime time;
  final String source;
}
