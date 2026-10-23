import 'models.dart';

const String svcWeightScale = '0000181d-0000-1000-8000-00805f9b34fb';
const String svcBodyComp = '0000181b-0000-1000-8000-00805f9b34fb';
const String chrWeightMeasurement = '00002a9d-0000-1000-8000-00805f9b34fb';

const double lbToKg = 0.45359237;

/// Chuẩn hoá UUID về dạng 128-bit chữ thường.
String normUuid(String s) {
  var t = s.toLowerCase().trim();
  if (t.startsWith('0x')) t = t.substring(2);
  if (t.length == 4) return '0000$t-0000-1000-8000-00805f9b34fb';
  if (t.length == 8) return '$t-0000-1000-8000-00805f9b34fb';
  return t;
}

String shortUuid(String full) {
  final m = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$')
      .firstMatch(full.toLowerCase());
  return m != null ? '0x${m.group(1)!.toUpperCase()}' : full;
}

/// Một gói quảng bá đã chuẩn hoá.
class AdvPacket {
  final Map<int, List<int>> mfr;
  final Map<String, List<int>> svc; // key: uuid 128-bit
  final List<String> serviceUuids; // 128-bit
  AdvPacket(this.mfr, this.svc, this.serviceUuids);

  /// Mọi luồng dữ liệu theo key ổn định: m:<id> hoặc s:<uuid>.
  Map<String, List<int>> get streams {
    final out = <String, List<int>>{};
    mfr.forEach((k, v) => out['m:$k'] = v);
    svc.forEach((k, v) => out['s:$k'] = v);
    return out;
  }
}

String streamLabel(String key) {
  if (key.startsWith('m:')) {
    final id = int.tryParse(key.substring(2)) ?? 0;
    return 'MFR 0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }
  if (key.startsWith('s:')) return 'SVC ${shortUuid(key.substring(2))}';
  return key;
}

class Reading {
  final double kg;
  final bool? stable; // null = giao thức không báo
  final bool removed;
  final int? impedance;
  final DateTime? at;
  Reading(this.kg, {this.stable, this.removed = false, this.impedance, this.at});
}

/// Mi Scale 1: service data 0x181D, 10 byte.
Reading? parseMi1(List<int> b) {
  if (b.length < 3) return null;
  final c = b[0];
  final raw = b[1] | (b[2] << 8);
  double kg;
  if ((c & 0x01) != 0) {
    kg = raw / 100 * lbToKg;
  } else if ((c & 0x10) != 0) {
    kg = raw / 100 * 0.5;
  } else {
    kg = raw / 200;
  }
  return Reading(kg, stable: (c & 0x20) != 0, removed: (c & 0x80) != 0);
}

/// Mi Body Composition Scale 2: service data 0x181B, 13 byte.
Reading? parseMi2(List<int> b) {
  if (b.length < 13) return null;
  final c0 = b[0];
  final c1 = b[1];
  final raw = b[11] | (b[12] << 8);
  final kg = (c0 & 0x01) != 0 ? raw / 100 * lbToKg : raw / 200;
  final hasImp = (c1 & 0x02) != 0;
  final imp = b[9] | (b[10] << 8);
  return Reading(
    kg,
    stable: (c1 & 0x20) != 0,
    removed: (c1 & 0x80) != 0,
    impedance: hasImp && imp > 0 && imp < 3000 ? imp : null,
  );
}

/// Weight Measurement chuẩn Bluetooth SIG (0x2A9D).
Reading? parseWeightMeasurement(List<int> b) {
  if (b.length < 3) return null;
  final flags = b[0];
  final raw = b[1] | (b[2] << 8);
  if (raw == 0xFFFF) return null;
  final imperial = (flags & 0x01) != 0;
  final kg = imperial ? raw * 0.01 * lbToKg : raw * 0.005;
  DateTime? at;
  var i = 3;
  if ((flags & 0x02) != 0 && b.length >= i + 7) {
    final y = b[i] | (b[i + 1] << 8);
    if (y > 2000 && y < 2100 && b[i + 2] >= 1 && b[i + 2] <= 12) {
      at = DateTime(y, b[i + 2], b[i + 3] == 0 ? 1 : b[i + 3], b[i + 4],
          b[i + 5], b[i + 6]);
    }
    i += 7;
  }
  return Reading(kg, stable: true, at: at);
}

/// Cấu hình dò byte: key luồng, offset, endian, hệ số chia.
class LearnedConfig {
  final String key;
  final int offset;
  final bool bigEndian;
  final double divisor;
  LearnedConfig(this.key, this.offset, this.bigEndian, this.divisor);

  Map<String, dynamic> toJson() =>
      {'key': key, 'offset': offset, 'be': bigEndian, 'div': divisor};

  static LearnedConfig? fromJson(Map<String, dynamic> j) {
    if (j['key'] == null) return null;
    return LearnedConfig(
      j['key'] as String,
      (j['offset'] as num).toInt(),
      (j['be'] as bool?) ?? false,
      (j['div'] as num).toDouble(),
    );
  }
}

Reading? parseLearned(AdvPacket p, LearnedConfig c) {
  final b = p.streams[c.key];
  if (b == null || c.offset + 1 >= b.length) return null;
  final raw = c.bigEndian
      ? (b[c.offset] << 8) | b[c.offset + 1]
      : b[c.offset] | (b[c.offset + 1] << 8);
  return Reading(raw / c.divisor);
}

Reading? parseAdv(SavedDevice d, AdvPacket p) {
  switch (d.proto) {
    case Proto.miScale1:
      final b = p.svc[svcWeightScale];
      return b == null ? null : parseMi1(b);
    case Proto.miScale2:
      final b = p.svc[svcBodyComp];
      return b == null ? null : parseMi2(b);
    case Proto.learned:
      final c = LearnedConfig.fromJson(d.config);
      return c == null ? null : parseLearned(p, c);
    case Proto.gattStandard:
      return null;
  }
}

/// Đoán giao thức từ gói quảng bá.
Proto? detectProto(AdvPacket p) {
  if ((p.svc[svcBodyComp]?.length ?? 0) >= 13) return Proto.miScale2;
  if ((p.svc[svcWeightScale]?.length ?? 0) >= 3) return Proto.miScale1;
  if (p.serviceUuids.contains(svcWeightScale)) return Proto.gattStandard;
  return null;
}

class Candidate {
  final LearnedConfig cfg;
  final double value;
  final bool match;
  Candidate(this.cfg, this.value, this.match);
}

/// Thử mọi offset / endian / hệ số, trả về giá trị nằm trong 2..250 kg.
List<Candidate> findCandidates(AdvPacket p, double? knownKg) {
  final out = <Candidate>[];
  p.streams.forEach((key, b) {
    for (var i = 0; i + 1 < b.length; i++) {
      final le = b[i] | (b[i + 1] << 8);
      final be = (b[i] << 8) | b[i + 1];
      for (final isBe in [false, true]) {
        final raw = isBe ? be : le;
        for (final div in [10.0, 100.0, 200.0]) {
          final v = raw / div;
          if (v < 2 || v > 250) continue;
          final match = knownKg != null && (v - knownKg).abs() <= 0.15;
          out.add(Candidate(LearnedConfig(key, i, isBe, div), v, match));
        }
      }
    }
  });
  out.sort((a, b) {
    if (a.match != b.match) return a.match ? -1 : 1;
    if (knownKg != null) {
      return (a.value - knownKg).abs().compareTo((b.value - knownKg).abs());
    }
    return 0;
  });
  return out;
}
