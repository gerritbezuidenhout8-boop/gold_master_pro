import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Standard GMP surface: near-black fill, thin gold hairline border,
/// rounded corners. Used everywhere in place of Material [Card].
class GmpCard extends StatelessWidget {
  const GmpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 6),
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppTheme.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? decorated
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: decorated,
            ),
    );
  }
}

/// Uppercase gold section label with optional trailing widget.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: AppTheme.sectionLabel)),
        ?trailing,
      ],
    );
  }
}

/// Small rounded pill (e.g. bias / status chips).
class GmpPill extends StatelessWidget {
  const GmpPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}
