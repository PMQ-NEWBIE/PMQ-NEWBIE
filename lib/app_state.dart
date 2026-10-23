import 'dart:async';

import 'package:flutter/material.dart';

import 'ble_service.dart';
import 'db.dart';
import 'fmt.dart';
import 'metrics.dart';
import 'models.dart';
import 'native.dart';
import 'protocols.dart';
import 'session.dart';

class LiveReading {
  final String deviceId;
  final double kg;
  final bool settled; // đã lưu vào lịch sử
  final double hold; // 0..1, tiến độ giữ yên trước khi chốt
  final DateTime at;
  LiveReading(this.deviceId, this.kg, this.settled, this.at, {this.hold = 0});
}

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
  bool backgroundOn = false;
  bool dismissedProfileHint = false;

  bool reminderOn = false;
  int reminderHour = 7;
  int reminderMinute = 0;
  int reminderDays = 0x7F; // bit0 = Thứ 2 ... bit6 = Chủ nhật

  /// Số đang đo. Tách riêng để mỗi gói Bluetooth chỉ vẽ lại thẻ số cân,
  /// không rebuild cả app.
  final ValueNotifier<LiveReading?> liveNotifier = ValueNotifier(null);
  LiveReading? get live => liveNotifier.value;
  set live(LiveReading? v) => liveNotifier.value = v;

  Measurement? justSaved; // để Home chạy hiệu ứng kết quả
  int syncedThisSession = 0;
  int importedFromBackground = 0;

  final Map<String, WeighSession> _sessions = {};
  Timer? _watchdog;

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
      backgroundOn = s['bg_on'] == '1';
      dismissedProfileHint = s['hint_profile'] == '0';
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
    await NativeBridge.setAppForeground(true);
    await importBackground();
    await _syncNative();
    if (devices.isNotEmpty) await ble.startScan();

    loading = false;
    notifyListeners();
  }

  // ---------- Vòng đời app ----------
  Future<void> onResumed() async {
    await NativeBridge.setAppForeground(true);
    await importBackground();
    if (devices.isNotEmpty) await ble.startScan();
  }

  Future<void> onPaused() async {
    await NativeBridge.setAppForeground(false);
    await ble.stopScan(keepWanted: true);
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
  SavedDevice? deviceById(String? id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> addDevice(SavedDevice d) async {
    await db.saveDevice(d);
    devices.removeWhere((x) => x.id == d.id);
    devices.add(d);
    ble.setWatched(devices);
    await ble.startScan();
    await _syncNative();
    notifyListeners();
  }

  Future<void> renameDevice(SavedDevice d, String name) async {
    d.name = name;
    await db.saveDevice(d);
    await _syncNative();
    notifyListeners();
  }

  Future<void> removeDevice(String id) async {
    await ble.disconnect(id);
    await db.deleteDevice(id);
    devices.removeWhere((d) => d.id == id);
    ble.setWatched(devices);
    await _syncNative();
    notifyListeners();
  }

  // ---------- Chạy nền ----------
  Future<void> setBackground(bool v) async {
    backgroundOn = v;
    await db.setSetting('bg_on', v ? '1' : '0');
    if (v) await NativeBridge.requestNotificationPermission();
    await _syncNative();
    notifyListeners();
  }

  Future<void> _syncNative() => NativeBridge.configureBackground(
        enabled: backgroundOn && devices.any((d) => !d.proto.needsConnection),
        devices: devices.map((d) => d.toNativeJson()).toList(),
        unitLb: unitLb,
      );

  /// Nhập các lần cân mà dịch vụ chạy nền đã ghi khi app đóng.
  Future<void> importBackground() async {
    final items = await NativeBridge.drainBackground();
    var added = 0;
    for (final b in items) {
      final dup = measurements.any((m) =>
          m.deviceId == b.deviceId &&
          (m.at.difference(b.at).inSeconds).abs() < 120 &&
          (m.weightKg - b.kg).abs() < 0.1);
      if (dup) continue;
      final m = Measurement(
        userId: _guessUser(b.kg),
        weightKg: b.kg,
        impedance: b.impedance,
        at: b.at,
        deviceId: b.deviceId,
        deviceName: deviceById(b.deviceId)?.name,
        source: 'bg',
        extKey: 'bg@${b.deviceId}@${b.at.millisecondsSinceEpoch}',
        method: CommitMethod.values.where((x) => x.name == b.method).firstOrNull,
        samples: b.samples,
        durationMs: b.durationMs,
        minKg: b.minKg,
        maxKg: b.maxKg,
        raw: b.raw,
      );
      m.heightCm = userById(m.userId)?.heightCm;
      if (await db.insertMeasurement(m) == null) continue;
      measurements.add(m);
      added++;
    }
    if (added > 0) {
      measurements.sort((a, b) => a.at.compareTo(b.at));
      importedFromBackground += added;
      notifyListeners();
    }
  }

  // ---------- Nhận số đo ----------
  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _sessions.forEach((id, s) {
        final c = s.checkSilence(now);
        if (c != null) _commit(id, c);
      });
      final l = live;
      if (l != null && now.difference(l.at) > const Duration(seconds: 8)) {
        live = null;
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
      _save(Measurement(
        weightKg: r.kg,
        impedance: r.impedance,
        at: r.at ?? now,
        deviceId: deviceId,
        source: 'gatt',
        extKey: ext,
        method: CommitMethod.gatt,
        samples: 1,
        raw: r.raw == null ? null : hex(r.raw!),
      ));
      return;
    }

    _startWatchdog();
    final s = _sessions.putIfAbsent(deviceId, () => WeighSession());
    final step = s.feed(r, now);
    if (step.ended) {
      if (live?.deviceId == deviceId) live = null;
    } else if (step.kg != null) {
      live = LiveReading(deviceId, step.kg!, step.saved, now, hold: step.hold);
    }
    if (step.commit != null) _commit(deviceId, step.commit!);
  }

  void _commit(String deviceId, SessionCommit c) {
    // Cân Xiaomi hay phát lại số cũ khi vừa thức: bỏ nếu y hệt số vừa lưu.
    final now = DateTime.now();
    final dup = measurements.any((m) =>
        m.deviceId == deviceId &&
        now.difference(m.at) < const Duration(minutes: 10) &&
        (m.weightKg - c.kg).abs() < 0.01);
    if (dup) return;
    if (live?.deviceId == deviceId) {
      live = LiveReading(deviceId, c.kg, true, now, hold: 1);
    }
    _save(Measurement(
      weightKg: double.parse(c.kg.toStringAsFixed(2)),
      impedance: c.impedance,
      at: now,
      deviceId: deviceId,
      source: 'adv',
      method: c.method,
      samples: c.samples,
      durationMs: c.durationMs,
      minKg: c.minKg,
      maxKg: c.maxKg,
      raw: c.raw == null ? null : hex(c.raw!),
    ));
  }

  /// Nút "Lưu luôn số này" khi tự chốt không ăn.
  void saveLiveNow() {
    final l = live;
    if (l == null) return;
    final s = _sessions[l.deviceId];
    final c = s?.forceCommit(DateTime.now()) ??
        SessionCommit(l.kg, CommitMethod.liveButton);
    _commit(l.deviceId, c);
  }

  Future<void> _save(Measurement m) async {
    m.userId ??= _guessUser(m.weightKg);
    m.deviceName ??= deviceById(m.deviceId)?.name;
    m.heightCm ??= userById(m.userId)?.heightCm;
    final id = await db.insertMeasurement(m);
    if (id == null) return; // bản ghi đã có (đồng bộ lặp)
    measurements.add(m);
    measurements.sort((a, b) => a.at.compareTo(b.at));
    if (m.source == 'gatt') syncedThisSession++;
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
    m.heightCm ??= userById(userId)?.heightCm;
    await db.updateMeasurement(m);
    notifyListeners();
  }

  Future<void> updateNote(Measurement m, String note) async {
    m.note = note.trim().isEmpty ? null : note.trim();
    await db.updateMeasurement(m);
    notifyListeners();
  }

  Future<void> addManual(double kg, DateTime at, int userId, {String? note}) =>
      _save(Measurement(
        userId: userId,
        weightKg: kg,
        at: at,
        source: 'manual',
        method: CommitMethod.manual,
        note: note,
      ));

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
  _Derived? _derived;

  @override
  void notifyListeners() {
    _derived = null; // dữ liệu có thể đã đổi, tính lại khi cần
    super.notifyListeners();
  }

  _Derived get _d => _derived ??= _Derived(measurements);

  List<Measurement> historyOf(int userId) => _d.byUser[userId] ?? const [];

  Measurement? latestFor(int userId) {
    final h = _d.byUser[userId];
    return (h == null || h.isEmpty) ? null : h.last;
  }

  Measurement? previousOf(Measurement m) => _d.prev[m];

  /// Trung bình 7 ngày tính tới lần cân [m] (cùng người).
  double? average7(Measurement m) => _d.avg7[m];

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
    final last = latestFor(u.id!);
    if (last == null) return null;
    final h = u.heightCm;
    if (h == null || h < 50) return last.bmi;
    final m = h / 100;
    return last.weightKg / (m * m);
  }

  double? bmrFor(UserProfile u, Measurement m) => bmrMifflin(
        weightKg: m.weightKg,
        heightCm: m.heightCm ?? u.heightCm,
        age: u.ageAt(m.at),
        sex: u.sex,
      );

  // ---------- Cài đặt ----------
  Future<void> dismissProfileHint() async {
    dismissedProfileHint = true;
    await db.setSetting('hint_profile', '0');
    notifyListeners();
  }

  Future<void> setUnitLb(bool v) async {
    unitLb = v;
    await db.setSetting('unit', v ? 'lb' : 'kg');
    await _syncNative();
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
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    String n(double? v, [int d = 2]) => v == null ? '' : v.toStringAsFixed(d);
    final b = StringBuffer('﻿');
    b.writeln([
      'Nguoi dung', 'Thoi gian', 'Buoi', 'Can nang (kg)', 'Can nang (lb)',
      'Chenh lan truoc (kg)', 'TB 7 ngay (kg)', 'BMI', 'Phan loai BMI (chau A)',
      'Nang luong nghi (kcal)', 'Tro khang (ohm)', 'Chieu cao (cm)', 'Thiet bi',
      'Nguon', 'Cach chot', 'Do tin cay', 'So goi', 'Thoi gian dung (s)',
      'Thap nhat (kg)', 'Cao nhat (kg)', 'Ghi chu', 'Byte tho',
    ].join(','));
    for (final m in measurements) {
      if (userId != null && m.userId != userId) continue;
      final u = userById(m.userId);
      final prev = previousOf(m);
      final avg = average7(m);
      final bmiV = m.bmi;
      final bmr = u == null ? null : bmrFor(u, m);
      b.writeln([
        q(u?.name ?? 'Chua gan'),
        '${m.at.year}-${two(m.at.month)}-${two(m.at.day)} ${two(m.at.hour)}:${two(m.at.minute)}',
        q(dayPart(m.at)),
        n(m.weightKg),
        n(m.weightKg / lbToKg),
        prev == null ? '' : n(m.weightKg - prev.weightKg),
        n(avg),
        n(bmiV, 1),
        q(bmiV == null ? null : bmiBandAsia(bmiV).label),
        n(bmr, 0),
        m.impedance?.toString() ?? '',
        n(m.heightCm, 0),
        q(m.deviceName),
        m.source,
        q(m.method?.label),
        m.confidence.name,
        m.samples?.toString() ?? '',
        m.durationMs == null ? '' : (m.durationMs! / 1000).toStringAsFixed(1),
        n(m.minKg),
        n(m.maxKg),
        q(m.note),
        q(m.raw),
      ].join(','));
    }
    return b.toString();
  }
}

/// Thống kê dẫn xuất, tính một lượt cho toàn bộ lịch sử.
class _Derived {
  final Map<int?, List<Measurement>> byUser = {};
  final Map<Measurement, Measurement?> prev = Map.identity();
  final Map<Measurement, double?> avg7 = Map.identity();

  _Derived(List<Measurement> all) {
    for (final m in all) {
      (byUser[m.userId] ??= []).add(m);
    }
    for (final list in byUser.values) {
      // list đã theo thời gian tăng dần vì measurements luôn được sort.
      var lo = 0;
      var sum = 0.0;
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        prev[m] = i == 0 ? null : list[i - 1];
        sum += m.weightKg;
        final from = m.at.subtract(const Duration(days: 7));
        while (lo < i && !list[lo].at.isAfter(from)) {
          sum -= list[lo].weightKg;
          lo++;
        }
        avg7[m] = sum / (i - lo + 1);
      }
    }
  }
}
