/// 1234567.891 → '1,234,567.89'.
String formatPrice(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final digits = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '$grouped.${parts[1]}';
}

String two(int v) => v.toString().padLeft(2, '0');

/// 2026-07-21 09:00 UTC → '07-21 09:00'.
String formatUtcStamp(DateTime t) =>
    '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';

/// Signed price change, e.g. 12.5 → '+12.50', -3 → '-3.00'.
String signed(double v) => '${v >= 0 ? '+' : '-'}${formatPrice(v.abs())}';

/// Signed percent, e.g. 0.79 → '+0.79%'.
String signedPct(double v) =>
    '${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(2)}%';

/// Rough dominant forex trading session for a UTC time, plus whether the
/// gold market is open (closed over the weekend).
({String name, bool open}) marketSession(DateTime utc) {
  final t = utc.toUtc();
  final weekend = t.weekday == DateTime.saturday ||
      (t.weekday == DateTime.sunday && t.hour < 22) ||
      (t.weekday == DateTime.friday && t.hour >= 22);
  final h = t.hour;
  final name = h >= 7 && h < 13
      ? 'London'
      : h >= 13 && h < 17
          ? 'London / New York'
          : h >= 17 && h < 22
              ? 'New York'
              : h >= 0 && h < 7
                  ? 'Tokyo'
                  : 'Sydney';
  return (name: name, open: !weekend);
}
