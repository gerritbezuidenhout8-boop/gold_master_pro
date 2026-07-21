import 'package:flutter/material.dart';

import '../journal/journal_screen.dart';
import '../settings/settings_screen.dart';

/// Account, journal and settings entry points (spec: Profile tab).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.2),
                child: Icon(Icons.person, color: scheme.primary),
              ),
              title: const Text('Local mode'),
              subtitle: const Text(
                  'Journal data stays on this device. Firebase sign-in is '
                  'ready to connect — see docs/firebase_setup.md.'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.book_outlined, color: scheme.primary),
              title: const Text('Trading journal'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JournalScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.settings_outlined, color: scheme.primary),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
