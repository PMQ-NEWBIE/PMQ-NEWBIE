import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

const _schemaVersion = 2;

/// Cột thêm ở schema v2. Giữ ở một chỗ để onCreate và onUpgrade dùng chung.
const _measurementV2Cols = {
  'device_name': 'TEXT',
  'method': 'TEXT',
  'samples': 'INTEGER',
  'duration_ms': 'INTEGER',
  'min_kg': 'REAL',
  'max_kg': 'REAL',
  'raw': 'TEXT',
  'height_cm': 'REAL',
  'note': 'TEXT',
};
const _userV2Cols = {'sex': 'TEXT', 'birth_year': 'INTEGER'};

class AppDb {
  late Database _db;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'can_lo.db'),
      version: _schemaVersion,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            height_cm REAL,
            goal_kg REAL,
            goal_start_kg REAL,
            color INTEGER
          )''');
        await d.execute('''
          CREATE TABLE devices(
            id TEXT PRIMARY KEY,
            name TEXT,
            protocol TEXT,
            config TEXT,
            added_at INTEGER
          )''');
        await d.execute('''
          CREATE TABLE measurements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            weight_kg REAL NOT NULL,
            impedance INTEGER,
            measured_at INTEGER NOT NULL,
            device_id TEXT,
            source TEXT,
            ext_key TEXT UNIQUE
          )''');
        await d.execute(
            'CREATE INDEX idx_m_user ON measurements(user_id, measured_at)');
        await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
        await _addV2(d);
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) await _addV2(d);
      },
    );
  }

  Future<void> _addV2(Database d) async {
    for (final e in _measurementV2Cols.entries) {
      await d.execute('ALTER TABLE measurements ADD COLUMN ${e.key} ${e.value}');
    }
    for (final e in _userV2Cols.entries) {
      await d.execute('ALTER TABLE users ADD COLUMN ${e.key} ${e.value}');
    }
  }

  // Users
  Future<List<UserProfile>> users() async =>
      (await _db.query('users', orderBy: 'id')).map(UserProfile.fromMap).toList();

  Future<int> saveUser(UserProfile u) async {
    if (u.id == null) {
      final m = u.toMap()..remove('id');
      return u.id = await _db.insert('users', m);
    }
    await _db.update('users', u.toMap(), where: 'id=?', whereArgs: [u.id]);
    return u.id!;
  }

  Future<void> deleteUser(int id) async {
    await _db.transaction((t) async {
      await t.delete('measurements', where: 'user_id=?', whereArgs: [id]);
      await t.delete('users', where: 'id=?', whereArgs: [id]);
    });
  }

  // Devices
  Future<List<SavedDevice>> devices() async =>
      (await _db.query('devices', orderBy: 'added_at'))
          .map(SavedDevice.fromMap)
          .toList();

  Future<void> saveDevice(SavedDevice d) async => _db.insert(
      'devices', d.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteDevice(String id) async =>
      _db.delete('devices', where: 'id=?', whereArgs: [id]);

  // Measurements
  Future<List<Measurement>> measurements() async =>
      (await _db.query('measurements', orderBy: 'measured_at'))
          .map(Measurement.fromMap)
          .toList();

  /// Trả về null nếu bản ghi trùng ext_key (đã đồng bộ trước đó).
  Future<int?> insertMeasurement(Measurement m) async {
    final map = m.toMap()..remove('id');
    final id = await _db.insert('measurements', map,
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) return null;
    return m.id = id;
  }

  Future<void> updateMeasurement(Measurement m) async => _db.update(
      'measurements', m.toMap()..remove('id'),
      where: 'id=?', whereArgs: [m.id]);

  Future<void> deleteMeasurement(int id) async =>
      _db.delete('measurements', where: 'id=?', whereArgs: [id]);

  Future<void> deleteMeasurementsOfUser(int userId) async =>
      _db.delete('measurements', where: 'user_id=?', whereArgs: [userId]);

  Future<void> deleteAllMeasurements() async => _db.delete('measurements');

  // Settings
  Future<Map<String, String>> settings() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['k'] as String: (r['v'] as String?) ?? ''};
  }

  Future<void> setSetting(String k, String v) async => _db.insert(
      'settings', {'k': k, 'v': v},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
