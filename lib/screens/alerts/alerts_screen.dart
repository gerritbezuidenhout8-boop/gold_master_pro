import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/alert_rule.dart';
import '../../state/alerts_controller.dart';
import '../../widgets/gmp_card.dart';
import '../../widgets/gold_button.dart';

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
      backgroundColor: AppTheme.surface,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) {
                final rules = _c.rules;
                return ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    _liveWatch(rules),
                    if (rules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No alerts yet — add one to watch a price level.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    else
                      for (final r in rules) _alertCard(r),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: GoldButton(
                key: const ValueKey('add-alert'),
                label: 'New Alert',
                icon: Icons.add,
                onPressed: () => _openSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveWatch(List<AlertRule> rules) {
    return GmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Live watch'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Last price',
                  style: TextStyle(color: AppTheme.textSecondary)),
              Text(
                _c.lastPrice == null
                    ? 'waiting for feed…'
                    : formatPrice(_c.lastPrice!),
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Armed alerts',
                  style: TextStyle(color: AppTheme.textSecondary)),
              Text('${rules.where((r) => r.isArmed).length} of ${rules.length}',
                  style: const TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Alerts fire while the app is open. Background push needs the '
            'optional backend (docs/alerts_backend.md).',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _alertCard(AlertRule r) {
    final triggered = r.triggeredAt != null;
    final (statusText, statusColor) = !r.enabled
        ? ('Off', AppTheme.textSecondary)
        : triggered
            ? ('Fired', AppTheme.gold)
            : ('Armed', AppTheme.bull);
    final dirColor =
        r.kind == AlertKind.priceAbove ? AppTheme.bull : AppTheme.bear;
    return GmpCard(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      onTap: () => _openSheet(existing: r),
      child: Row(
        children: [
          Icon(
            r.kind == AlertKind.priceAbove
                ? Icons.trending_up
                : Icons.trending_down,
            color: dirColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gold ${r.kind.label} ${formatPrice(r.threshold)}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  GmpPill(text: statusText, color: statusColor),
                  if (triggered)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('${formatUtcStamp(r.triggeredAt!)} UTC',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                    ),
                  if (r.note.isNotEmpty && !triggered)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(r.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                      ),
                    ),
                ]),
              ],
            ),
          ),
          triggered
              ? TextButton(
                  onPressed: () => _c.rearm(r.id),
                  child: const Text('Re-arm',
                      style: TextStyle(color: AppTheme.gold)),
                )
              : Switch(
                  value: r.enabled,
                  activeThumbColor: AppTheme.gold,
                  onChanged: (v) => _c.setEnabled(r.id, v),
                ),
        ],
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
                          ?.copyWith(color: AppTheme.bear)),
                ),
              const SizedBox(height: 16),
              Row(children: [
                if (widget.existing != null)
                  TextButton(
                    key: const ValueKey('delete-alert-button'),
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Delete',
                        style: TextStyle(color: AppTheme.bear)),
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
