// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _driveFolderIdMeta = const VerificationMeta(
    'driveFolderId',
  );
  @override
  late final GeneratedColumn<String> driveFolderId = GeneratedColumn<String>(
    'drive_folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeLutIdMeta = const VerificationMeta(
    'activeLutId',
  );
  @override
  late final GeneratedColumn<String> activeLutId = GeneratedColumn<String>(
    'active_lut_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    driveFolderId,
    activeLutId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('drive_folder_id')) {
      context.handle(
        _driveFolderIdMeta,
        driveFolderId.isAcceptableOrUnknown(
          data['drive_folder_id']!,
          _driveFolderIdMeta,
        ),
      );
    }
    if (data.containsKey('active_lut_id')) {
      context.handle(
        _activeLutIdMeta,
        activeLutId.isAcceptableOrUnknown(
          data['active_lut_id']!,
          _activeLutIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      driveFolderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}drive_folder_id'],
      ),
      activeLutId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_lut_id'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? driveFolderId;
  final String? activeLutId;
  const Session({
    required this.id,
    required this.name,
    required this.createdAt,
    this.driveFolderId,
    this.activeLutId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || driveFolderId != null) {
      map['drive_folder_id'] = Variable<String>(driveFolderId);
    }
    if (!nullToAbsent || activeLutId != null) {
      map['active_lut_id'] = Variable<String>(activeLutId);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      driveFolderId: driveFolderId == null && nullToAbsent
          ? const Value.absent()
          : Value(driveFolderId),
      activeLutId: activeLutId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeLutId),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      driveFolderId: serializer.fromJson<String?>(json['driveFolderId']),
      activeLutId: serializer.fromJson<String?>(json['activeLutId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'driveFolderId': serializer.toJson<String?>(driveFolderId),
      'activeLutId': serializer.toJson<String?>(activeLutId),
    };
  }

  Session copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Value<String?> driveFolderId = const Value.absent(),
    Value<String?> activeLutId = const Value.absent(),
  }) => Session(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    driveFolderId: driveFolderId.present
        ? driveFolderId.value
        : this.driveFolderId,
    activeLutId: activeLutId.present ? activeLutId.value : this.activeLutId,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      driveFolderId: data.driveFolderId.present
          ? data.driveFolderId.value
          : this.driveFolderId,
      activeLutId: data.activeLutId.present
          ? data.activeLutId.value
          : this.activeLutId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('driveFolderId: $driveFolderId, ')
          ..write('activeLutId: $activeLutId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, createdAt, driveFolderId, activeLutId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.driveFolderId == this.driveFolderId &&
          other.activeLutId == this.activeLutId);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<String?> driveFolderId;
  final Value<String?> activeLutId;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.driveFolderId = const Value.absent(),
    this.activeLutId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    this.driveFolderId = const Value.absent(),
    this.activeLutId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<String>? driveFolderId,
    Expression<String>? activeLutId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (driveFolderId != null) 'drive_folder_id': driveFolderId,
      if (activeLutId != null) 'active_lut_id': activeLutId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<String?>? driveFolderId,
    Value<String?>? activeLutId,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      activeLutId: activeLutId ?? this.activeLutId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (driveFolderId.present) {
      map['drive_folder_id'] = Variable<String>(driveFolderId.value);
    }
    if (activeLutId.present) {
      map['active_lut_id'] = Variable<String>(activeLutId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('driveFolderId: $driveFolderId, ')
          ..write('activeLutId: $activeLutId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotosTable extends Photos with TableInfo<$PhotosTable, Photo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewPathMeta = const VerificationMeta(
    'previewPath',
  );
  @override
  late final GeneratedColumn<String> previewPath = GeneratedColumn<String>(
    'preview_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fullResPathMeta = const VerificationMeta(
    'fullResPath',
  );
  @override
  late final GeneratedColumn<String> fullResPath = GeneratedColumn<String>(
    'full_res_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isRejectedMeta = const VerificationMeta(
    'isRejected',
  );
  @override
  late final GeneratedColumn<bool> isRejected = GeneratedColumn<bool>(
    'is_rejected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_rejected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _exifJsonMeta = const VerificationMeta(
    'exifJson',
  );
  @override
  late final GeneratedColumn<String> exifJson = GeneratedColumn<String>(
    'exif_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    fileName,
    previewPath,
    fullResPath,
    isFavorite,
    isRejected,
    exifJson,
    capturedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Photo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('preview_path')) {
      context.handle(
        _previewPathMeta,
        previewPath.isAcceptableOrUnknown(
          data['preview_path']!,
          _previewPathMeta,
        ),
      );
    }
    if (data.containsKey('full_res_path')) {
      context.handle(
        _fullResPathMeta,
        fullResPath.isAcceptableOrUnknown(
          data['full_res_path']!,
          _fullResPathMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('is_rejected')) {
      context.handle(
        _isRejectedMeta,
        isRejected.isAcceptableOrUnknown(data['is_rejected']!, _isRejectedMeta),
      );
    }
    if (data.containsKey('exif_json')) {
      context.handle(
        _exifJsonMeta,
        exifJson.isAcceptableOrUnknown(data['exif_json']!, _exifJsonMeta),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Photo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Photo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      previewPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview_path'],
      ),
      fullResPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_res_path'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      isRejected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_rejected'],
      )!,
      exifJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exif_json'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }
}

class Photo extends DataClass implements Insertable<Photo> {
  final String id;
  final String sessionId;
  final String fileName;
  final String? previewPath;
  final String? fullResPath;
  final bool isFavorite;
  final bool isRejected;
  final String exifJson;
  final DateTime capturedAt;
  const Photo({
    required this.id,
    required this.sessionId,
    required this.fileName,
    this.previewPath,
    this.fullResPath,
    required this.isFavorite,
    required this.isRejected,
    required this.exifJson,
    required this.capturedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || previewPath != null) {
      map['preview_path'] = Variable<String>(previewPath);
    }
    if (!nullToAbsent || fullResPath != null) {
      map['full_res_path'] = Variable<String>(fullResPath);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_rejected'] = Variable<bool>(isRejected);
    map['exif_json'] = Variable<String>(exifJson);
    map['captured_at'] = Variable<DateTime>(capturedAt);
    return map;
  }

  PhotosCompanion toCompanion(bool nullToAbsent) {
    return PhotosCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      fileName: Value(fileName),
      previewPath: previewPath == null && nullToAbsent
          ? const Value.absent()
          : Value(previewPath),
      fullResPath: fullResPath == null && nullToAbsent
          ? const Value.absent()
          : Value(fullResPath),
      isFavorite: Value(isFavorite),
      isRejected: Value(isRejected),
      exifJson: Value(exifJson),
      capturedAt: Value(capturedAt),
    );
  }

  factory Photo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Photo(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      previewPath: serializer.fromJson<String?>(json['previewPath']),
      fullResPath: serializer.fromJson<String?>(json['fullResPath']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isRejected: serializer.fromJson<bool>(json['isRejected']),
      exifJson: serializer.fromJson<String>(json['exifJson']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'fileName': serializer.toJson<String>(fileName),
      'previewPath': serializer.toJson<String?>(previewPath),
      'fullResPath': serializer.toJson<String?>(fullResPath),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isRejected': serializer.toJson<bool>(isRejected),
      'exifJson': serializer.toJson<String>(exifJson),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
    };
  }

  Photo copyWith({
    String? id,
    String? sessionId,
    String? fileName,
    Value<String?> previewPath = const Value.absent(),
    Value<String?> fullResPath = const Value.absent(),
    bool? isFavorite,
    bool? isRejected,
    String? exifJson,
    DateTime? capturedAt,
  }) => Photo(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    fileName: fileName ?? this.fileName,
    previewPath: previewPath.present ? previewPath.value : this.previewPath,
    fullResPath: fullResPath.present ? fullResPath.value : this.fullResPath,
    isFavorite: isFavorite ?? this.isFavorite,
    isRejected: isRejected ?? this.isRejected,
    exifJson: exifJson ?? this.exifJson,
    capturedAt: capturedAt ?? this.capturedAt,
  );
  Photo copyWithCompanion(PhotosCompanion data) {
    return Photo(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      previewPath: data.previewPath.present
          ? data.previewPath.value
          : this.previewPath,
      fullResPath: data.fullResPath.present
          ? data.fullResPath.value
          : this.fullResPath,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      isRejected: data.isRejected.present
          ? data.isRejected.value
          : this.isRejected,
      exifJson: data.exifJson.present ? data.exifJson.value : this.exifJson,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Photo(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('fileName: $fileName, ')
          ..write('previewPath: $previewPath, ')
          ..write('fullResPath: $fullResPath, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isRejected: $isRejected, ')
          ..write('exifJson: $exifJson, ')
          ..write('capturedAt: $capturedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    fileName,
    previewPath,
    fullResPath,
    isFavorite,
    isRejected,
    exifJson,
    capturedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Photo &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.fileName == this.fileName &&
          other.previewPath == this.previewPath &&
          other.fullResPath == this.fullResPath &&
          other.isFavorite == this.isFavorite &&
          other.isRejected == this.isRejected &&
          other.exifJson == this.exifJson &&
          other.capturedAt == this.capturedAt);
}

class PhotosCompanion extends UpdateCompanion<Photo> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> fileName;
  final Value<String?> previewPath;
  final Value<String?> fullResPath;
  final Value<bool> isFavorite;
  final Value<bool> isRejected;
  final Value<String> exifJson;
  final Value<DateTime> capturedAt;
  final Value<int> rowid;
  const PhotosCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.previewPath = const Value.absent(),
    this.fullResPath = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isRejected = const Value.absent(),
    this.exifJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotosCompanion.insert({
    required String id,
    required String sessionId,
    required String fileName,
    this.previewPath = const Value.absent(),
    this.fullResPath = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isRejected = const Value.absent(),
    this.exifJson = const Value.absent(),
    required DateTime capturedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       fileName = Value(fileName),
       capturedAt = Value(capturedAt);
  static Insertable<Photo> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? fileName,
    Expression<String>? previewPath,
    Expression<String>? fullResPath,
    Expression<bool>? isFavorite,
    Expression<bool>? isRejected,
    Expression<String>? exifJson,
    Expression<DateTime>? capturedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (fileName != null) 'file_name': fileName,
      if (previewPath != null) 'preview_path': previewPath,
      if (fullResPath != null) 'full_res_path': fullResPath,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isRejected != null) 'is_rejected': isRejected,
      if (exifJson != null) 'exif_json': exifJson,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? fileName,
    Value<String?>? previewPath,
    Value<String?>? fullResPath,
    Value<bool>? isFavorite,
    Value<bool>? isRejected,
    Value<String>? exifJson,
    Value<DateTime>? capturedAt,
    Value<int>? rowid,
  }) {
    return PhotosCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      fileName: fileName ?? this.fileName,
      previewPath: previewPath ?? this.previewPath,
      fullResPath: fullResPath ?? this.fullResPath,
      isFavorite: isFavorite ?? this.isFavorite,
      isRejected: isRejected ?? this.isRejected,
      exifJson: exifJson ?? this.exifJson,
      capturedAt: capturedAt ?? this.capturedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (previewPath.present) {
      map['preview_path'] = Variable<String>(previewPath.value);
    }
    if (fullResPath.present) {
      map['full_res_path'] = Variable<String>(fullResPath.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isRejected.present) {
      map['is_rejected'] = Variable<bool>(isRejected.value);
    }
    if (exifJson.present) {
      map['exif_json'] = Variable<String>(exifJson.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('fileName: $fileName, ')
          ..write('previewPath: $previewPath, ')
          ..write('fullResPath: $fullResPath, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isRejected: $isRejected, ')
          ..write('exifJson: $exifJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadQueueTable extends UploadQueue
    with TableInfo<$UploadQueueTable, UploadQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantMeta = const VerificationMeta(
    'variant',
  );
  @override
  late final GeneratedColumn<String> variant = GeneratedColumn<String>(
    'variant',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteFileIdMeta = const VerificationMeta(
    'remoteFileId',
  );
  @override
  late final GeneratedColumn<String> remoteFileId = GeneratedColumn<String>(
    'remote_file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    photoId,
    variant,
    status,
    retryCount,
    remoteFileId,
    progress,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadQueueData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_photoIdMeta);
    }
    if (data.containsKey('variant')) {
      context.handle(
        _variantMeta,
        variant.isAcceptableOrUnknown(data['variant']!, _variantMeta),
      );
    } else if (isInserting) {
      context.missing(_variantMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('remote_file_id')) {
      context.handle(
        _remoteFileIdMeta,
        remoteFileId.isAcceptableOrUnknown(
          data['remote_file_id']!,
          _remoteFileIdMeta,
        ),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadQueueData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      )!,
      variant: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      remoteFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_file_id'],
      ),
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
    );
  }

  @override
  $UploadQueueTable createAlias(String alias) {
    return $UploadQueueTable(attachedDatabase, alias);
  }
}

class UploadQueueData extends DataClass implements Insertable<UploadQueueData> {
  final String id;
  final String photoId;
  final String variant;
  final String status;
  final int retryCount;
  final String? remoteFileId;
  final double progress;
  const UploadQueueData({
    required this.id,
    required this.photoId,
    required this.variant,
    required this.status,
    required this.retryCount,
    this.remoteFileId,
    required this.progress,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['photo_id'] = Variable<String>(photoId);
    map['variant'] = Variable<String>(variant);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || remoteFileId != null) {
      map['remote_file_id'] = Variable<String>(remoteFileId);
    }
    map['progress'] = Variable<double>(progress);
    return map;
  }

  UploadQueueCompanion toCompanion(bool nullToAbsent) {
    return UploadQueueCompanion(
      id: Value(id),
      photoId: Value(photoId),
      variant: Value(variant),
      status: Value(status),
      retryCount: Value(retryCount),
      remoteFileId: remoteFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteFileId),
      progress: Value(progress),
    );
  }

  factory UploadQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadQueueData(
      id: serializer.fromJson<String>(json['id']),
      photoId: serializer.fromJson<String>(json['photoId']),
      variant: serializer.fromJson<String>(json['variant']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      remoteFileId: serializer.fromJson<String?>(json['remoteFileId']),
      progress: serializer.fromJson<double>(json['progress']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'photoId': serializer.toJson<String>(photoId),
      'variant': serializer.toJson<String>(variant),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'remoteFileId': serializer.toJson<String?>(remoteFileId),
      'progress': serializer.toJson<double>(progress),
    };
  }

  UploadQueueData copyWith({
    String? id,
    String? photoId,
    String? variant,
    String? status,
    int? retryCount,
    Value<String?> remoteFileId = const Value.absent(),
    double? progress,
  }) => UploadQueueData(
    id: id ?? this.id,
    photoId: photoId ?? this.photoId,
    variant: variant ?? this.variant,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    remoteFileId: remoteFileId.present ? remoteFileId.value : this.remoteFileId,
    progress: progress ?? this.progress,
  );
  UploadQueueData copyWithCompanion(UploadQueueCompanion data) {
    return UploadQueueData(
      id: data.id.present ? data.id.value : this.id,
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      variant: data.variant.present ? data.variant.value : this.variant,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      remoteFileId: data.remoteFileId.present
          ? data.remoteFileId.value
          : this.remoteFileId,
      progress: data.progress.present ? data.progress.value : this.progress,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadQueueData(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('variant: $variant, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('remoteFileId: $remoteFileId, ')
          ..write('progress: $progress')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    photoId,
    variant,
    status,
    retryCount,
    remoteFileId,
    progress,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadQueueData &&
          other.id == this.id &&
          other.photoId == this.photoId &&
          other.variant == this.variant &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.remoteFileId == this.remoteFileId &&
          other.progress == this.progress);
}

class UploadQueueCompanion extends UpdateCompanion<UploadQueueData> {
  final Value<String> id;
  final Value<String> photoId;
  final Value<String> variant;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<String?> remoteFileId;
  final Value<double> progress;
  final Value<int> rowid;
  const UploadQueueCompanion({
    this.id = const Value.absent(),
    this.photoId = const Value.absent(),
    this.variant = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.remoteFileId = const Value.absent(),
    this.progress = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadQueueCompanion.insert({
    required String id,
    required String photoId,
    required String variant,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.remoteFileId = const Value.absent(),
    this.progress = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       photoId = Value(photoId),
       variant = Value(variant);
  static Insertable<UploadQueueData> custom({
    Expression<String>? id,
    Expression<String>? photoId,
    Expression<String>? variant,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? remoteFileId,
    Expression<double>? progress,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (photoId != null) 'photo_id': photoId,
      if (variant != null) 'variant': variant,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (remoteFileId != null) 'remote_file_id': remoteFileId,
      if (progress != null) 'progress': progress,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? photoId,
    Value<String>? variant,
    Value<String>? status,
    Value<int>? retryCount,
    Value<String?>? remoteFileId,
    Value<double>? progress,
    Value<int>? rowid,
  }) {
    return UploadQueueCompanion(
      id: id ?? this.id,
      photoId: photoId ?? this.photoId,
      variant: variant ?? this.variant,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      remoteFileId: remoteFileId ?? this.remoteFileId,
      progress: progress ?? this.progress,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (variant.present) {
      map['variant'] = Variable<String>(variant.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (remoteFileId.present) {
      map['remote_file_id'] = Variable<String>(remoteFileId.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadQueueCompanion(')
          ..write('id: $id, ')
          ..write('photoId: $photoId, ')
          ..write('variant: $variant, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('remoteFileId: $remoteFileId, ')
          ..write('progress: $progress, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $UploadQueueTable uploadQueue = $UploadQueueTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    photos,
    uploadQueue,
  ];
}

typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      Value<String?> driveFolderId,
      Value<String?> activeLutId,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<String?> driveFolderId,
      Value<String?> activeLutId,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get driveFolderId => $composableBuilder(
    column: $table.driveFolderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeLutId => $composableBuilder(
    column: $table.activeLutId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get driveFolderId => $composableBuilder(
    column: $table.driveFolderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeLutId => $composableBuilder(
    column: $table.activeLutId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get driveFolderId => $composableBuilder(
    column: $table.driveFolderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activeLutId => $composableBuilder(
    column: $table.activeLutId,
    builder: (column) => column,
  );
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, BaseReferences<_$AppDatabase, $SessionsTable, Session>),
          Session,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> driveFolderId = const Value.absent(),
                Value<String?> activeLutId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                driveFolderId: driveFolderId,
                activeLutId: activeLutId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                Value<String?> driveFolderId = const Value.absent(),
                Value<String?> activeLutId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                driveFolderId: driveFolderId,
                activeLutId: activeLutId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, BaseReferences<_$AppDatabase, $SessionsTable, Session>),
      Session,
      PrefetchHooks Function()
    >;
typedef $$PhotosTableCreateCompanionBuilder =
    PhotosCompanion Function({
      required String id,
      required String sessionId,
      required String fileName,
      Value<String?> previewPath,
      Value<String?> fullResPath,
      Value<bool> isFavorite,
      Value<bool> isRejected,
      Value<String> exifJson,
      required DateTime capturedAt,
      Value<int> rowid,
    });
typedef $$PhotosTableUpdateCompanionBuilder =
    PhotosCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> fileName,
      Value<String?> previewPath,
      Value<String?> fullResPath,
      Value<bool> isFavorite,
      Value<bool> isRejected,
      Value<String> exifJson,
      Value<DateTime> capturedAt,
      Value<int> rowid,
    });

class $$PhotosTableFilterComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fullResPath => $composableBuilder(
    column: $table.fullResPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRejected => $composableBuilder(
    column: $table.isRejected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exifJson => $composableBuilder(
    column: $table.exifJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fullResPath => $composableBuilder(
    column: $table.fullResPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRejected => $composableBuilder(
    column: $table.isRejected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exifJson => $composableBuilder(
    column: $table.exifJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fullResPath => $composableBuilder(
    column: $table.fullResPath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRejected => $composableBuilder(
    column: $table.isRejected,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exifJson =>
      $composableBuilder(column: $table.exifJson, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );
}

class $$PhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhotosTable,
          Photo,
          $$PhotosTableFilterComposer,
          $$PhotosTableOrderingComposer,
          $$PhotosTableAnnotationComposer,
          $$PhotosTableCreateCompanionBuilder,
          $$PhotosTableUpdateCompanionBuilder,
          (Photo, BaseReferences<_$AppDatabase, $PhotosTable, Photo>),
          Photo,
          PrefetchHooks Function()
        > {
  $$PhotosTableTableManager(_$AppDatabase db, $PhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> previewPath = const Value.absent(),
                Value<String?> fullResPath = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isRejected = const Value.absent(),
                Value<String> exifJson = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion(
                id: id,
                sessionId: sessionId,
                fileName: fileName,
                previewPath: previewPath,
                fullResPath: fullResPath,
                isFavorite: isFavorite,
                isRejected: isRejected,
                exifJson: exifJson,
                capturedAt: capturedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String fileName,
                Value<String?> previewPath = const Value.absent(),
                Value<String?> fullResPath = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isRejected = const Value.absent(),
                Value<String> exifJson = const Value.absent(),
                required DateTime capturedAt,
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion.insert(
                id: id,
                sessionId: sessionId,
                fileName: fileName,
                previewPath: previewPath,
                fullResPath: fullResPath,
                isFavorite: isFavorite,
                isRejected: isRejected,
                exifJson: exifJson,
                capturedAt: capturedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhotosTable,
      Photo,
      $$PhotosTableFilterComposer,
      $$PhotosTableOrderingComposer,
      $$PhotosTableAnnotationComposer,
      $$PhotosTableCreateCompanionBuilder,
      $$PhotosTableUpdateCompanionBuilder,
      (Photo, BaseReferences<_$AppDatabase, $PhotosTable, Photo>),
      Photo,
      PrefetchHooks Function()
    >;
typedef $$UploadQueueTableCreateCompanionBuilder =
    UploadQueueCompanion Function({
      required String id,
      required String photoId,
      required String variant,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> remoteFileId,
      Value<double> progress,
      Value<int> rowid,
    });
typedef $$UploadQueueTableUpdateCompanionBuilder =
    UploadQueueCompanion Function({
      Value<String> id,
      Value<String> photoId,
      Value<String> variant,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> remoteFileId,
      Value<double> progress,
      Value<int> rowid,
    });

class $$UploadQueueTableFilterComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variant => $composableBuilder(
    column: $table.variant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variant => $composableBuilder(
    column: $table.variant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<String> get variant =>
      $composableBuilder(column: $table.variant, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteFileId => $composableBuilder(
    column: $table.remoteFileId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);
}

class $$UploadQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadQueueTable,
          UploadQueueData,
          $$UploadQueueTableFilterComposer,
          $$UploadQueueTableOrderingComposer,
          $$UploadQueueTableAnnotationComposer,
          $$UploadQueueTableCreateCompanionBuilder,
          $$UploadQueueTableUpdateCompanionBuilder,
          (
            UploadQueueData,
            BaseReferences<_$AppDatabase, $UploadQueueTable, UploadQueueData>,
          ),
          UploadQueueData,
          PrefetchHooks Function()
        > {
  $$UploadQueueTableTableManager(_$AppDatabase db, $UploadQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> photoId = const Value.absent(),
                Value<String> variant = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> remoteFileId = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadQueueCompanion(
                id: id,
                photoId: photoId,
                variant: variant,
                status: status,
                retryCount: retryCount,
                remoteFileId: remoteFileId,
                progress: progress,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String photoId,
                required String variant,
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> remoteFileId = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadQueueCompanion.insert(
                id: id,
                photoId: photoId,
                variant: variant,
                status: status,
                retryCount: retryCount,
                remoteFileId: remoteFileId,
                progress: progress,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadQueueTable,
      UploadQueueData,
      $$UploadQueueTableFilterComposer,
      $$UploadQueueTableOrderingComposer,
      $$UploadQueueTableAnnotationComposer,
      $$UploadQueueTableCreateCompanionBuilder,
      $$UploadQueueTableUpdateCompanionBuilder,
      (
        UploadQueueData,
        BaseReferences<_$AppDatabase, $UploadQueueTable, UploadQueueData>,
      ),
      UploadQueueData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$UploadQueueTableTableManager get uploadQueue =>
      $$UploadQueueTableTableManager(_db, _db.uploadQueue);
}
