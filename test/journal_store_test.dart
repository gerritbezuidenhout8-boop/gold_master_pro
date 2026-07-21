import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gold_master_pro/models/journal_entry.dart';
import 'package:gold_master_pro/services/journal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty store loads an empty list', () async {
    expect(await LocalJournalStore().load(), isEmpty);
  });

  test('save/load round trip', () async {
    final store = LocalJournalStore();
    final entries = [
      JournalEntry(
        id: 'a',
        openedAt: DateTime.utc(2026, 7, 21, 8),
        direction: TradeDirection.long,
        entryPrice: 4056.43,
        stopPrice: 4040,
        notes: 'breakout above PDH',
      ),
      JournalEntry(
        id: 'b',
        openedAt: DateTime.utc(2026, 7, 20, 14),
        direction: TradeDirection.short,
        entryPrice: 4100,
        exitPrice: 4080,
        size: 2,
      ),
    ];
    await store.save(entries);
    final back = await store.load();
    expect(back, hasLength(2));
    expect(back[0].id, 'a');
    expect(back[0].exitPrice, isNull);
    expect(back[1].pnl, 40);
  });
}
