import 'package:flutter/material.dart';

/// App settings (notifications, appearance, data). Functional in Phase 5.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Notifications'),
            subtitle: Text('Available once alerts ship (Phase 5)'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Dark gold theme (fixed for now)'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('Data & cache'),
            subtitle: Text('Available once live data ships (Phase 3)'),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
