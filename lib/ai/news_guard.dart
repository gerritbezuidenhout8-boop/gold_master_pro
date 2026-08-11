import '../services/economic_calendar.dart';

/// Keeps new signals away from high-impact news.
///
/// Gold's sharpest, least predictable moves come minutes either side of a
/// US macro release — NFP, CPI, FOMC. Technicals do not price those in: a
/// clean setup can be stopped out on the spike and still have been "right".
/// Since the goal is reaching the target rather than issuing signals, the
/// safest thing to do in that window is not open a trade at all.
///
/// Pure and deterministic like the rest of `ai/`: it is handed the events and
/// the clock, and never fetches anything itself.
class NewsGuard {
  NewsGuard._();

  /// Whose releases move gold. USD dominates; extend deliberately, because
  /// every added currency means more blocked windows and fewer signals.
  static const Set<String> relevantCountries = {'USD'};

  /// Impacts treated as dangerous.
  static const Set<EventImpact> blockingImpacts = {EventImpact.high};

  /// How long before a release the window opens — positioning and spreads
  /// start moving well ahead of the print.
  static const Duration quietBefore = Duration(minutes: 30);

  /// How long after it closes, once the initial whipsaw has passed.
  static const Duration quietAfter = Duration(minutes: 15);

  /// The event currently blocking new signals, or null when it is clear.
  ///
  /// Returns the *soonest* blocking event so callers can name it.
  static EconomicEvent? blocking(
    List<EconomicEvent> events,
    DateTime now, {
    Duration? before,
    Duration? after,
  }) {
    final lead = before ?? quietBefore;
    final lag = after ?? quietAfter;
    final nowUtc = now.toUtc();
    EconomicEvent? soonest;
    for (final e in events) {
      if (!blockingImpacts.contains(e.impact)) continue;
      if (!relevantCountries.contains(e.country.toUpperCase())) continue;
      final t = e.time.toUtc();
      final opens = t.subtract(lead);
      final closes = t.add(lag);
      // Inclusive at both edges: exactly on the boundary counts as blocked,
      // the conservative reading.
      if (nowUtc.isBefore(opens) || nowUtc.isAfter(closes)) continue;
      if (soonest == null || t.isBefore(soonest.time.toUtc())) soonest = e;
    }
    return soonest;
  }

  /// Whether a new signal may be opened at [now].
  static bool isClear(List<EconomicEvent> events, DateTime now) =>
      blocking(events, now) == null;
}
