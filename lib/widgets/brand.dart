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

/// The crowned-bull emblem (rounded square) for drawer / avatars.
class GmpEmblem extends StatelessWidget {
  const GmpEmblem({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
