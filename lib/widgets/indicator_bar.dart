import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../indicators/rsi.dart';
import 'gmp_card.dart';

/// Indicator readout + toggles above the chart: latest StochRSI %K/%D, a
/// recent-divergence pill, and show/hide chips for the chart overlays.
class IndicatorBar extends StatelessWidget {
  const IndicatorBar({
    super.key,
    required this.stochK,
    required this.stochD,
    required this.recentDivergence,
    required this.showStochRsi,
    required this.showDivergence,
    required this.onStochRsiChanged,
    required this.onDivergenceChanged,
  });

  final double? stochK;
  final double? stochD;
  final DivergenceEvent? recentDivergence;
  final bool showStochRsi;
  final bool showDivergence;
  final ValueChanged<bool> onStochRsiChanged;
  final ValueChanged<bool> onDivergenceChanged;

  @override
  Widget build(BuildContext context) {
    final div = recentDivergence;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          if (stochK != null)
            Text(
              'StochRSI ${stochK!.toStringAsFixed(1)} / '
              '${stochD?.toStringAsFixed(1) ?? '—'}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            ),
          if (div != null) ...[
            const SizedBox(width: 8),
            GmpPill(
              text: div.type == DivergenceType.bullish ? 'Bull div' : 'Bear div',
              color: div.type == DivergenceType.bullish
                  ? AppTheme.bull
                  : AppTheme.bear,
            ),
          ],
          const Spacer(),
          _toggle('StochRSI', showStochRsi, onStochRsiChanged),
          const SizedBox(width: 6),
          _toggle('Divergence', showDivergence, onDivergenceChanged),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: value,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: onChanged,
    );
  }
}
