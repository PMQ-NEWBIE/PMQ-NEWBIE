import 'dart:convert';

class UserProfile {
  int? id;
  String name;
  double? heightCm;
  double? goalKg;
  double? goalStartKg;
  int color;

  UserProfile({
    this.id,
    required this.name,
    this.heightCm,
    this.goalKg,
    this.goalStartKg,
    this.color = 0xFF0F7A5A,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'height_cm': heightCm,
        'goal_kg': goalKg,
        'goal_start_kg': goalStartKg,
        'color': color,
      };

  static UserProfile fromMap(Map<String, Object?> m) => UserProfile(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? 'Người dùng',
        heightCm: (m['height_cm'] as num?)?.toDouble(),
        goalKg: (m['goal_kg'] as num?)?.toDouble(),
        goalStartKg: (m['goal_start_kg'] as num?)?.toDouble(),
        color: (m['color'] as int?) ?? 0xFF0F7A5A,
      );
}

class Measurement {
  int? id;
  int? userId;
  double weightKg;
  int? impedance;
  DateTime at;
  String? deviceId;
  String source; // adv | gatt | manual
  String? extKey;

  Measurement({
    this.id,
    this.userId,
    required this.weightKg,
    this.impedance,
    required this.at,
    this.deviceId,
    this.source = 'manual',
    this.extKey,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'user_id': userId,
        'weight_kg': weightKg,
        'impedance': impedance,
        'measured_at': at.millisecondsSinceEpoch,
        'device_id': deviceId,
        'source': source,
        'ext_key': extKey,
      };

  static Measurement fromMap(Map<String, Object?> m) => Measurement(
        id: m['id'] as int?,
        userId: m['user_id'] as int?,
        weightKg: (m['weight_kg'] as num).toDouble(),
        impedance: m['impedance'] as int?,
        at: DateTime.fromMillisecondsSinceEpoch(m['measured_at'] as int),
        deviceId: m['device_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        extKey: m['ext_key'] as String?,
      );
}

/// Kiểu giao thức của cân.
enum Proto { miScale1, miScale2, gattStandard, learned }

extension ProtoX on Proto {
  String get label {
    switch (this) {
      case Proto.miScale1:
        return 'Xiaomi Mi Scale 1';
      case Proto.miScale2:
        return 'Xiaomi Mi Scale 2';
      case Proto.gattStandard:
        return 'Bluetooth Weight Scale chuẩn (kết nối)';
      case Proto.learned:
        return 'Tự dò byte';
    }
  }

  bool get needsConnection => this == Proto.gattStandard;
}

class SavedDevice {
  String id;
  String name;
  Proto proto;
  Map<String, dynamic> config;
  int addedAt;

  SavedDevice({
    required this.id,
    required this.name,
    required this.proto,
    Map<String, dynamic>? config,
    int? addedAt,
  })  : config = config ?? {},
        addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'protocol': proto.name,
        'config': jsonEncode(config),
        'added_at': addedAt,
      };

  static SavedDevice fromMap(Map<String, Object?> m) => SavedDevice(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Cân',
        proto: Proto.values.firstWhere(
          (p) => p.name == m['protocol'],
          orElse: () => Proto.learned,
        ),
        config: (jsonDecode((m['config'] as String?) ?? '{}') as Map)
            .cast<String, dynamic>(),
        addedAt: (m['added_at'] as int?) ?? 0,
      );
}
