import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/journal_entry.dart';
import 'package:gold_master_pro/screens/journal/journal_screen.dart';
import 'package:gold_master_pro/services/journal_store.dart';

class _MemStore implements JournalStore {
  List<JournalEntry> data = [];

  @override
  Future<List<JournalEntry>> load() async => List.of(data);

  @override
  Future<void> save(List<JournalEntry> entries) async {
    data = List.of(entries);
  }
}

void main() {
  late JournalStore real;
  late _MemStore store;

  setUp(() {
    real = JournalStore.instance;
    store = _MemStore();
    JournalStore.instance = store;
  });

  tearDown(() => JournalStore.instance = real);

  Future<void> pumpJournal(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const JournalScreen()));
    await tester.pump();
  }

  testWidgets('shows the empty state', (tester) async {
    await pumpJournal(tester);
    expect(find.textContaining('No trades yet'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
  });

  testWidgets('logs a trade through the sheet and persists it',
      (tester) async {
    await pumpJournal(tester);

    await tester.tap(find.byKey(const ValueKey('add-trade')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('entry-field')), '4000');
    await tester.enterText(
        find.byKey(const ValueKey('notes-field')), 'test breakout');
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();

    expect(find.text('4,000.00 → open'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('1 total · 1 open'), findsOneWidget);
    expect(store.data, hasLength(1));
    expect(store.data.single.entryPrice, 4000);
  });

  testWidgets('closing a trade updates P&L and stats', (tester) async {
    store.data = [
      JournalEntry(
        id: 'x',
        openedAt: DateTime.utc(2026, 7, 21, 9),
        direction: TradeDirection.long,
        entryPrice: 4000,
        stopPrice: 3950,
      ),
    ];
    await pumpJournal(tester);

    await tester.tap(find.text('4,000.00 → open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('exit-field')), '4100');
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();

    expect(find.text('4,000.00 → 4,100.00'), findsOneWidget);
    expect(find.text('+100.00'), findsWidgets);
    expect(find.text('2.0R'), findsOneWidget);
    expect(find.text('100% of 1 closed'), findsOneWidget);
    expect(store.data.single.isClosed, isTrue);
  });

  testWidgets('deleting from the edit sheet removes the entry',
      (tester) async {
    store.data = [
      JournalEntry(
        id: 'x',
        openedAt: DateTime.utc(2026, 7, 21, 9),
        direction: TradeDirection.short,
        entryPrice: 4100,
      ),
    ];
    await pumpJournal(tester);

    await tester.tap(find.text('4,100.00 → open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No trades yet'), findsOneWidget);
    expect(store.data, isEmpty);
  });

  testWidgets('validation blocks a bad entry price', (tester) async {
    await pumpJournal(tester);
    await tester.tap(find.byKey(const ValueKey('add-trade')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pump();
    expect(find.text('Entry price must be a positive number'), findsOneWidget);
    expect(store.data, isEmpty);
  });
}
