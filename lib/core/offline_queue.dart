import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class QueuedItem {
  QueuedItem(this.uuid, this.payload);

  final String uuid;
  final Map<String, dynamic> payload;
}

/// Work done offline, waiting to be sent: one API request each.
class QueuedRequest {
  QueuedRequest({
    required this.uuid,
    required this.path,
    required this.body,
    required this.label,
    required this.createdAt,
    this.error,
  });

  final String uuid;
  final String path;
  final Map<String, dynamic> body;
  final String label;
  final DateTime createdAt;

  /// Set when the server refused it; it then waits for the person to retry or discard.
  final String? error;
}

/// SQLite on the phone, three tables:
/// - outbox: location pings and events, uploaded in batches by the tracker;
/// - requests: actions taken without network (punch, check-in, demand...), sent in order;
/// - cache: the last answer of every screen, shown when there is no network.
/// Everything carries a uuid, so sending twice is harmless.
class OfflineQueue {
  Database? _db;

  Future<Database> _open() async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'ff_queue.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE outbox (uuid TEXT PRIMARY KEY, kind TEXT NOT NULL, '
          'payload TEXT NOT NULL, created_at INTEGER NOT NULL)',
        );
        await _createV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
      },
    );
  }

  static Future<void> _createV2(Database db) async {
    await db.execute(
      'CREATE TABLE requests (uuid TEXT PRIMARY KEY, path TEXT NOT NULL, body TEXT NOT NULL, '
      'label TEXT NOT NULL, created_at INTEGER NOT NULL, error TEXT)',
    );
    await db.execute('CREATE TABLE cache (key TEXT PRIMARY KEY, body TEXT NOT NULL, saved_at INTEGER NOT NULL)');
  }

  // ------------------------------------------------------------------
  // Pings and events (tracker)
  // ------------------------------------------------------------------
  Future<void> add(String kind, Map<String, dynamic> payload) async {
    final db = await _open();
    await db.insert(
      'outbox',
      {
        'uuid': payload['uuid'],
        'kind': kind,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<QueuedItem>> take(String kind, int limit) async {
    final db = await _open();
    final rows = await db.query('outbox',
        where: 'kind = ?', whereArgs: [kind], orderBy: 'created_at', limit: limit);
    return rows
        .map((r) => QueuedItem(r['uuid'] as String, jsonDecode(r['payload'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> remove(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _open();
    final marks = List.filled(uuids.length, '?').join(',');
    await db.delete('outbox', where: 'uuid IN ($marks)', whereArgs: uuids);
  }

  Future<int> count() async {
    final db = await _open();
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;
  }

  // ------------------------------------------------------------------
  // Actions taken offline
  // ------------------------------------------------------------------
  Future<void> addRequest(String uuid, String path, Map<String, dynamic> body, String label) async {
    final db = await _open();
    await db.insert(
      'requests',
      {
        'uuid': uuid,
        'path': path,
        'body': jsonEncode(body),
        'label': label,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Oldest first: a check-in must reach the server before the demand taken during it.
  Future<List<QueuedRequest>> requests() async {
    final db = await _open();
    final rows = await db.query('requests', orderBy: 'created_at');
    return [
      for (final r in rows)
        QueuedRequest(
          uuid: r['uuid'] as String,
          path: r['path'] as String,
          body: jsonDecode(r['body'] as String) as Map<String, dynamic>,
          label: r['label'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          error: r['error'] as String?,
        ),
    ];
  }

  Future<void> removeRequest(String uuid) async {
    final db = await _open();
    await db.delete('requests', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> markRequest(String uuid, String? error) async {
    final db = await _open();
    await db.update('requests', {'error': error}, where: 'uuid = ?', whereArgs: [uuid]);
  }

  // ------------------------------------------------------------------
  // Last known answers
  // ------------------------------------------------------------------
  Future<void> saveCache(String key, Object? data) async {
    final db = await _open();
    await db.insert(
      'cache',
      {'key': key, 'body': jsonEncode(data), 'saved_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// (data, saved at) or null when this screen was never loaded online.
  Future<(Object?, DateTime)?> readCache(String key) async {
    final db = await _open();
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return (
      jsonDecode(rows.first['body'] as String),
      DateTime.fromMillisecondsSinceEpoch(rows.first['saved_at'] as int),
    );
  }

  Future<void> clearCache() async {
    final db = await _open();
    await db.delete('cache');
  }
}
