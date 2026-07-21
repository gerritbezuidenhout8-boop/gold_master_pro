import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/models/journal_entry.dart';

JournalEntry _e({
  TradeDirection direction = TradeDirection.long,
  double entry = 100,
  double? exit,
  double? stop,
  double size = 1,
}) =>
    JournalEntry(
      id: '1',
      openedAt: DateTime.utc(2026, 7, 21, 9),
      direction: direction,
      entryPrice: entry,
      exitPrice: exit,
      stopPrice: stop,
      size: size,
      notes: 'test',
    );

void main() {
  test('long and short P&L, scaled by size', () {
    expect(_e(exit: 110, size: 2).pnl, 20);
    expect(_e(direction: TradeDirection.short, exit: 90, size: 2).pnl, 20);
    expect(_e(direction: TradeDirection.short, exit: 110).pnl, -10);
    expect(_e().pnl, isNull); // open position
  });

  test('R multiple against the initial stop', () {
    expect(_e(exit: 110, stop: 95, size: 2).rMultiple, closeTo(2.0, 1e-9));
    expect(_e(exit: 90, stop: 95).rMultiple, closeTo(-2.0, 1e-9));
    expect(_e(exit: 110).rMultiple, isNull); // no stop
    expect(_e(exit: 110, stop: 100).rMultiple, isNull); // zero risk
    expect(_e(stop: 95).rMultiple, isNull); // open
  });

  test('JSON round trip preserves everything, including nulls', () {
    final open = _e(stop: 95);
    final closed = _e(direction: TradeDirection.short, exit: 91.5, size: 0.5);
    for (final e in [open, closed]) {
      final back = JournalEntry.fromMap(e.toMap());
      expect(back.id, e.id);
      expect(back.openedAt, e.openedAt);
      expect(back.direction, e.direction);
      expect(back.entryPrice, e.entryPrice);
      expect(back.exitPrice, e.exitPrice);
      expect(back.stopPrice, e.stopPrice);
      expect(back.size, e.size);
      expect(back.notes, e.notes);
    }
  });
}
