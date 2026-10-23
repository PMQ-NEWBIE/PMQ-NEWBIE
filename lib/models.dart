import 'dart:convert';

enum Sex { male, female }

class UserProfile {
  int? id;
  String name;
  double? heightCm;
  double? goalKg;
  double? goalStartKg;
  int color;
  Sex? sex;
  int? birthYear;

  UserProfile({
    this.id,
    required this.name,
    this.heightCm,
    this.goalKg,
    this.goalStartKg,
    this.color = 0xFF0F7A5A,
    this.sex,
    this.birthYear,
  });

  int? ageAt(DateTime t) => birthYear == null ? null : t.year - birthYear!;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'height_cm': heightCm,
        'goal_kg': goalKg,
        'goal_start_kg': goalStartKg,
        'color': color,
        'sex': sex?.name,
        'birth_year': birthYear,
      };

  static UserProfile fromMap(Map<String, Object?> m) => UserProfile(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? 'Người dùng',
        heightCm: (m['height_cm'] as num?)?.toDouble(),
        goalKg: (m['goal_kg'] as num?)?.toDouble(),
        goalStartKg: (m['goal_start_kg'] as num?)?.toDouble(),
        color: (m['color'] as int?) ?? 0xFF0F7A5A,
        sex: Sex.values.where((s) => s.name == m['sex']).firstOrNull,
        birthYear: m['birth_year'] as int?,
      );
}

/// Cách một số cân được chốt. Dùng để đánh giá độ tin cậy của bản ghi.
enum CommitMethod {
  scaleStable, // cân tự báo "đã ổn định"
  hold, // số đứng yên đủ lâu
  sessionEnd, // bước xuống / cân tắt, lấy số giữ lâu nhất
  liveButton, // bấm "Lưu luôn số này"
  gatt, // cân chuẩn gửi bản ghi hoàn chỉnh
  manual, // nhập tay
}

extension CommitMethodX on CommitMethod {
  String get label {
    switch (this) {
      case CommitMethod.scaleStable:
        return 'Cân báo đã ổn định';
      case CommitMethod.hold:
        return 'Số đứng yên đủ lâu';
      case CommitMethod.sessionEnd:
        return 'Chốt lúc bước xuống';
      case CommitMethod.liveButton:
        return 'Bấm lưu tay khi đang đo';
      case CommitMethod.gatt:
        return 'Cân gửi bản ghi chuẩn';
      case CommitMethod.manual:
        return 'Nhập tay';
    }
  }
}

enum Confidence { high, medium, low }

class Measurement {
  int? id;
  int? userId;
  double weightKg;
  int? impedance;
  DateTime at;
  String? deviceId;
  String source; // adv | gatt | manual | bg
  String? extKey;

  // Chi tiết phiên cân (schema v2).
  String? deviceName;
  CommitMethod? method;
  int? samples; // số gói nhận được trong phiên
  int? durationMs; // thời gian đứng trên cân
  double? minKg;
  double? maxKg;
  String? raw; // byte thô của gói dùng để chốt (hex)
  double? heightCm; // chiều cao lúc cân, để BMI không đổi khi sửa hồ sơ
  String? note;

  Measurement({
    this.id,
    this.userId,
    required this.weightKg,
    this.impedance,
    required this.at,
    this.deviceId,
    this.source = 'manual',
    this.extKey,
    this.deviceName,
    this.method,
    this.samples,
    this.durationMs,
    this.minKg,
    this.maxKg,
    this.raw,
    this.heightCm,
    this.note,
  });

  double? get bmi {
    final h = heightCm;
    if (h == null || h < 50) return null;
    final m = h / 100;
    return weightKg / (m * m);
  }

  /// Độ dao động trong phiên (kg).
  double? get spread =>
      (minKg != null && maxKg != null) ? (maxKg! - minKg!).abs() : null;

  Confidence get confidence {
    switch (method) {
      case CommitMethod.gatt:
      case CommitMethod.scaleStable:
      case CommitMethod.manual:
        return Confidence.high;
      case CommitMethod.hold:
        return (spread ?? 0) <= 0.3 ? Confidence.high : Confidence.medium;
      case CommitMethod.liveButton:
        return Confidence.medium;
      case CommitMethod.sessionEnd:
        return (samples ?? 0) >= 5 ? Confidence.medium : Confidence.low;
      case null:
        return Confidence.medium;
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'user_id': userId,
        'weight_kg': weightKg,
        'impedance': impedance,
        'measured_at': at.millisecondsSinceEpoch,
        'device_id': deviceId,
        'source': source,
        'ext_key': extKey,
        'device_name': deviceName,
        'method': method?.name,
        'samples': samples,
        'duration_ms': durationMs,
        'min_kg': minKg,
        'max_kg': maxKg,
        'raw': raw,
        'height_cm': heightCm,
        'note': note,
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
        deviceName: m['device_name'] as String?,
        method: CommitMethod.values.where((x) => x.name == m['method']).firstOrNull,
        samples: m['samples'] as int?,
        durationMs: m['duration_ms'] as int?,
        minKg: (m['min_kg'] as num?)?.toDouble(),
        maxKg: (m['max_kg'] as num?)?.toDouble(),
        raw: m['raw'] as String?,
        heightCm: (m['height_cm'] as num?)?.toDouble(),
        note: m['note'] as String?,
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

  Map<String, Object?> toNativeJson() =>
      {'id': id, 'name': name, 'proto': proto.name, 'config': config};

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
