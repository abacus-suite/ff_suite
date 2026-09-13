import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class QueuedItem {
  QueuedItem(this.uuid, this.payload);

  final String uuid;
  final Map<String, dynamic> payload;
}

/// SQLite outbox: pings and events wait here until the server accepts them.
/// Every item carries a uuid, so re-sending after a failure is safe.
class OfflineQueue {
  Database? _db;

  Future<Database> _open() async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'ff_queue.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE outbox (uuid TEXT PRIMARY KEY, kind TEXT NOT NULL, '
          'payload TEXT NOT NULL, created_at INTEGER NOT NULL)',
        );
      },
    );
  }

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
}
