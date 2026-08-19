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
      version: 2,
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
        sentAt INTEGER NOT NULL
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

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('request_logs');
    await db.delete('encounters');
    await db.delete('sent_notices');
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
    'status': log.status.name,
    'requestedAt': log.requestedAt.millisecondsSinceEpoch,
    'resolvedAt': log.resolvedAt?.millisecondsSinceEpoch,
    'body': log.body,
    'error': log.error,
  };

  RequestLog _rowToRequestLog(Map<String, dynamic> row) => RequestLog(
    id: row['id'] as String,
    encounterId: row['encounterId'] as String,
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
  };

  SentNotice _rowToSentNotice(Map<String, dynamic> row) => SentNotice(
    id: row['id'] as String,
    teaser: row['teaser'] as String,
    body: row['body'] as String,
    sentAt: DateTime.fromMillisecondsSinceEpoch(row['sentAt'] as int),
  );
}

final databaseServiceProvider = DatabaseService();
