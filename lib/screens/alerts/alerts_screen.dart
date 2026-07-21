import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../models/alert_rule.dart';
import '../../state/alerts_controller.dart';
import '../../widgets/section_card.dart';

const _armed = Color(0xFF14AD8F);
const _fired = Color(0xFFD4AF37);

/// Price alerts (spec: Alerts tab). In-app alerts are evaluated live
/// while the app is open (see AlertWatcher). Background delivery needs
/// the Cloudflare Worker + FCM path — docs/alerts_backend.md.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertsController get _c => AlertsController.instance;

  @override
  void initState() {
    super.initState();
    if (!_c.loaded) _c.load();
  }

  Future<void> _openSheet({AlertRule? existing}) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AlertSheet(existing: existing, seed: _c.lastPrice),
    );
    if (result is AlertRule) {
      await _c.upsert(result);
    } else if (result == 'delete' && existing != null) {
      await _c.remove(existing.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-alert'),
        onPressed: () => _openSheet(),
        icon: const Icon(Icons.add),
        label: const Text('New alert'),
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final rules = _c.rules;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              SectionCard(title: 'Live watch', children: [
                KvRow(
                  label: 'Last price',
                  value: _c.lastPrice == null
                      ? 'waiting for feed…'
                      : formatPrice(_c.lastPrice!),
                ),
                KvRow(
                  label: 'Armed alerts',
                  value: '${rules.where((r) => r.isArmed).length} '
                      'of ${rules.length}',
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Alerts fire while the app is open. Background push needs '
                    'the optional backend (docs/alerts_backend.md).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No alerts yet — tap “New alert” to watch a price level.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                for (final r in rules) _alertCard(r, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _alertCard(AlertRule r, ThemeData theme) {
    final triggered = r.triggeredAt != null;
    final color = !r.enabled
        ? theme.colorScheme.outline
        : triggered
            ? _fired
            : _armed;
    final status = !r.enabled
        ? 'DISABLED'
        : triggered
            ? 'FIRED ${formatUtcStamp(r.triggeredAt!)} UTC'
            : 'ARMED';
    return Card(
      child: ListTile(
        onTap: () => _openSheet(existing: r),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            r.kind.shortLabel,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
        title: Text('Gold ${r.kind.label} ${formatPrice(r.threshold)}'),
        subtitle: Text(
          '$status${r.note.isEmpty ? '' : ' · ${r.note}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: triggered
            ? TextButton(
                onPressed: () => _c.rearm(r.id),
                child: const Text('Re-arm'),
              )
            : Switch(
                value: r.enabled,
                onChanged: (v) => _c.setEnabled(r.id, v),
              ),
      ),
    );
  }
}

class _AlertSheet extends StatefulWidget {
  const _AlertSheet({this.existing, this.seed});

  final AlertRule? existing;
  final double? seed;

  @override
  State<_AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends State<_AlertSheet> {
  late AlertKind _kind = widget.existing?.kind ?? AlertKind.priceAbove;
  late final TextEditingController _threshold = TextEditingController(
      text: widget.existing?.threshold.toString() ??
          widget.seed?.toStringAsFixed(2) ??
          '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  String? _error;

  @override
  void dispose() {
    _threshold.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final threshold = double.tryParse(_threshold.text.trim());
    if (threshold == null || threshold <= 0) {
      setState(() => _error = 'Price must be a positive number');
      return;
    }
    final base = widget.existing;
    Navigator.of(context).pop(AlertRule(
      id: base?.id ?? AlertRule.newId(),
      kind: _kind,
      threshold: threshold,
      note: _note.text.trim(),
      enabled: base?.enabled ?? true,
      createdAt: base?.createdAt ?? DateTime.now().toUtc(),
      // Editing re-arms so the new level is watched afresh.
      triggeredAt: null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'New alert' : 'Edit alert',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(children: [
                ChoiceChip(
                  label: const Text('Crosses above'),
                  selected: _kind == AlertKind.priceAbove,
                  onSelected: (_) =>
                      setState(() => _kind = AlertKind.priceAbove),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Crosses below'),
                  selected: _kind == AlertKind.priceBelow,
                  onSelected: (_) =>
                      setState(() => _kind = AlertKind.priceBelow),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: const ValueKey('threshold-field'),
                  controller: _threshold,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Price level *'),
                ),
              ),
              TextField(
                key: const ValueKey('alert-note-field'),
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFFD5405D))),
                ),
              const SizedBox(height: 16),
              Row(children: [
                if (widget.existing != null)
                  TextButton(
                    key: const ValueKey('delete-alert-button'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Delete',
                        style: TextStyle(color: Color(0xFFD5405D))),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('save-alert-button'),
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
