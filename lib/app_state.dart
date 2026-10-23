import 'dart:async';

import 'package:flutter/material.dart';

import 'ble_service.dart';
import 'db.dart';
import 'models.dart';
import 'native.dart';
import 'protocols.dart';

class LiveReading {
  final String deviceId;
  final double kg;
  final bool settled; // đã lưu vào lịch sử
  final double hold; // 0..1, tiến độ giữ yên trước khi chốt
  final DateTime at;
  LiveReading(this.deviceId, this.kg, this.settled, this.at, {this.hold = 0});
}

/// Một phiên cân: từ lúc có người đứng lên tới lúc bước xuống / cân tắt.
class _Session {
  bool active = false;
  DateTime start = DateTime.now();
  DateTime lastPacket = DateTime.now();
  double? lastKg;
  DateTime holdStart = DateTime.now();
  int holdPackets = 0;
  double? bestKg;
  Duration bestHold = Duration.zero;
  double? committedKg;
  int? impedance;
  // Chống lưu trùng giữa các phiên.
  double? lastFinal;
  DateTime lastFinalAt = DateTime.fromMillisecondsSinceEpoch(0);

  void reset() {
    active = false;
    lastKg = null;
    holdPackets = 0;
    bestKg = null;
    bestHold = Duration.zero;
    committedKg = null;
    impedance = null;
  }
}

const _holdNeed = Duration(milliseconds: 1500);
const _silence = Duration(seconds: 4);
const _tol = 0.1;

const userPalette = [
  0xFF0F7A5A,
  0xFF2563EB,
  0xFFC2410C,
  0xFF9333EA,
  0xFFDB2777,
  0xFF0891B2,
];

class AppState extends ChangeNotifier {
  final AppDb db = AppDb();
  final BleService ble = BleService();

  bool loading = true;
  String? fatalError;

  List<UserProfile> users = [];
  List<SavedDevice> devices = [];
  List<Measurement> measurements = [];

  int? activeUserId;
  bool unitLb = false;
  ThemeMode themeMode = ThemeMode.system;
  bool autoAssign = true;

  bool reminderOn = false;
  int reminderHour = 7;
  int reminderMinute = 0;
  int reminderDays = 0x7F; // bit0 = Thứ 2 ... bit6 = Chủ nhật

  LiveReading? live;
  Measurement? justSaved; // để Home chạy hiệu ứng kết quả
  int syncedThisSession = 0;


  Future<void> load() async {
    try {
      await db.open();
      users = await db.users();
      if (users.isEmpty) {
        final u = UserProfile(name: 'Tôi', color: userPalette.first);
        await db.saveUser(u);
        users = [u];
      }
      devices = await db.devices();
      measurements = await db.measurements();
      final s = await db.settings();
      activeUserId = int.tryParse(s['active_user'] ?? '') ?? users.first.id;
      if (!users.any((u) => u.id == activeUserId)) activeUserId = users.first.id;
      unitLb = s['unit'] == 'lb';
      themeMode = ThemeMode.values.firstWhere((m) => m.name == s['theme'],
          orElse: () => ThemeMode.system);
      autoAssign = s['auto_assign'] != '0';
      reminderOn = s['rem_on'] == '1';
      reminderHour = int.tryParse(s['rem_h'] ?? '') ?? 7;
      reminderMinute = int.tryParse(s['rem_m'] ?? '') ?? 0;
      reminderDays = int.tryParse(s['rem_d'] ?? '') ?? 0x7F;
    } catch (e) {
      fatalError = 'Không mở được dữ liệu: $e';
    }

    ble.onReading = _onReading;
    await ble.init();
    ble.setWatched(devices);
    if (devices.isNotEmpty) await ble.startScan();

    loading = false;
    notifyListeners();
  }

  // ---------- Người dùng ----------
  UserProfile? get activeUser {
    for (final u in users) {
      if (u.id == activeUserId) return u;
    }
    return users.isEmpty ? null : users.first;
  }

