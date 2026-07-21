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
