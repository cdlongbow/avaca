class WorkFieldProvenance {
  const WorkFieldProvenance({
    required this.workId,
    required this.field,
    required this.source,
    this.sourceUri,
    this.observedAt,
    this.updatedAt,
  });

  final int workId;
  final String field;
  final String source;
  final Uri? sourceUri;
  final DateTime? observedAt;
  final DateTime? updatedAt;

  WorkFieldProvenance copyWith({int? workId}) => WorkFieldProvenance(
    workId: workId ?? this.workId,
    field: field,
    source: source,
    sourceUri: sourceUri,
    observedAt: observedAt,
    updatedAt: updatedAt,
  );

  Map<String, Object?> toRow() => {
    'work_id': workId,
    'field': field,
    'source': source,
    'source_uri': sourceUri?.toString(),
    'observed_at': observedAt?.toUtc().toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  factory WorkFieldProvenance.fromRow(Map<String, Object?> row) =>
      WorkFieldProvenance(
        workId: _int(row['work_id']),
        field: row['field']?.toString() ?? '',
        source: row['source']?.toString() ?? '',
        sourceUri: Uri.tryParse(row['source_uri']?.toString() ?? ''),
        observedAt: _date(row['observed_at']),
        updatedAt: _date(row['updated_at']),
      );

  Map<String, Object?> toTransferJson() => {
    'field': field,
    'source': source,
    if (sourceUri != null) 'sourceUri': sourceUri.toString(),
    if (observedAt != null) 'observedAt': observedAt!.toUtc().toIso8601String(),
  };
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