  UserProfile? userById(int? id) {
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> setActiveUser(int id) async {
    activeUserId = id;
    await db.setSetting('active_user', '$id');
    notifyListeners();
  }

  Future<void> saveUser(UserProfile u) async {
    final old = u.id == null ? null : userById(u.id);
    if (u.goalKg != null && (old == null || old.goalKg != u.goalKg)) {
      u.goalStartKg = u.id == null ? null : latestFor(u.id!)?.weightKg;
    }
    if (u.goalKg == null) u.goalStartKg = null;
    final isNew = u.id == null;
    await db.saveUser(u);
    if (isNew) {
      users.add(u);
    } else {
      final i = users.indexWhere((x) => x.id == u.id);
      if (i >= 0) users[i] = u;
    }
    notifyListeners();
  }

  Future<void> deleteUser(int id) async {
    if (users.length <= 1) return;
    await db.deleteUser(id);
    users.removeWhere((u) => u.id == id);
    measurements.removeWhere((m) => m.userId == id);
    if (activeUserId == id) await setActiveUser(users.first.id!);
    notifyListeners();
  }

  int nextColor() => userPalette[users.length % userPalette.length];

  // ---------- Thiết bị ----------
  Future<void> addDevice(SavedDevice d) async {
    await db.saveDevice(d);
    devices.removeWhere((x) => x.id == d.id);
    devices.add(d);
    ble.setWatched(devices);
    await ble.startScan();
    notifyListeners();
  }

  Future<void> renameDevice(SavedDevice d, String name) async {
    d.name = name;
    await db.saveDevice(d);
    notifyListeners();
  }

  Future<void> removeDevice(String id) async {
    await ble.disconnect(id);
    await db.deleteDevice(id);
    devices.removeWhere((d) => d.id == id);
    ble.setWatched(devices);
    notifyListeners();
  }

  // ---------- Nhận số đo ----------
  final Map<String, _Session> _sessions = {};
  Timer? _watchdog;

  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _sessions.forEach((id, s) {
        if (s.active && now.difference(s.lastPacket) > _silence) {
          _endSession(id, s); // cân tắt màn hình / ngừng phát: chốt số tốt nhất
        }
      });
      final l = live;
      if (l != null && now.difference(l.at) > const Duration(seconds: 8)) {
        live = null;
        notifyListeners();
      }
    });
  }

  void _onReading(String deviceId, Reading r, {required bool fromGatt}) {
    final now = DateTime.now();
    if (fromGatt) {
      live = LiveReading(deviceId, r.kg, true, now, hold: 1);
      final ext = r.at != null
          ? '$deviceId@${r.at!.millisecondsSinceEpoch}@${(r.kg * 100).round()}'
          : null;
      _finalize(deviceId, r, 'gatt', ext);
      return;
    }

    _startWatchdog();
    final s = _sessions.putIfAbsent(deviceId, () => _Session());
    s.lastPacket = now;

    if (r.removed || r.kg < 2) {
      if (s.active) _endSession(deviceId, s);
      return;
    }
    if (r.kg < 5) return;

    if (!s.active) {
      s.reset();
      s.active = true;
      s.start = now;
    }
    if (s.lastKg == null || (r.kg - s.lastKg!).abs() > _tol) {
      s.lastKg = r.kg;
      s.holdStart = now;
      s.holdPackets = 1;
    } else {
      s.holdPackets++;
    }
    if (r.impedance != null) s.impedance = r.impedance;
    final held = now.difference(s.holdStart);
    if (s.bestKg == null || held >= s.bestHold) {
      s.bestHold = held;
      s.bestKg = r.kg;
    }

    final saved =
        s.committedKg != null && (r.kg - s.committedKg!).abs() <= 0.5;
    final ready =
        r.stable == true || (held >= _holdNeed && s.holdPackets >= 2);
    final progress = saved || r.stable == true
        ? 1.0
        : (held.inMilliseconds / _holdNeed.inMilliseconds).clamp(0.0, 1.0);
    live = LiveReading(deviceId, r.kg, saved, now, hold: progress);
    notifyListeners();

    if (ready && !saved) _commit(deviceId, s, r.kg);
  }

  void _endSession(String id, _Session s) {
    if (s.active && s.committedKg == null) {
      // Chưa chốt được trong lúc đứng: lấy số giữ lâu nhất, hoặc số cuối.
      if (s.bestKg != null && s.bestHold >= const Duration(milliseconds: 300)) {
        _commit(id, s, s.bestKg!);
      } else if (s.lastKg != null &&
          s.lastPacket.difference(s.start) >= const Duration(seconds: 2)) {
        _commit(id, s, s.lastKg!);
      }
    }
    s.reset();
    if (live?.deviceId == id) live = null;
    notifyListeners();
  }

  void _commit(String id, _Session s, double kg) {
    final now = DateTime.now();
    s.committedKg = kg;
    if (s.lastFinal != null &&
        (kg - s.lastFinal!).abs() < 0.3 &&
        now.difference(s.lastFinalAt) < const Duration(seconds: 90)) {
      return;
    }
    // Cân Xiaomi hay phát lại số cũ khi vừa thức: bỏ nếu y hệt số vừa lưu.
    final dup = measurements.any((m) =>
        m.deviceId == id &&
        now.difference(m.at) < const Duration(minutes: 10) &&
        (m.weightKg - kg).abs() < 0.01);
    if (dup) return;
    s.lastFinal = kg;
    s.lastFinalAt = now;
    if (live?.deviceId == id) {
      live = LiveReading(id, kg, true, now, hold: 1);
    }
    _finalize(id, Reading(kg, impedance: s.impedance), 'adv', null);
  }

  /// Nút "Lưu số này" trên màn hình khi tự chốt không ăn.
  void saveLiveNow() {
    final l = live;
    if (l == null) return;
    final s = _sessions.putIfAbsent(l.deviceId, () => _Session());
    s.lastFinal = null;
    _commit(l.deviceId, s, l.kg);
  }

  Future<void> _finalize(
      String deviceId, Reading r, String source, String? ext) async {
    final m = Measurement(
      userId: _guessUser(r.kg),
      weightKg: double.parse(r.kg.toStringAsFixed(2)),
      impedance: r.impedance,
      at: r.at ?? DateTime.now(),
      deviceId: deviceId,
      source: source,
      extKey: ext,
    );
    final id = await db.insertMeasurement(m);
    if (id == null) return; // bản ghi đã có (đồng bộ lặp)
    measurements.add(m);
    measurements.sort((a, b) => a.at.compareTo(b.at));
    if (source == 'gatt') syncedThisSession++;
    justSaved = m;
    notifyListeners();
  }

  int? _guessUser(double kg) {
    if (users.length == 1) return users.first.id;
    if (!autoAssign) return activeUserId;
    final scored = <MapEntry<int, double>>[];
    for (final u in users) {
      final last = latestFor(u.id!);
      if (last == null) continue;
      final diff = (kg - last.weightKg).abs();
      final tol = last.weightKg * 0.04 < 2.5 ? 2.5 : last.weightKg * 0.04;
      if (diff <= tol) scored.add(MapEntry(u.id!, diff));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => a.value.compareTo(b.value));
    if (scored.length == 1 || scored[1].value - scored[0].value > 1.5) {
      return scored.first.key;
    }
    return null;
  }

  List<Measurement> get pending =>
      measurements.where((m) => m.userId == null).toList();

  Future<void> assign(Measurement m, int userId) async {
    m.userId = userId;
    await db.updateMeasurementUser(m.id!, userId);
    notifyListeners();
  }

  Future<void> addManual(double kg, DateTime at, int userId) async {
    final m = Measurement(
        userId: userId, weightKg: kg, at: at, source: 'manual');
    await db.insertMeasurement(m);
    measurements.add(m);
    measurements.sort((a, b) => a.at.compareTo(b.at));
    justSaved = m;
    notifyListeners();
  }

  Future<void> deleteMeasurement(Measurement m) async {
    if (m.id != null) await db.deleteMeasurement(m.id!);
    measurements.remove(m);
    notifyListeners();
  }

  Future<void> restoreMeasurement(Measurement m) async {
    m.id = null;
    await db.insertMeasurement(m);
    measurements.add(m);
    measurements.sort((a, b) => a.at.compareTo(b.at));
    notifyListeners();
  }

  Future<void> deleteHistoryOf(int userId) async {
    await db.deleteMeasurementsOfUser(userId);
    measurements.removeWhere((m) => m.userId == userId);
    notifyListeners();
  }

  Future<void> deleteAllHistory() async {
    await db.deleteAllMeasurements();
    measurements.clear();
    notifyListeners();
  }

  // ---------- Thống kê ----------
  List<Measurement> historyOf(int userId) =>
      measurements.where((m) => m.userId == userId).toList();

  Measurement? latestFor(int userId) {
    for (var i = measurements.length - 1; i >= 0; i--) {
      if (measurements[i].userId == userId) return measurements[i];
    }
    return null;
  }

  Measurement? previousOf(Measurement m) {
    Measurement? prev;
    for (final x in measurements) {
      if (identical(x, m)) break;
      if (x.userId == m.userId) prev = x;
    }
    return prev;
  }

  /// Độ dốc hồi quy tuyến tính 30 ngày gần nhất, đơn vị kg/tuần.
  double? trendPerWeek(int userId) {
    final from = DateTime.now().subtract(const Duration(days: 30));
    final pts = historyOf(userId).where((m) => m.at.isAfter(from)).toList();
    if (pts.length < 2) return null;
    final span = pts.last.at.difference(pts.first.at).inHours;
    if (span < 24) return null;
    final t0 = pts.first.at.millisecondsSinceEpoch;
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    for (final p in pts) {
      final x = (p.at.millisecondsSinceEpoch - t0) / 86400000.0;
      sx += x;
      sy += p.weightKg;
      sxx += x * x;
      sxy += x * p.weightKg;
    }
    final n = pts.length.toDouble();
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return null;
    return (n * sxy - sx * sy) / den * 7;
  }

  /// 0..1, null nếu chưa đặt mục tiêu.
  double? goalProgress(UserProfile u) {
    if (u.goalKg == null) return null;
    final cur = latestFor(u.id!)?.weightKg;
    if (cur == null) return 0;
    final start = u.goalStartKg ?? historyOf(u.id!).first.weightKg;
    final total = start - u.goalKg!;
    if (total.abs() < 0.05) return 1;
    return ((start - cur) / total).clamp(0.0, 1.0);
  }

  double? bmi(UserProfile u) {
    final h = u.heightCm;
    final w = latestFor(u.id!)?.weightKg;
    if (h == null || h < 50 || w == null) return null;
    final m = h / 100;
    return w / (m * m);
  }

  // ---------- Cài đặt ----------
  Future<void> setUnitLb(bool v) async {
    unitLb = v;
    await db.setSetting('unit', v ? 'lb' : 'kg');
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await db.setSetting('theme', m.name);
    notifyListeners();
  }

  Future<void> setAutoAssign(bool v) async {
    autoAssign = v;
    await db.setSetting('auto_assign', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setReminder(
      {bool? on, int? hour, int? minute, int? days}) async {
    reminderOn = on ?? reminderOn;
    reminderHour = hour ?? reminderHour;
    reminderMinute = minute ?? reminderMinute;
    reminderDays = days ?? reminderDays;
    if (on == true) await NativeBridge.requestNotificationPermission();
    await db.setSetting('rem_on', reminderOn ? '1' : '0');
    await db.setSetting('rem_h', '$reminderHour');
    await db.setSetting('rem_m', '$reminderMinute');
    await db.setSetting('rem_d', '$reminderDays');
    await NativeBridge.setReminder(
      enabled: reminderOn && reminderDays != 0,
      hour: reminderHour,
      minute: reminderMinute,
      daysMask: reminderDays,
    );
    notifyListeners();
  }

  // ---------- Xuất CSV ----------
  String buildCsv({int? userId}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final b = StringBuffer('﻿');
    b.writeln('Nguoi dung,Thoi gian,Can nang (kg),Can nang (lb),Tro khang,Nguon');
    for (final m in measurements) {
      if (userId != null && m.userId != userId) continue;
      final u = userById(m.userId)?.name ?? 'Chua gan';
      final t =
          '${m.at.year}-${two(m.at.month)}-${two(m.at.day)} ${two(m.at.hour)}:${two(m.at.minute)}';
      final name = u.replaceAll('"', "'");
      b.writeln('"$name",$t,${m.weightKg.toStringAsFixed(2)},'
          '${(m.weightKg / lbToKg).toStringAsFixed(2)},${m.impedance ?? ''},${m.source}');
    }
    return b.toString();
  }
}
