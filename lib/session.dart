import 'models.dart';
import 'protocols.dart';

/// Kết quả chốt của một phiên cân, kèm thống kê để lưu chi tiết.
class SessionCommit {
  final double kg;
  final CommitMethod method;
  final int? impedance;
  final int samples;
  final int durationMs;
  final double? minKg;
  final double? maxKg;
  final List<int>? raw;

  SessionCommit(
    this.kg,
    this.method, {
    this.impedance,
    this.samples = 1,
    this.durationMs = 0,
    this.minKg,
    this.maxKg,
    this.raw,
  });
}

/// Trạng thái sau mỗi gói, để giao diện hiển thị.
class SessionStep {
  final double? kg;
  final bool saved;
  final double hold;
  final bool ended;
  final SessionCommit? commit;
  const SessionStep(
      {this.kg, this.saved = false, this.hold = 0, this.ended = false, this.commit});
}

/// Một phiên cân: từ lúc có người đứng lên tới lúc bước xuống / cân ngừng phát.
///
/// Chốt số khi: cân báo ổn định, hoặc số đứng yên [holdNeed] với ít nhất 2 gói.
/// Nếu cả phiên không chốt được, lúc kết thúc lấy số được giữ lâu nhất.
/// Logic thuần Dart, không đụng Bluetooth, để test được.
class WeighSession {
  static const holdNeed = Duration(milliseconds: 1500);
  static const tolerance = 0.1; // kg, dao động vẫn tính là "đứng yên"
  static const minKg = 5.0;

  final Duration silence;
  WeighSession({this.silence = const Duration(seconds: 4)});

  bool active = false;
  DateTime _start = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPacket = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastKg;
  List<int>? _lastRaw;
  DateTime _holdStart = DateTime.fromMillisecondsSinceEpoch(0);
  int _holdPackets = 0;
  double? _bestKg;
  List<int>? _bestRaw;
  Duration _bestHold = Duration.zero;
  double? _committedKg;
  int? _impedance;
  int _samples = 0;
  double? _min;
  double? _max;

  double? _lastFinal;
  DateTime _lastFinalAt = DateTime.fromMillisecondsSinceEpoch(0);
  /// Đã thấy cân về 0 / bước xuống kể từ lần chốt trước: lần sau là cân mới thật.
  bool _sawReset = true;

  void _reset() {
    active = false;
    _lastKg = null;
    _lastRaw = null;
    _holdPackets = 0;
    _bestKg = null;
    _bestRaw = null;
    _bestHold = Duration.zero;
    _committedKg = null;
    _impedance = null;
    _samples = 0;
    _min = null;
    _max = null;
  }

  SessionStep feed(Reading r, DateTime now) {
    _lastPacket = now;
    if (r.removed || r.kg < 2) {
      _sawReset = true;
      final c = active ? _end(now) : null;
      return SessionStep(ended: true, commit: c);
    }
    if (r.kg < minKg || r.kg > 300) return const SessionStep();

    if (!active) {
      _reset();
      active = true;
      _start = now;
    }
    _samples++;
    _min = _min == null || r.kg < _min! ? r.kg : _min;
    _max = _max == null || r.kg > _max! ? r.kg : _max;
    if (r.impedance != null) _impedance = r.impedance;

    if (_lastKg == null || (r.kg - _lastKg!).abs() > tolerance) {
      _lastKg = r.kg;
      _holdStart = now;
      _holdPackets = 1;
    } else {
      _holdPackets++;
    }
    _lastRaw = r.raw;
    final held = now.difference(_holdStart);
    if (_bestKg == null || held >= _bestHold) {
      _bestHold = held;
      _bestKg = r.kg;
      _bestRaw = r.raw;
    }

    final saved = _committedKg != null && (r.kg - _committedKg!).abs() <= 0.5;
    SessionCommit? commit;
    if (!saved) {
      if (r.stable == true) {
        commit = _commit(r.kg, CommitMethod.scaleStable, now, r.raw);
      } else if (held >= holdNeed && _holdPackets >= 2) {
        commit = _commit(r.kg, CommitMethod.hold, now, r.raw);
      }
    }
    final hold = saved || r.stable == true
        ? 1.0
        : (held.inMilliseconds / holdNeed.inMilliseconds).clamp(0.0, 1.0);
    return SessionStep(
      kg: r.kg,
      saved: saved || commit != null,
      hold: commit != null ? 1.0 : hold,
      commit: commit,
    );
  }

  /// Gọi định kỳ: cân im lặng quá [silence] thì coi như phiên kết thúc.
  SessionCommit? checkSilence(DateTime now) {
    if (!active || now.difference(_lastPacket) <= silence) return null;
    return _end(now);
  }

  /// Người dùng bấm lưu tay giữa chừng.
  SessionCommit? forceCommit(DateTime now) {
    if (!active || _lastKg == null) return null;
    _lastFinal = null;
    return _commit(_lastKg!, CommitMethod.liveButton, now, _lastRaw);
  }

  SessionCommit? _end(DateTime now) {
    SessionCommit? c;
    if (active && _committedKg == null) {
      if (_bestKg != null && _bestHold >= const Duration(milliseconds: 300)) {
        c = _commit(_bestKg!, CommitMethod.sessionEnd, now, _bestRaw);
      } else if (_lastKg != null &&
          _lastPacket.difference(_start) >= const Duration(seconds: 2)) {
        c = _commit(_lastKg!, CommitMethod.sessionEnd, now, _lastRaw);
      }
    }
    _reset();
    return c;
  }

  SessionCommit? _commit(
      double kg, CommitMethod method, DateTime now, List<int>? raw) {
    _committedKg = kg;
    // Chỉ coi là trùng khi cân phát lại số cũ: chưa về 0 kể từ lần chốt trước
    // và cũng không có đoạn số tăng dần (người bước lên lại).
    final ramped = _min != null && _min! < kg - 1.0;
    if (!_sawReset &&
        !ramped &&
        _lastFinal != null &&
        (kg - _lastFinal!).abs() < 0.3 &&
        now.difference(_lastFinalAt) < const Duration(seconds: 90)) {
      return null;
    }
    _lastFinal = kg;
    _lastFinalAt = now;
    _sawReset = false;
    return SessionCommit(
      kg,
      method,
      impedance: _impedance,
      samples: _samples,
      durationMs: now.difference(_start).inMilliseconds,
      minKg: _min,
      maxKg: _max,
      raw: raw,
    );
  }
}
