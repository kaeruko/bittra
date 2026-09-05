import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bluetooth_models.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'bittora.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE encounters (
            id TEXT PRIMARY KEY,
            peerId TEXT NOT NULL,
            teaser TEXT NOT NULL,
            receivedAt INTEGER NOT NULL,
            dedupeKey TEXT NOT NULL,
            lastSeenAt INTEGER NOT NULL,
            count INTEGER NOT NULL,
            rssi INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE request_logs (
            id TEXT PRIMARY KEY,
            encounterId TEXT NOT NULL,
            encounterKey TEXT,
            teaser TEXT,
            status TEXT NOT NULL,
            requestedAt INTEGER NOT NULL,
            resolvedAt INTEGER,
            body TEXT,
            error TEXT
          )
        ''');
        await _createSentNoticesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSentNoticesTable(db);
        } else if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE sent_notices '
            'ADD COLUMN receivedCount INTEGER NOT NULL DEFAULT 0',
          );
        }

        if (oldVersion < 4) {
          await db.execute('ALTER TABLE request_logs ADD COLUMN teaser TEXT');
          await db.execute('''
            UPDATE request_logs
            SET teaser = COALESCE(
              (
                SELECT encounters.teaser
                FROM encounters
                WHERE encounters.id = request_logs.encounterId
                LIMIT 1
              ),
              (
                SELECT encounters.teaser
                FROM encounters
                WHERE encounters.peerId = request_logs.encounterId
                ORDER BY encounters.lastSeenAt DESC
                LIMIT 1
              )
            )
            WHERE teaser IS NULL
          ''');
        }

        if (oldVersion < 5) {
          await db.execute('ALTER TABLE request_logs ADD COLUMN encounterKey TEXT');
          await db.execute('''
            UPDATE request_logs
            SET encounterKey = COALESCE(
              (
                SELECT encounters.dedupeKey
                FROM encounters
                WHERE encounters.peerId = request_logs.encounterId
                  AND (
                    request_logs.teaser IS NULL OR
                    encounters.teaser = request_logs.teaser
                  )
                ORDER BY encounters.lastSeenAt DESC
                LIMIT 1
              ),
              (
                SELECT encounters.dedupeKey
                FROM encounters
                WHERE encounters.id = request_logs.encounterId
                  AND (
                    request_logs.teaser IS NULL OR
                    encounters.teaser = request_logs.teaser
                  )
                LIMIT 1
              )
            )
            WHERE encounterKey IS NULL
          ''');
        }
      },
    );
  }

  Future<void> _createSentNoticesTable(Database db) async {
    await db.execute('''
      CREATE TABLE sent_notices (
        id TEXT PRIMARY KEY,
        teaser TEXT NOT NULL,
        body TEXT NOT NULL,
        sentAt INTEGER NOT NULL,
        receivedCount INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // --- Encounter ---

  Future<List<Encounter>> loadEncounters() async {
    final db = await database;
    final rows = await db.query('encounters', orderBy: 'lastSeenAt DESC');
    return rows.map(_rowToEncounter).toList();
  }

  Future<void> upsertEncounter(Encounter e) async {
    final db = await database;
    await db.insert(
      'encounters',
      _encounterToRow(e),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceEncounterAndDeleteDuplicates(
    Encounter encounter, {
    required List<String> duplicateIds,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final duplicateId in duplicateIds) {
        if (duplicateId == encounter.id) {
          throw StateError(
            'Canonical encounter id was included in duplicateIds: $duplicateId',
          );
        }
        await transaction.delete(
          'encounters',
          where: 'id = ?',
          whereArgs: [duplicateId],
        );
      }
      await transaction.insert(
        'encounters',
        _encounterToRow(encounter),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // --- RequestLog ---

  Future<List<RequestLog>> loadRequestLogs() async {
    final db = await database;
    final rows = await db.query('request_logs', orderBy: 'requestedAt DESC');
    return rows.map(_rowToRequestLog).toList();
  }

  Future<void> upsertRequestLog(RequestLog log) async {
    final db = await database;
    await db.insert(
      'request_logs',
      _requestLogToRow(log),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- SentNotice ---

  Future<List<SentNotice>> loadSentNotices() async {
    final db = await database;
    final rows = await db.query('sent_notices', orderBy: 'sentAt DESC');
    return rows.map(_rowToSentNotice).toList();
  }

  Future<void> insertSentNotice(SentNotice notice) async {
    final db = await database;
    await db.insert(
      'sent_notices',
      _sentNoticeToRow(notice),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateSentNoticeReceivedCount(
    String noticeId,
    int receivedCount,
  ) async {
    final db = await database;
    final updatedRows = await db.update(
      'sent_notices',
      {'receivedCount': receivedCount},
      where: 'id = ?',
      whereArgs: [noticeId],
    );
    if (updatedRows != 1) {
      throw StateError(
        'Expected one sent notice row for $noticeId, updated $updatedRows',
      );
    }
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('request_logs');
      await transaction.delete('encounters');
      await transaction.delete('sent_notices');
    });
  }

  // --- Mappers ---

  Map<String, dynamic> _encounterToRow(Encounter e) => {
    'id': e.id,
    'peerId': e.peerId,
    'teaser': e.teaser,
    'receivedAt': e.receivedAt.millisecondsSinceEpoch,
    'dedupeKey': e.dedupeKey,
    'lastSeenAt': e.lastSeenAt.millisecondsSinceEpoch,
    'count': e.count,
    'rssi': e.rssi,
  };

  Encounter _rowToEncounter(Map<String, dynamic> row) => Encounter(
    id: row['id'] as String,
    peerId: row['peerId'] as String,
    teaser: row['teaser'] as String,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(row['receivedAt'] as int),
    dedupeKey: row['dedupeKey'] as String,
    lastSeenAt: DateTime.fromMillisecondsSinceEpoch(row['lastSeenAt'] as int),
    count: row['count'] as int,
    rssi: row['rssi'] as int,
  );

  Map<String, dynamic> _requestLogToRow(RequestLog log) => {
    'id': log.id,
    'encounterId': log.encounterId,
    'encounterKey': log.encounterKey,
    'teaser': log.teaser,
    'status': log.status.name,
    'requestedAt': log.requestedAt.millisecondsSinceEpoch,
    'resolvedAt': log.resolvedAt?.millisecondsSinceEpoch,
    'body': log.body,
    'error': log.error,
  };

  RequestLog _rowToRequestLog(Map<String, dynamic> row) => RequestLog(
    id: row['id'] as String,
    encounterId: row['encounterId'] as String,
    encounterKey: row['encounterKey'] as String?,
    teaser: row['teaser'] as String?,
    status: RequestStatus.values.byName(row['status'] as String),
    requestedAt: DateTime.fromMillisecondsSinceEpoch(row['requestedAt'] as int),
    resolvedAt: row['resolvedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(row['resolvedAt'] as int)
        : null,
    body: row['body'] as String?,
    error: row['error'] as String?,
  );

  Map<String, dynamic> _sentNoticeToRow(SentNotice notice) => {
    'id': notice.id,
    'teaser': notice.teaser,
    'body': notice.body,
    'sentAt': notice.sentAt.millisecondsSinceEpoch,
    'receivedCount': notice.receivedCount,
  };

  SentNotice _rowToSentNotice(Map<String, dynamic> row) => SentNotice(
    id: row['id'] as String,
    teaser: row['teaser'] as String,
    body: row['body'] as String,
    sentAt: DateTime.fromMillisecondsSinceEpoch(row['sentAt'] as int),
    receivedCount: row['receivedCount'] as int,
  );
}

final databaseServiceProvider = DatabaseService();
