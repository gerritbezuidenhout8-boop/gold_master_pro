enum TradeDirection { long, short }

extension TradeDirectionLabel on TradeDirection {
  String get label => this == TradeDirection.long ? 'LONG' : 'SHORT';
}

/// One trade in the journal. An entry with no [exitPrice] is an open
/// position.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.openedAt,
    required this.direction,
    required this.entryPrice,
    this.exitPrice,
    this.stopPrice,
    this.size = 1,
    this.notes = '',
  });

  final String id;
  final DateTime openedAt;
  final TradeDirection direction;
  final double entryPrice;
  final double? exitPrice;
  final double? stopPrice;

  /// Position size in ounces/lots — a multiplier for P&L.
  final double size;
  final String notes;

  bool get isClosed => exitPrice != null;

  /// Realized profit; null while the position is open.
  double? get pnl {
    final exit = exitPrice;
    if (exit == null) return null;
    final perUnit = direction == TradeDirection.long
        ? exit - entryPrice
        : entryPrice - exit;
    return perUnit * size;
  }

  /// P&L divided by the initial risk (entry→stop distance); null without
  /// a stop or while open.
  double? get rMultiple {
    final p = pnl;
    final stop = stopPrice;
    if (p == null || stop == null) return null;
    final risk = (entryPrice - stop).abs() * size;
    return risk <= 0 ? null : p / risk;
  }

  JournalEntry copyWith({
    TradeDirection? direction,
    double? entryPrice,
    double? exitPrice,
    double? stopPrice,
    double? size,
    String? notes,
  }) =>
      JournalEntry(
        id: id,
        openedAt: openedAt,
        direction: direction ?? this.direction,
        entryPrice: entryPrice ?? this.entryPrice,
        exitPrice: exitPrice ?? this.exitPrice,
        stopPrice: stopPrice ?? this.stopPrice,
        size: size ?? this.size,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'openedAt': openedAt.toIso8601String(),
        'direction': direction.name,
        'entryPrice': entryPrice,
        'exitPrice': exitPrice,
        'stopPrice': stopPrice,
        'size': size,
        'notes': notes,
      };

  factory JournalEntry.fromMap(Map<String, dynamic> map) => JournalEntry(
        id: map['id'] as String,
        openedAt: DateTime.parse(map['openedAt'] as String),
        direction: TradeDirection.values.byName(map['direction'] as String),
        entryPrice: (map['entryPrice'] as num).toDouble(),
        exitPrice: (map['exitPrice'] as num?)?.toDouble(),
        stopPrice: (map['stopPrice'] as num?)?.toDouble(),
        size: (map['size'] as num?)?.toDouble() ?? 1,
        notes: map['notes'] as String? ?? '',
      );

  /// Timestamp-based id — fine for manual, single-device entry.
  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
