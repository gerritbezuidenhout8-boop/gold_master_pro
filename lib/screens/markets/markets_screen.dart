import 'package:flutter/material.dart';

import '../../widgets/section_placeholder.dart';

/// Related markets, economic calendar and news (spec: Markets tab).
class MarketsScreen extends StatelessWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Markets')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          SectionPlaceholder(
            title: 'Watchlist',
            subtitle: 'DXY · US10Y · Silver — Phase 5',
            icon: Icons.stacked_line_chart,
          ),
          SectionPlaceholder(
            title: 'Economic calendar',
            subtitle: 'Provider undecided (no good free API) — Phase 5',
            icon: Icons.event,
          ),
          SectionPlaceholder(
            title: 'News analysis',
            subtitle: 'AI summaries via backend — Phase 5',
            icon: Icons.newspaper,
          ),
        ],
      ),
    );
  }
}
