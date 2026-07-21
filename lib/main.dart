import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/shell/root_shell.dart';

void main() {
  runApp(const GmpApp());
}

class GmpApp extends StatelessWidget {
  const GmpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gold Master Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const RootShell(),
    );
  }
}
