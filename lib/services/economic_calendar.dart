import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// Relative importance of a scheduled event.
enum EventImpact { high, medium, low, holiday, none }

extension EventImpactLabel on EventImpact {
  String get label => switch (this) {
        EventImpact.high => 'High',
        EventImpact.medium => 'Medium',
        EventImpact.low => 'Low',
        EventImpact.holiday => 'Holiday',
        EventImpact.none => '—',
      };
}

/// One scheduled economic release/event (times normalised to UTC).
class EconomicEvent {
  const EconomicEvent({
    required this.title,
    required this.country,
    required this.time,
    required this.impact,
    this.forecast,
    this.previous,
  });

  final String title;
  final String country; // e.g. USD, EUR
  final DateTime time; // UTC
  final EventImpact impact;
  final String? forecast;
  final String? previous;

  /// USD prints (CPI, NFP, FOMC…) are the dominant scheduled driver of gold.
  bool get movesGold => country == 'USD';
}

typedef CalendarFetcher = Future<List<EconomicEvent>> Function();

/// This-week economic calendar from ForexFactory's public weekly JSON
/// (via faireconomy — keyless). The host sends no CORS header, so — like
/// the candle feeds — web and offline fall back to a bundled snapshot.
class EconomicCalendar {
  EconomicCalendar._();

  /// Swappable for tests.
  static CalendarFetcher fetch = fetchThisWeek;

  static const String _url =
      'https://nfs.faireconomy.media/ff_calendar_thisweek.json';
  static const String _fixture = 'assets/calendar/ff_thisweek.json';

  static Future<List<EconomicEvent>> fetchThisWeek() async {
    if (!kIsWeb) {
      try {
        final r = await http
            .get(Uri.parse(_url))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final events = eventsFromForexFactory(r.body);
          if (events.isNotEmpty) return events;
        }
      } on Exception {
        // fall through to the bundled snapshot
      }
    }
    return _loadFixture();
  }

  static Future<List<EconomicEvent>> _loadFixture() async {
    try {
      return eventsFromForexFactory(await rootBundle.loadString(_fixture));
    } on Exception {
      return const [];
    }
  }
}

/// Parses ForexFactory's weekly JSON. Skips malformed entries; sorts by time.
List<EconomicEvent> eventsFromForexFactory(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final out = <EconomicEvent>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    final title = e['title'] as String?;
    final country = e['country'] as String?;
    final dateStr = e['date'] as String?;
    if (title == null || country == null || dateStr == null) continue;
    final dt = DateTime.tryParse(dateStr)?.toUtc();
    if (dt == null) continue;
    out.add(EconomicEvent(
      title: title,
      country: country,
      time: dt,
      impact: _impact(e['impact']),
      forecast: _clean(e['forecast']),
      previous: _clean(e['previous']),
    ));
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

EventImpact _impact(Object? raw) => switch (raw) {
      'High' => EventImpact.high,
      'Medium' => EventImpact.medium,
      'Low' => EventImpact.low,
      'Holiday' => EventImpact.holiday,
      _ => EventImpact.none,
    };

String? _clean(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}
