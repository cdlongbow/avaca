import 'dart:convert';

/// The versioned, portable data contract shared by the exporter and importer.
class DataTransferLimits {
  const DataTransferLimits._();

  static const format = 'avaca-data';
  static const version = 1;
  static const maxArchiveBytes = 1 << 30;
  static const maxEntries = 10000;
  static const maxSingleEntryBytes = 128 << 20;
  static const maxManifestBytes = 16 << 20;
  static const maxTotalUncompressedBytes = 4 << 30;
  static const maxCompressionRatio = 200;
  static const maxActresses = 100000;
  static const maxWorks = 250000;
  static const maxRelations = 1000000;
  static const maxAliasesPerActress = 1000;
  static const maxStringBytes = 1 << 20;
}

class DataTransferManifest {
  const DataTransferManifest({
    required this.exportedAt,
    required this.actresses,
    required this.works,
    required this.relations,
    required this.assets,
  });

  final String exportedAt;
  final List<DataTransferActress> actresses;
  final List<DataTransferWork> works;
  final List<DataTransferRelation> relations;
  final List<DataTransferAsset> assets;

  Map<String, Object?> toJson() => {
    'format': DataTransferLimits.format,
    'version': DataTransferLimits.version,
    'exportedAt': exportedAt,
    'actresses': actresses.map((item) => item.toJson()).toList(),
    'works': works.map((item) => item.toJson()).toList(),
    'relations': relations.map((item) => item.toJson()).toList(),
    'assets': assets.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory DataTransferManifest.fromJson(Object? source) {
    final map = _asMap(source, 'manifest');
    final format = _requiredString(map, 'format');
    final version = _requiredInt(map, 'version');
    if (format != DataTransferLimits.format) {
      throw const FormatException('Unsupported data transfer format.');
    }
    if (version != DataTransferLimits.version) {
      throw FormatException('Unsupported data transfer version: $version.');
    }

    final exportedAt = _requiredString(map, 'exportedAt');
    final actresses = _list(map, 'actresses', DataTransferActress.fromJson);
    final works = _list(map, 'works', DataTransferWork.fromJson);
    final relations = _list(map, 'relations', DataTransferRelation.fromJson);
    final assets = _list(map, 'assets', DataTransferAsset.fromJson);

    if (actresses.length > DataTransferLimits.maxActresses) {
      throw const FormatException('Too many actresses in archive.');
    }
    if (works.length > DataTransferLimits.maxWorks) {
      throw const FormatException('Too many works in archive.');
    }
    if (relations.length > DataTransferLimits.maxRelations) {
      throw const FormatException('Too many relations in archive.');
    }

    _ensureUnique(actresses.map((item) => item.id), 'actress id');
    _ensureUnique(works.map((item) => item.id), 'work id');
    _ensureUnique(assets.map((item) => item.id), 'asset id');
    _ensureUnique(works.map((item) => item.code.toLowerCase()), 'work code');
    _ensureUnique(
      relations.map((item) => '${item.actressId}\u0000${item.workId}'),
      'relation',
    );

    final actressIds = actresses.map((item) => item.id).toSet();
    final workIds = works.map((item) => item.id).toSet();
    final assetIds = assets.map((item) => item.id).toSet();
    for (final relation in relations) {
      if (!actressIds.contains(relation.actressId) ||
          !workIds.contains(relation.workId)) {
        throw const FormatException('Relation points to an unknown record.');
      }
    }
    for (final actress in actresses) {
      if (actress.aliases.length > DataTransferLimits.maxAliasesPerActress) {
        throw const FormatException('Too many aliases for an actress.');
      }
      _ensureUnique(
        actress.aliases.map((alias) => alias.toLowerCase()),
        'actress alias',
      );
      if (actress.avatarAssetId != null &&
          !assetIds.contains(actress.avatarAssetId)) {
        throw const FormatException('Actress references an unknown asset.');
      }
    }
    for (final work in works) {
      for (final assetId in [work.cardImageAssetId, work.detailImageAssetId]) {
        if (assetId != null && !assetIds.contains(assetId)) {
          throw const FormatException('Work references an unknown asset.');
        }
      }
    }

    return DataTransferManifest(
      exportedAt: exportedAt,
      actresses: List.unmodifiable(actresses),
      works: List.unmodifiable(works),
      relations: List.unmodifiable(relations),
      assets: List.unmodifiable(assets),
    );
  }
}

class DataTransferActress {
  const DataTransferActress({
    required this.id,
    required this.name,
    required this.avatarAssetId,
    required this.birthDate,
    required this.mainType,
    required this.tags,
    required this.memo,
    required this.height,
    required this.weight,
    required this.bwh,
    required this.cup,
    required this.aliases,
  });

