import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/widgets/bottom_trade_panel.dart';

void main() {
  testWidgets('shows SELL/BUY boxes with the spread for two-sided quotes',
      (tester) async {
    final quotes = StreamController<SpotQuote>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: BottomTradePanel(quotes: quotes.stream)),
    ));
    expect(find.textContaining('connecting'), findsOneWidget);

    quotes.add(SpotQuote(
      price: 4115.5,
      bid: 4115.2,
      ask: 4115.8,
      time: DateTime.utc(2026, 7, 22, 8),
      source: 'XAU/USD spot · Swissquote',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('SELL'), findsOneWidget);
    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('4,115.20'), findsOneWidget);
    expect(find.text('4,115.80'), findsOneWidget);
    expect(find.text('0.60'), findsOneWidget); // spread

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falls back to a single price when no bid/ask', (tester) async {
    final quotes = StreamController<SpotQuote>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: BottomTradePanel(quotes: quotes.stream)),
    ));

    quotes.add(SpotQuote(
      price: 4104.91,
      time: DateTime.utc(2026, 7, 22, 8),
      source: 'PAXG/USD · Binance · live',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('4,104.91'), findsOneWidget);
    expect(find.text('SELL'), findsNothing);
    expect(find.text('BUY'), findsNothing);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });
}
