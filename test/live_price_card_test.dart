import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/core/utils/format.dart';
import 'package:gold_master_pro/models/spot_quote.dart';
import 'package:gold_master_pro/widgets/live_price_card.dart';

void main() {
  test('formatPrice groups thousands', () {
    expect(formatPrice(4063.9), '4,063.90');
    expect(formatPrice(123.4), '123.40');
    expect(formatPrice(1234567.891), '1,234,567.89');
  });

  testWidgets('shows connecting state, then live quote and spot reference',
      (tester) async {
    final quotes = StreamController<SpotQuote>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: LivePriceCard(
          quotes: quotes.stream,
          fetchSpot: () async => SpotQuote(
            price: 4063.899902,
            time: DateTime.utc(2026, 7, 21, 10, 10, 3),
            source: 'XAU spot · gold-api.com',
          ),
        ),
      ),
    ));
    expect(find.text('— · ——'), findsOneWidget);
    expect(find.text('Connecting to live feed…'), findsOneWidget);

    await tester.pump();
    expect(find.textContaining('gold-api.com'), findsOneWidget);

    quotes.add(SpotQuote(
      price: 4057.86,
      time: DateTime.utc(2026, 7, 21, 10, 10, 3),
      source: 'PAXG/USD · Binance · live',
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('4,057.86'), findsOneWidget);
    expect(find.textContaining('10:10:03 UTC'), findsOneWidget);

    await quotes.close();
    await tester.pumpWidget(const SizedBox());
  });
}