  final String id;
  final String name;
  final String? avatarAssetId;
  final String? birthDate;
  final String? mainType;
  final String? tags;
  final String? memo;
  final String? height;
  final String? weight;
  final String? bwh;
  final String? cup;
  final List<String> aliases;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatarAssetId': avatarAssetId,
    'birthDate': birthDate,
    'mainType': mainType,
    'tags': tags,
    'memo': memo,
    'height': height,
    'weight': weight,
    'bwh': bwh,
    'cup': cup,
    'aliases': aliases,
  };

  factory DataTransferActress.fromJson(Object? source) {
    final map = _asMap(source, 'actress');
    return DataTransferActress(
      id: _requiredString(map, 'id'),
      name: _requiredString(map, 'name'),
      avatarAssetId: _nullableString(map, 'avatarAssetId'),
      birthDate: _nullableString(map, 'birthDate'),
      mainType: _nullableString(map, 'mainType'),
      tags: _nullableString(map, 'tags'),
      memo: _nullableString(map, 'memo'),
      height: _nullableString(map, 'height'),
      weight: _nullableString(map, 'weight'),
      bwh: _nullableString(map, 'bwh'),
      cup: _nullableString(map, 'cup'),
      aliases: _stringList(map, 'aliases'),
    );
  }
}

class DataTransferWork {
  const DataTransferWork({
    required this.id,
    required this.code,
    required this.title,
    required this.releaseDate,
    required this.durationMinutes,
    required this.studio,
    required this.publisher,
    required this.series,
    required this.cardImageAssetId,
    required this.detailImageAssetId,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final String? cardImageAssetId;
  final String? detailImageAssetId;
  final String? createdAt;
  final String? modifiedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'title': title,
    'releaseDate': releaseDate,
    'durationMinutes': durationMinutes,
    'studio': studio,
    'publisher': publisher,
    'series': series,
    'cardImageAssetId': cardImageAssetId,
    'detailImageAssetId': detailImageAssetId,
    'createdAt': createdAt,
    'modifiedAt': modifiedAt,
  };

  factory DataTransferWork.fromJson(Object? source) {
    final map = _asMap(source, 'work');
    return DataTransferWork(
      id: _requiredString(map, 'id'),
      code: _requiredString(map, 'code'),
      title: _requiredString(map, 'title'),
      releaseDate: _nullableString(map, 'releaseDate'),
      durationMinutes: _nullableInt(map, 'durationMinutes'),
      studio: _nullableString(map, 'studio'),
      publisher: _nullableString(map, 'publisher'),
      series: _nullableString(map, 'series'),
      cardImageAssetId: _nullableString(map, 'cardImageAssetId'),
      detailImageAssetId: _nullableString(map, 'detailImageAssetId'),
      createdAt: _nullableString(map, 'createdAt'),
      modifiedAt: _nullableString(map, 'modifiedAt'),
    );
  }
}

class DataTransferRelation {
  const DataTransferRelation({required this.actressId, required this.workId});

  final String actressId;
  final String workId;

  Map<String, Object?> toJson() => {'actressId': actressId, 'workId': workId};

  factory DataTransferRelation.fromJson(Object? source) {
    final map = _asMap(source, 'relation');
    return DataTransferRelation(
      actressId: _requiredString(map, 'actressId'),
      workId: _requiredString(map, 'workId'),
    );
  }
}

class DataTransferAsset {
  const DataTransferAsset({
    required this.id,
    required this.path,
    required this.size,
    required this.sha256,
  });

  final String id;
  final String path;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'size': size,
    'sha256': sha256,
  };

  factory DataTransferAsset.fromJson(Object? source) {
    final map = _asMap(source, 'asset');
    final size = _requiredInt(map, 'size');
    if (size < 0 || size > DataTransferLimits.maxSingleEntryBytes) {
      throw const FormatException('Asset size is outside supported limits.');
    }
    final sha256 = _requiredString(map, 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('Asset SHA-256 is invalid.');
    }
    return DataTransferAsset(
      id: _requiredString(map, 'id'),
      path: _requiredString(map, 'path'),
      size: size,
      sha256: sha256,
    );
  }
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  return Map<String, Object?>.from(value);
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  if (utf8.encode(value).length > DataTransferLimits.maxStringBytes) {
    throw FormatException('$key is too long.');
  }
  return value;
}

String? _nullableString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key must be a string or null.');
  }
  if (utf8.encode(value).length > DataTransferLimits.maxStringBytes) {
    throw FormatException('$key is too long.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

int? _nullableInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int) {
    throw FormatException('$key must be an integer or null.');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) {
    throw FormatException('$key must be an array.');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('$key must contain non-empty strings.');
        }
        if (utf8.encode(item).length > DataTransferLimits.maxStringBytes) {
          throw FormatException('$key contains an oversized string.');
        }
        return item;
      })
      .toList(growable: false);
}

List<T> _list<T>(
  Map<String, Object?> map,
  String key,
  T Function(Object?) parse,
) {
  final value = map[key];
  if (value is! List) {
    throw FormatException('$key must be an array.');
  }
  return value.map(parse).toList(growable: false);
}

void _ensureUnique(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw FormatException('Duplicate $label: $value.');
    }
  }
}
