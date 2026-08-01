import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_settings.dart';
import '../../services/notifications.dart';
import '../../widgets/gmp_card.dart';

/// App settings (spec: Settings). Auto Refresh, Price Alerts and Signal
/// Alerts all take real effect; News/Push persist the choice but await the
/// cloud backend.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get _s => AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _section('General', [
            _value('Appearance', 'Dark'),
            _value('Language', 'English'),
            _value('Default Instrument', 'XAUUSD'),
            _value('Market Session', 'Auto'),
          ]),
          _section('Notifications', [
            _toggle('Price Alerts', _s.priceAlerts, _grant(_s.setPriceAlerts)),
            _toggle('Signal Alerts', _s.scoreAlerts, _grant(_s.setScoreAlerts)),
            _toggle('News Alerts', _s.newsAlerts, _s.setNewsAlerts),
            _toggle('Push Notifications', _s.pushNotifications,
                _s.setPushNotifications),
          ]),
          _section('Data & Display', [
            _value('Data Source', 'Binance · gold-api'),
            _autoRefreshRow(),
            _value('Chart Default', 'Candlestick'),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Signal Alerts notify you when the Gold Master Score reaches '
              '80 or 20 and a trade plan opens; Price Alerts notify you when '
              'a level you set is crossed. Both are delivered by the running '
              'app, so they arrive while GMP is open or in the background, '
              'but not once the phone has closed it. News and Push persist '
              'your choice but need the cloud backend, which is not enabled '
              'in this build.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SectionLabel(title),
        ),
        GmpCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Material(
            color: Colors.transparent,
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }

  /// "1 second" / "5 seconds" — the picker offers 1, so don't say "1 seconds".
  static String _seconds(int s) => s == 1 ? '1 second' : '$s seconds';

  Widget _autoRefreshRow() {
    return ValueListenableBuilder<int>(
      valueListenable: AppSettings.instance.autoRefreshSeconds,
      builder: (context, seconds, _) => ListTile(
        dense: true,
        title: const Text('Auto Refresh',
            style: TextStyle(color: AppTheme.textPrimary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_seconds(seconds),
                style: const TextStyle(color: AppTheme.gold)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
        onTap: _pickAutoRefresh,
      ),
    );
  }

  Future<void> _pickAutoRefresh() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: SectionLabel('Auto Refresh Interval'),
            ),
            for (final s in AppSettings.autoRefreshOptions)
              ListTile(
                title: Text(_seconds(s),
                    style: const TextStyle(color: AppTheme.textPrimary)),
                trailing: s == AppSettings.instance.autoRefreshSeconds.value
                    ? const Icon(Icons.check, color: AppTheme.gold)
                    : null,
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await AppSettings.instance.setAutoRefresh(chosen);
  }

  Widget _value(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right,
              size: 18, color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  /// Wraps a setter so switching a notification on first asks the OS for
  /// permission. Turning it off never prompts.
  ValueChanged<bool> _grant(Future<void> Function(bool) set) => (bool on) async {
        if (on) await Notifications.instance.requestPermission();
        await set(on);
      };

  Widget _toggle(
      String label, ValueNotifier<bool> notifier, ValueChanged<bool> onChanged) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) => SwitchListTile(
        dense: true,
        title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
        value: value,
        activeThumbColor: AppTheme.gold,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        onChanged: onChanged,
      ),
    );
  }
}
