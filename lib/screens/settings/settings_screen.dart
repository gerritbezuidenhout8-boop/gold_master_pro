import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_settings.dart';
import '../../widgets/gmp_card.dart';

/// App settings (spec: Settings). Layout matches the design; toggles are
/// display-only in this build and are wired to real behaviour as the
/// underlying features land.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _priceAlerts = true;
  bool _scoreAlerts = false;
  bool _newsAlerts = false;
  bool _push = false;

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
            _toggle('Price Alerts', _priceAlerts,
                (v) => setState(() => _priceAlerts = v)),
            _toggle('Score Alerts', _scoreAlerts,
                (v) => setState(() => _scoreAlerts = v)),
            _toggle('News Alerts', _newsAlerts,
                (v) => setState(() => _newsAlerts = v)),
            _toggle('Push Notifications', _push,
                (v) => setState(() => _push = v)),
          ]),
          _section('Data & Display', [
            _value('Data Source', 'Binance · gold-api'),
            _autoRefreshRow(),
            _value('Chart Default', 'Candlestick'),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Auto Refresh is live on the Markets watchlist. Notification '
              'toggles and other values are illustrative and take effect as '
              'each feature is connected.',
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
            Text('$seconds seconds',
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
                title: Text('$s seconds',
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

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
      value: value,
      activeThumbColor: AppTheme.gold,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onChanged: onChanged,
    );
  }
}
