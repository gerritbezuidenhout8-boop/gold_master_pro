import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/core/theme/app_theme.dart';
import 'package:gold_master_pro/screens/calendar/economic_calendar_screen.dart';
import 'package:gold_master_pro/services/economic_calendar.dart';

const _sample = '''
[
  {"title":"Bank Holiday","country":"JPY","date":"2026-07-20T00:00:00-04:00",
   "impact":"Holiday","forecast":"","previous":""},
  {"title":"Core CPI m/m","country":"USD","date":"2026-07-21T08:30:00-04:00",
   "impact":"High","forecast":"0.3%","previous":"0.2%"},
  {"title":"Retail Sales m/m","country":"GBP","date":"2026-07-21T02:00:00-04:00",
   "impact":"Medium","forecast":"","previous":"-0.6%"},
  {"title":"Broken","country":null,"date":"2026-07-21T02:00:00-04:00"}
]
''';

void main() {
  group('eventsFromForexFactory', () {
    test('parses valid rows, skips malformed, sorts by time', () {
      final events = eventsFromForexFactory(_sample);
      expect(events, hasLength(3)); // the null-country row is dropped
      // sorted ascending by UTC time: JPY 04:00Z, GBP 06:00Z, USD 12:30Z
      expect(events.first.country, 'JPY');
      expect(events.last.title, 'Core CPI m/m');
      expect(events.last.time.isUtc, isTrue);
      expect(events.last.time.hour, 12); // 08:30 -04:00 → 12:30 UTC
    });

    test('maps impact and blanks forecast/previous to null', () {
      final events = eventsFromForexFactory(_sample);
      final cpi = events.firstWhere((e) => e.country == 'USD');
      expect(cpi.impact, EventImpact.high);
      expect(cpi.movesGold, isTrue);
      expect(cpi.forecast, '0.3%');
      final holiday = events.firstWhere((e) => e.country == 'JPY');
      expect(holiday.impact, EventImpact.holiday);
      expect(holiday.forecast, isNull);
      expect(holiday.movesGold, isFalse);
    });

    test('bad JSON yields an empty list', () {
      expect(eventsFromForexFactory('not json'), isEmpty);
      expect(eventsFromForexFactory('{}'), isEmpty);
    });
  });

  group('bundled fixture', () {
    testWidgets('assets/calendar/ff_thisweek.json parses to events',
        (tester) async {
      final body =
          await rootBundle.loadString('assets/calendar/ff_thisweek.json');
      final events = eventsFromForexFactory(body);
      expect(events, isNotEmpty);
      expect(events.any((e) => e.movesGold), isTrue);
    });
  });

  group('EconomicCalendarScreen', () {
    final realFetch = EconomicCalendar.fetch;
    tearDown(() => EconomicCalendar.fetch = realFetch);

    testWidgets('renders events grouped, filters to gold-relevant',
        (tester) async {
      EconomicCalendar.fetch = () async => eventsFromForexFactory(_sample);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const EconomicCalendarScreen(),
      ));
      await tester.pumpAndSettle();

      // Default filter (High + Medium) shows CPI and Retail Sales.
      expect(find.text('Core CPI m/m'), findsOneWidget);
      expect(find.text('Retail Sales m/m'), findsOneWidget);

      // Turn on gold-relevant (USD only) → GBP row drops out.
      await tester.tap(find.text('Gold-relevant (USD)'));
      await tester.pumpAndSettle();
      expect(find.text('Core CPI m/m'), findsOneWidget);
      expect(find.text('Retail Sales m/m'), findsNothing);
    });
  });
}
