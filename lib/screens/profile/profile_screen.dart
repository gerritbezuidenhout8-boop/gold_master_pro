import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/journal_entry.dart';
import '../../services/journal_store.dart';
import '../../widgets/brand.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/stat_tile.dart';
import '../journal/journal_screen.dart';
import '../settings/settings_screen.dart';

/// Account, performance and settings (spec: Profile tab). Performance is
/// computed live from the local trading journal.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<JournalEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await JournalStore.instance.load();
    if (mounted) setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _headerCard(),
          _performanceCard(),
          _links(),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return GmpCard(
      child: Row(
        children: [
          const GmpEmblem(size: 52),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Trader',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(width: 8),
                const GmpPill(text: 'Local', color: AppTheme.gold),
              ]),
              const SizedBox(height: 2),
              Text('Journal stays on this device',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _performanceCard() {
    final closed = [
      for (final e in _entries)
        if (e.isClosed) e,
    ];
    final wins = closed.where((e) => (e.pnl ?? 0) > 0).length;
    final grossWin = closed
        .where((e) => (e.pnl ?? 0) > 0)
        .fold(0.0, (s, e) => s + (e.pnl ?? 0));
    final grossLoss = closed
        .where((e) => (e.pnl ?? 0) < 0)
        .fold(0.0, (s, e) => s + (e.pnl ?? 0).abs());
    final totalPnl = closed.fold(0.0, (s, e) => s + (e.pnl ?? 0));
    final winRate =
        closed.isEmpty ? null : (wins / closed.length * 100).round();
    final profitFactor = grossLoss <= 0 ? null : grossWin / grossLoss;

    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Performance'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: StatTile(
                label: 'Total Trades',
                value: '${_entries.length}',
                note: '${closed.length} closed',
                noteColor: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Win Rate',
                value: winRate == null ? '—' : '$winRate%',
                note: winRate == null ? 'no closed trades' : 'of closed',
                noteColor:
                    (winRate ?? 0) >= 50 ? AppTheme.bull : AppTheme.gold,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: StatTile(
                label: 'Total P&L',
                value: closed.isEmpty ? '—' : signed(totalPnl),
                note: 'realized',
                noteColor: totalPnl >= 0 ? AppTheme.bull : AppTheme.bear,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Profit Factor',
                value:
                    profitFactor == null ? '—' : profitFactor.toStringAsFixed(2),
                note: 'win / loss',
                noteColor:
                    (profitFactor ?? 0) >= 1 ? AppTheme.bull : AppTheme.bear,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _links() {
    return GmpCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Column(
        children: [
          _tile(Icons.book_outlined, 'Trading journal', () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const JournalScreen()));
            _load();
          }),
          const Divider(height: 1, color: AppTheme.hairline),
          _tile(Icons.settings_outlined, 'Settings',
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen()))),
        ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.gold),
      title: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing:
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}
