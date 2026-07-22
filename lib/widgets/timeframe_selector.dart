import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// Horizontal timeframe chip row (M5 … W1).
class TimeframeSelector extends StatelessWidget {
  const TimeframeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final tf in AppConstants.timeframes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tf),
                selected: selected == tf,
                onSelected: (_) => onSelected(tf),
              ),
            ),
        ],
      ),
    );
  }
}
