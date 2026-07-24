import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../services/economic_calendar.dart';
import '../../widgets/gmp_card.dart';

/// Economic Calendar (spec: News & Calendar). This-week scheduled releases
/// that move gold, grouped by UTC day. Live on device; a bundled weekly
/// snapshot backs web and offline. Times are UTC to match the rest of GMP.
class EconomicCalendarScreen extends StatefulWidget {
  const EconomicCalendarScreen({super.key});

  @override
  State<EconomicCalendarScreen> createState() => _EconomicCalendarScreenState();
}

class _EconomicCalendarScreenState extends State<EconomicCalendarScreen> {
  List<EconomicEvent> _events = const [];
  bool _loading = true;
  String? _error;
  bool _majorOnly = true; // High + Medium
  bool _goldFocus = false; // USD only

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await EconomicCalendar.fetch();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the calendar: $e';
        _loading = false;
      });
    }
  }

  List<EconomicEvent> get _filtered => _events.where((e) {
        if (_goldFocus && !e.movesGold) return false;
        if (_majorOnly &&
            e.impact != EventImpact.high &&
            e.impact != EventImpact.medium) {
          return false;
        }
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Economic Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.gold),
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, style: const TextStyle(color: AppTheme.textSecondary)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    final events = _filtered;
    return Column(
      children: [
        _filters(),
        Expanded(
          child: events.isEmpty
              ? const Center(
                  child: Text('No events match the current filters',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: _buildGroups(events),
                ),
        ),
      ],
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('High + Medium'),
            selected: _majorOnly,
            onSelected: (v) => setState(() => _majorOnly = v),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Gold-relevant (USD)'),
            selected: _goldFocus,
            onSelected: (v) => setState(() => _goldFocus = v),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroups(List<EconomicEvent> events) {
    final widgets = <Widget>[];
    DateTime? currentDay;
    for (final e in events) {
      final day = DateTime.utc(e.time.year, e.time.month, e.time.day);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: SectionLabel(_dayLabel(day)),
        ));
      }
      widgets.add(_eventCard(e));
    }
    return widgets;
  }

  Widget _eventCard(EconomicEvent e) {
    final color = _impactColor(e.impact);
    return GmpCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('${two(e.time.hour)}:${two(e.time.minute)}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _countryBadge(e.country),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.title,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (e.forecast != null || e.previous != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        if (e.forecast != null) 'Forecast ${e.forecast}',
                        if (e.previous != null) 'Previous ${e.previous}',
                      ].join('  ·  '),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          GmpPill(text: e.impact.label, color: color),
        ],
      ),
    );
  }

  Widget _countryBadge(String country) {
    final gold = country == 'USD';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: gold ? AppTheme.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: gold ? AppTheme.gold : AppTheme.hairline),
      ),
      child: Text(country,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gold ? AppTheme.gold : AppTheme.textSecondary)),
    );
  }

  Color _impactColor(EventImpact impact) => switch (impact) {
        EventImpact.high => AppTheme.bear,
        EventImpact.medium => AppTheme.gold,
        EventImpact.low => AppTheme.textSecondary,
        EventImpact.holiday => AppTheme.textSecondary,
        EventImpact.none => AppTheme.textSecondary,
      };

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' //
  ];
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dayLabel(DateTime day) =>
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]} · UTC';
}
