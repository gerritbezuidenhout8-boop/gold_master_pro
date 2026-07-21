import 'package:flutter/material.dart';

/// Splash screen — wired into startup in Phase 3 once there is real
/// initialization (Firebase, cached data hydration) to wait for.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Gold Master Pro', style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
