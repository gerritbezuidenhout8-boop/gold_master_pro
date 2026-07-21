import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Text wordmark stand-in for the GMP logo. Swap for the real bull/crown
/// emblem by dropping a PNG into assets/ and using it here.
class GmpWordmark extends StatelessWidget {
  const GmpWordmark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (r) => AppTheme.goldGradient.createShader(r),
          child: Text(
            'GMP',
            style: TextStyle(
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.white,
            ),
          ),
        ),
        if (!compact)
          const Text(
            'GOLD MASTER PRO',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// Circular emblem placeholder (bull silhouette) for splash / avatars.
class GmpEmblem extends StatelessWidget {
  const GmpEmblem({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2A2413), Color(0xFF0A0A0B)],
        ),
        border: Border.all(color: AppTheme.gold, width: 2),
      ),
      child: Icon(Icons.savings_outlined,
          color: AppTheme.gold, size: size * 0.5),
    );
  }
}
