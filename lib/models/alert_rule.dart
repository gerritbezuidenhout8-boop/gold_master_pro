enum AlertKind { priceAbove, priceBelow }

extension AlertKindLabel on AlertKind {
  String get label =>
      this == AlertKind.priceAbove ? 'crosses above' : 'crosses below';
  String get shortLabel => this == AlertKind.priceAbove ? 'ABOVE' : 'BELOW';
}

/// A single price-crossing alert.
///
/// An alert is *armed* while [enabled] and not yet [triggeredAt]. It fires
/// once on a genuine crossing (see [AlertEngine]); re-arm to reuse it.
class AlertRule {
  const AlertRule({
    required this.id,
    required this.kind,
    required this.threshold,
    this.note = '',
    this.enabled = true,
    this.createdAt,
    this.triggeredAt,
  });

  final String id;
  final AlertKind kind;
  final double threshold;
  final String note;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? triggeredAt;

  bool get isArmed => enabled && triggeredAt == null;

  AlertRule copyWith({
    AlertKind? kind,
    double? threshold,
    String? note,
    bool? enabled,
    DateTime? triggeredAt,
    bool clearTriggered = false,
  }) =>
      AlertRule(
        id: id,
        kind: kind ?? this.kind,
        threshold: threshold ?? this.threshold,
        note: note ?? this.note,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        triggeredAt: clearTriggered ? null : (triggeredAt ?? this.triggeredAt),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'threshold': threshold,
        'note': note,
        'enabled': enabled,
        'createdAt': createdAt?.toIso8601String(),
        'triggeredAt': triggeredAt?.toIso8601String(),
      };

  factory AlertRule.fromMap(Map<String, dynamic> map) => AlertRule(
        id: map['id'] as String,
        kind: AlertKind.values.byName(map['kind'] as String),
        threshold: (map['threshold'] as num).toDouble(),
        note: map['note'] as String? ?? '',
        enabled: map['enabled'] as bool? ?? true,
        createdAt: _parse(map['createdAt']),
        triggeredAt: _parse(map['triggeredAt']),
      );

  static DateTime? _parse(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
