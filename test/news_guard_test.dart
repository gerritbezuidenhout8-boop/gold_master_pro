import 'package:flutter_test/flutter_test.dart';

import 'package:gold_master_pro/ai/news_guard.dart';
import 'package:gold_master_pro/services/economic_calendar.dart';

EconomicEvent _e(
  DateTime time, {
  EventImpact impact = EventImpact.high,
  String country = 'USD',
  String title = 'Non-Farm Employment Change',
}) =>
    EconomicEvent(
      title: title,
      country: country,
      time: time,
      impact: impact,
    );

void main() {
  final release = DateTime.utc(2026, 8, 7, 12, 30); // a typical NFP print

  test('blocks the half hour before a high-impact USD release', () {
    final events = [_e(release)];
    expect(NewsGuard.isClear(events, release.subtract(const Duration(hours: 1))),
        isTrue);
    expect(
        NewsGuard.isClear(events, release.subtract(const Duration(minutes: 31))),
        isTrue);
    expect(
        NewsGuard.isClear(events, release.subtract(const Duration(minutes: 29))),
        isFalse);
    expect(NewsGuard.isClear(events, release), isFalse);
  });

  test('stays blocked through the whipsaw, then clears', () {
    final events = [_e(release)];
    expect(
        NewsGuard.isClear(events, release.add(const Duration(minutes: 14))),
        isFalse);
    expect(
        NewsGuard.isClear(events, release.add(const Duration(minutes: 16))),
        isTrue);
  });

  test('the window edges count as blocked', () {
    final events = [_e(release)];
    expect(NewsGuard.isClear(events, release.subtract(NewsGuard.quietBefore)),
        isFalse);
    expect(NewsGuard.isClear(events, release.add(NewsGuard.quietAfter)), isFalse);
  });

  test('ignores medium/low impact and non-USD events', () {
    for (final e in [
      _e(release, impact: EventImpact.medium),
      _e(release, impact: EventImpact.low),
      _e(release, impact: EventImpact.holiday),
      _e(release, country: 'EUR'),
      _e(release, country: 'GBP'),
    ]) {
      expect(NewsGuard.isClear([e], release), isTrue,
          reason: '${e.country}/${e.impact} should not block');
    }
  });

  test('country match is case-insensitive', () {
    expect(NewsGuard.isClear([_e(release, country: 'usd')], release), isFalse);
  });

  test('names the soonest blocking event', () {
    final later = release.add(const Duration(minutes: 10));
    final blocking = NewsGuard.blocking(
      [_e(later, title: 'Later'), _e(release, title: 'Sooner')],
      release,
    );
    expect(blocking?.title, 'Sooner');
  });

  test('an empty calendar never blocks', () {
    // A failed fetch degrades to "no known event" — the technicals still gate.
    expect(NewsGuard.isClear(const [], release), isTrue);
  });
}
