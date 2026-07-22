import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/shell/root_shell.dart';
import 'services/app_settings.dart';
import 'services/market_data.dart';
import 'services/spot_gold_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  // Real-gold data source (futures candles + bank-spot ticker), with the
  // PAXG feed as automatic fallback (and the only path on web).
  MarketData.instance = SpotGoldMarketData();
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
