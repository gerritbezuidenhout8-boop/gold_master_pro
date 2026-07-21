import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../models/journal_entry.dart';
import '../../services/journal_store.dart';
import '../../widgets/section_card.dart';

const _gain = Color(0xFF14AD8F);
const _loss = Color(0xFFD5405D);

String signedPrice(double v) =>
    v < 0 ? '-${formatPrice(-v)}' : '+${formatPrice(v)}';

/// Trading journal (spec: Journal) — local-first storage via
/// [JournalStore]; cloud sync arrives when Firebase is connected.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<JournalEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await JournalStore.instance.load();
    if (!mounted) return;
    entries.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _persist() => JournalStore.instance.save(_entries);

  Future<void> _openSheet({JournalEntry? existing}) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(existing: existing),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result == 'delete' && existing != null) {
        _entries.removeWhere((e) => e.id == existing.id);
      } else if (result is JournalEntry) {
        final i = _entries.indexWhere((e) => e.id == result.id);
        if (i >= 0) {
          _entries[i] = result;
        } else {
          _entries.insert(0, result);
        }
      }
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Trading Journal')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-trade'),
        onPressed: () => _openSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Log trade'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              children: [
                _statsCard(),
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No trades yet — log your first with the button below.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  for (final e in _entries) _entryCard(e, theme),
              ],
            ),
    );
  }

  Widget _statsCard() {
    final closed = [
      for (final e in _entries)
        if (e.isClosed) e,
    ];
    final open = _entries.length - closed.length;
    final wins = [
      for (final e in closed)
        if ((e.pnl ?? 0) > 0) e,
    ].length;
    final totalPnl = closed.fold(0.0, (s, e) => s + (e.pnl ?? 0));
    final rs = [
      for (final e in closed)
        if (e.rMultiple != null) e.rMultiple!,
    ];
    final avgR = rs.isEmpty ? null : rs.reduce((a, b) => a + b) / rs.length;
    return SectionCard(title: 'Performance', children: [
      KvRow(label: 'Trades', value: '${_entries.length} total · $open open'),
      KvRow(
        label: 'Win rate',
        value: closed.isEmpty
            ? '—'
            : '${(wins / closed.length * 100).round()}% of ${closed.length} closed',
      ),
      KvRow(
          label: 'Total P&L',
          value: closed.isEmpty ? '—' : signedPrice(totalPnl)),
      KvRow(label: 'Avg R', value: avgR == null ? '—' : avgR.toStringAsFixed(2)),
    ]);
  }

  Widget _entryCard(JournalEntry e, ThemeData theme) {
    final dirColor = e.direction == TradeDirection.long ? _gain : _loss;
    final pnl = e.pnl;
    final r = e.rMultiple;
    return Card(
      child: ListTile(
        onTap: () => _openSheet(existing: e),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: dirColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            e.direction.label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: dirColor, fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(
          '${formatPrice(e.entryPrice)} → '
          '${e.exitPrice == null ? 'open' : formatPrice(e.exitPrice!)}',
        ),
        subtitle: Text(
          '${formatUtcStamp(e.openedAt)} UTC'
          '${e.notes.isEmpty ? '' : ' · ${e.notes}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: pnl == null
            ? Text('OPEN',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    signedPrice(pnl),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: pnl >= 0 ? _gain : _loss),
                  ),
                  if (r != null)
                    Text('${r.toStringAsFixed(1)}R',
                        style: theme.textTheme.bodySmall),
                ],
              ),
      ),
    );
  }
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({this.existing});

  final JournalEntry? existing;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late TradeDirection _direction =
      widget.existing?.direction ?? TradeDirection.long;
  late final TextEditingController _entry =
      TextEditingController(text: widget.existing?.entryPrice.toString() ?? '');
  late final TextEditingController _size =
      TextEditingController(text: (widget.existing?.size ?? 1).toString());
  late final TextEditingController _stop = TextEditingController(
      text: widget.existing?.stopPrice?.toString() ?? '');
  late final TextEditingController _exit = TextEditingController(
      text: widget.existing?.exitPrice?.toString() ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  String? _error;

  @override
  void dispose() {
    _entry.dispose();
    _size.dispose();
    _stop.dispose();
    _exit.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final entry = double.tryParse(_entry.text.trim());
    final size = double.tryParse(_size.text.trim());
    final stopText = _stop.text.trim();
    final exitText = _exit.text.trim();
    final stop = stopText.isEmpty ? null : double.tryParse(stopText);
    final exit = exitText.isEmpty ? null : double.tryParse(exitText);
    String? error;
    if (entry == null || entry <= 0) {
      error = 'Entry price must be a positive number';
    } else if (size == null || size <= 0) {
      error = 'Size must be a positive number';
    } else if (stopText.isNotEmpty && stop == null) {
      error = 'Stop price must be a number';
    } else if (exitText.isNotEmpty && exit == null) {
      error = 'Exit price must be a number';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final base = widget.existing;
    Navigator.of(context).pop(JournalEntry(
      id: base?.id ?? JournalEntry.newId(),
      openedAt: base?.openedAt ?? DateTime.now().toUtc(),
      direction: _direction,
      entryPrice: entry!,
      exitPrice: exit,
      stopPrice: stop,
      size: size!,
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.existing == null ? 'Log trade' : 'Edit trade',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [
                  ChoiceChip(
                    label: const Text('LONG'),
                    selected: _direction == TradeDirection.long,
                    onSelected: (_) =>
                        setState(() => _direction = TradeDirection.long),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('SHORT'),
                    selected: _direction == TradeDirection.short,
                    onSelected: (_) =>
                        setState(() => _direction = TradeDirection.short),
                  ),
                ]),
                _numField('Entry price *', _entry, 'entry-field'),
                Row(children: [
                  Expanded(child: _numField('Size', _size, 'size-field')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _numField('Stop price', _stop, 'stop-field')),
                ]),
                _numField('Exit price (closes the trade)', _exit, 'exit-field'),
                TextField(
                  key: const ValueKey('notes-field'),
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: _loss)),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  if (widget.existing != null)
                    TextButton(
                      key: const ValueKey('delete-button'),
                      onPressed: () => Navigator.of(context).pop('delete'),
                      child:
                          const Text('Delete', style: TextStyle(color: _loss)),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('save-button'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl, String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: ValueKey(key),
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
